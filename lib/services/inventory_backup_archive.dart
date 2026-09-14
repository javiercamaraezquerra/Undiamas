import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import 'hive_restore_service.dart';
import 'inventory_photo_store.dart';

/// Version 2 is a deliberately small ZIP subset: regular, uncompressed files,
/// a strict manifest, and exactly the JPEGs it references. JPEGs are already
/// compressed; rejecting ZIP compression also eliminates decompression bombs.
/// Photos are processed one at a time, never collected into a giant byte list.
class InventoryBackupArchive {
  InventoryBackupArchive({
    Future<Uint8List> Function(String id)? readPhoto,
    Future<void> Function(String id, Uint8List bytes)? validatePhoto,
    Future<void> Function(String id, Uint8List bytes)? importPhoto,
    Future<Directory> Function()? temporaryDirectory,
  })  : _readPhoto = readPhoto ?? InventoryPhotoStore.instance.read,
        _validatePhoto = validatePhoto ?? InventoryPhotoStore.validatePrepared,
        _importPhoto =
            importPhoto ?? InventoryPhotoStore.instance.importPrepared,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  static const maxArchiveBytes = 512 * 1024 * 1024;
  static const maxManifestBytes = 16 * 1024 * 1024;
  static const maxPhotos = 5000;
  static const _maxDirectoryBytes = 2 * 1024 * 1024;
  static const _temporaryPrefix = 'udm_backup_work_';
  static const _manifestName = 'manifest.json';
  final Future<Uint8List> Function(String id) _readPhoto;
  final Future<void> Function(String id, Uint8List bytes) _validatePhoto;
  final Future<void> Function(String id, Uint8List bytes) _importPhoto;
  final Future<Directory> Function() _temporaryDirectory;

  /// The directory is private app cache, and removed on all ordinary exits.
  /// Startup removes abandoned workspaces before admitting backup operations.
  Future<T> withWorkspace<T>(
      Future<T> Function(Directory directory) action) async {
    final root = await _temporaryDirectory();
    await root.create(recursive: true);
    final directory = await root.createTemp(_temporaryPrefix);
    try {
      return await action(directory);
    } finally {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  /// Call once on startup, never while a backup is in progress. Does not touch
  /// the photo store, user files, or other cache directories.
  Future<void> cleanAbandonedWorkspaces() async {
    final root = await _temporaryDirectory();
    if (!await root.exists()) return;
    await for (final entity in root.list(followLinks: false)) {
      final name =
          entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (entity is Directory && name.startsWith(_temporaryPrefix)) {
        await entity.delete(recursive: true);
      }
    }
  }

  /// Accept the legacy public map API, but always write a v2 archive. Deep
  /// copying also prevents asynchronous changes to an export during upload.
  static Map<String, dynamic> version2(Map<String, dynamic> source) {
    HiveRestoreService.prepare(source);
    final detached = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
    if (!detached.containsKey('version')) {
      detached['version'] = 2;
      for (final entry in detached['diary'] as List) {
        (entry as Map<String, dynamic>)['photoId'] = null;
      }
    }
    HiveRestoreService.prepare(detached);
    return detached;
  }

  Future<File> create(Map<String, dynamic> source, Directory workspace) async {
    final manifest = version2(source);
    final prepared = HiveRestoreService.prepare(manifest);
    final ids = prepared.photoIds.toList()..sort();
    if (ids.length > maxPhotos) {
      throw const FormatException('La copia contiene demasiadas fotos.');
    }
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    if (manifestBytes.length > maxManifestBytes) {
      throw const FormatException(
          'El Inventario supera el tamaño de copia admitido.');
    }
    final file = File('${workspace.path}${Platform.pathSeparator}backup.zip');
    final encoder = ZipFileEncoder()
      ..create(file.path, level: ZipFileEncoder.store);
    var total = manifestBytes.length;
    try {
      encoder.addArchiveFile(
          ArchiveFile(_manifestName, manifestBytes.length, manifestBytes)
            ..compression = CompressionType.none);
      for (final id in ids) {
        final bytes = await _readPhoto(id);
        await _validatePhoto(id, bytes);
        total += bytes.length;
        // Include a generous bound for local + central directory headers.
        if (total + (ids.length + 1) * 512 + 22 > maxArchiveBytes) {
          throw const FormatException(
              'La copia con fotos supera el límite de 512 MB.');
        }
        encoder.addArchiveFile(
            ArchiveFile('photos/$id.jpg', bytes.length, bytes)
              ..compression = CompressionType.none);
      }
    } finally {
      await encoder.close();
    }
    if (await file.length() > maxArchiveBytes) {
      throw const FormatException(
          'La copia con fotos supera el límite de 512 MB.');
    }
    return file;
  }

  /// Validates every file before importing the first immutable photo. No Hive
  /// data is changed here. A failed import may leave safe, unreferenced blobs;
  /// existing photos must remain available for the restore undo journal.
  Future<Map<String, dynamic>> read(File file) async {
    await _preflight(file);
    final input = InputFileStream(file.path);
    try {
      final directory = ZipDirectory()..read(input);
      final headers = <String, ZipFileHeader>{};
      var total = 0;
      for (final header in directory.fileHeaders) {
        final name = header.filename;
        final isManifest = name == _manifestName;
        final photoMatch =
            RegExp(r'^photos/([a-f0-9]{64})\.jpg$').firstMatch(name);
        final size = header.uncompressedSize;
        final local = header.file;
        final type = (header.externalFileAttributes >> 16) & 0xf000;
        if ((!isManifest && photoMatch == null) ||
            headers.containsKey(name) ||
            header.compressionMethod != ZipFile.zipCompressionStore ||
            local == null ||
            local.compressionMethod != CompressionType.none ||
            (header.generalPurposeBitFlag & ~0x800) != 0 ||
            (local.flags & ~0x800) != 0 ||
            (type != 0 && type != 0x8000) ||
            header.diskNumberStart != 0 ||
            size <= 0 ||
            header.compressedSize != size ||
            local.compressedSize != size ||
            local.uncompressedSize != size ||
            local.getStream(decompress: false).length != size ||
            size >
                (isManifest
                    ? maxManifestBytes
                    : InventoryPhotoStore.maxPhotoBytes)) {
          throw const FormatException(
              'La copia contiene un archivo no válido o no compatible.');
        }
        total += size;
        if (total > maxArchiveBytes) {
          throw const FormatException('La copia supera el tamaño admitido.');
        }
        headers[name] = header;
      }
      final manifestHeader = headers[_manifestName];
      if (manifestHeader == null) {
        throw const FormatException('Falta el índice de la copia.');
      }
      final decoded = jsonDecode(utf8.decode(_bytes(manifestHeader)));
      if (decoded is! Map<String, dynamic> || !decoded.containsKey('version')) {
        throw const FormatException('La versión de la copia no es válida.');
      }
      final prepared = HiveRestoreService.prepare(decoded);
      final ids = prepared.photoIds.toList()..sort();
      if (ids.length > maxPhotos ||
          headers.length != ids.length + 1 ||
          ids.any((id) => !headers.containsKey('photos/$id.jpg'))) {
        throw const FormatException(
            'La copia no contiene exactamente todas las fotos del Inventario.');
      }
      for (final id in ids) {
        await _validatePhoto(id, _bytes(headers['photos/$id.jpg']!));
      }
      // Second pass only after the WHOLE copy passed validation. rawContent
      // reads a bounded photo without caching every JPEG in ZipFile.content.
      for (final id in ids) {
        await _importPhoto(id, _bytes(headers['photos/$id.jpg']!));
      }
      return decoded;
    } finally {
      await input.close();
    }
  }

  static Uint8List _bytes(ZipFileHeader header) {
    final bytes = header.file!.getRawContent();
    if (getCrc32(bytes) != header.crc32 || header.file!.crc32 != header.crc32) {
      throw const FormatException('La copia contiene un archivo dañado.');
    }
    return bytes;
  }

  /// Bound the directory before the ZIP package allocates it. This format
  /// never needs ZIP64, comments, split archives, encryption or compression.
  static Future<void> _preflight(File file) async {
    final length = await file.length();
    if (length < 22 || length > maxArchiveBytes) {
      throw const FormatException('El tamaño de la copia no es válido.');
    }
    final handle = await file.open();
    try {
      await handle.setPosition(length - 22);
      final tail = ByteData.sublistView(await handle.read(22));
      final count = tail.getUint16(10, Endian.little);
      final directorySize = tail.getUint32(12, Endian.little);
      final directoryOffset = tail.getUint32(16, Endian.little);
      if (tail.getUint32(0, Endian.little) != 0x06054b50 ||
          tail.getUint16(4, Endian.little) != 0 ||
          tail.getUint16(6, Endian.little) != 0 ||
          tail.getUint16(8, Endian.little) != count ||
          tail.getUint16(20, Endian.little) != 0 ||
          count < 1 ||
          count > maxPhotos + 1 ||
          directorySize < count * 46 ||
          directorySize > _maxDirectoryBytes ||
          directoryOffset + directorySize != length - 22) {
        throw const FormatException(
            'El archivo de copia no es compatible o está dañado.');
      }
      // Parse fixed central-directory records without decoding content. This
      // prevents duplicate EOCD tricks and huge/overlapping entry allocations.
      await handle.setPosition(directoryOffset);
      final central = ByteData.sublistView(await handle.read(directorySize));
      var offset = 0;
      final ranges = <List<int>>[];
      for (var i = 0; i < count; i++) {
        if (offset + 46 > central.lengthInBytes ||
            central.getUint32(offset, Endian.little) != 0x02014b50) {
          throw const FormatException('El índice de la copia está dañado.');
        }
        final compressed = central.getUint32(offset + 20, Endian.little);
        final uncompressed = central.getUint32(offset + 24, Endian.little);
        final nameLength = central.getUint16(offset + 28, Endian.little);
        final extraLength = central.getUint16(offset + 30, Endian.little);
        final commentLength = central.getUint16(offset + 32, Endian.little);
        final localOffset = central.getUint32(offset + 42, Endian.little);
        if (compressed != uncompressed ||
            uncompressed > maxManifestBytes ||
            central.getUint16(offset + 10, Endian.little) != 0 ||
            nameLength < 1 ||
            nameLength > 80 ||
            extraLength != 0 ||
            commentLength != 0 ||
            localOffset + 30 + nameLength + compressed > directoryOffset) {
          throw const FormatException('Una sección de la copia no es válida.');
        }
        if (offset + 46 + nameLength > central.lengthInBytes) {
          throw const FormatException('El índice de la copia está incompleto.');
        }
        await handle.setPosition(localOffset);
        final local = ByteData.sublistView(await handle.read(30 + nameLength));
        if (local.lengthInBytes != 30 + nameLength ||
            local.getUint32(0, Endian.little) != 0x04034b50 ||
            local.getUint16(6, Endian.little) !=
                central.getUint16(offset + 8, Endian.little) ||
            local.getUint16(8, Endian.little) != 0 ||
            local.getUint32(14, Endian.little) !=
                central.getUint32(offset + 16, Endian.little) ||
            local.getUint32(18, Endian.little) != compressed ||
            local.getUint32(22, Endian.little) != uncompressed ||
            local.getUint16(26, Endian.little) != nameLength ||
            local.getUint16(28, Endian.little) != 0) {
          throw const FormatException('Una cabecera de la copia no coincide.');
        }
        for (var index = 0; index < nameLength; index++) {
          if (local.getUint8(30 + index) !=
              central.getUint8(offset + 46 + index)) {
            throw const FormatException('El nombre de un archivo no coincide.');
          }
        }
        ranges.add([localOffset, localOffset + 30 + nameLength + compressed]);
        offset += 46 + nameLength + extraLength + commentLength;
      }
      if (offset != directorySize) {
        throw const FormatException('El índice de la copia no coincide.');
      }
      ranges.sort((a, b) => a.first.compareTo(b.first));
      var end = 0;
      for (final range in ranges) {
        if (range.first != end) {
          throw const FormatException(
              'La copia contiene secciones solapadas o inesperadas.');
        }
        end = range.last;
      }
      if (end != directoryOffset) {
        throw const FormatException('La copia contiene datos inesperados.');
      }
    } finally {
      await handle.close();
    }
  }
}
