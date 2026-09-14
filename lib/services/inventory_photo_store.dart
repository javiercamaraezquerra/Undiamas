import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'encryption_service.dart';
import 'inventory_encrypted_file.dart';

class InventoryPhotoException implements Exception {
  const InventoryPhotoException(this.message);
  final String message;
  @override
  String toString() => message;
}

class InventoryPhotoSizeException extends InventoryPhotoException {
  const InventoryPhotoSizeException()
      : super('Esta foto es demasiado grande. '
            'Elige una de hasta 16 MB y 16 megapíxeles.');
}

/// Private, encrypted, content-addressed copies of inventory photographs.
/// A gallery original is never moved, modified or deleted by this service.
class InventoryPhotoStore {
  InventoryPhotoStore({
    Directory? directory,
    Future<Directory> Function()? directoryProvider,
    Uint8List? key,
    Future<Uint8List> Function()? keyProvider,
    Future<void> Function(String)? beforeStep,
  }) : _files = InventoryEncryptedFile(
          directoryProvider: directoryProvider ??
              (directory != null ? () async => directory : _defaultDirectory),
          keyProvider: keyProvider ??
              (key != null ? () async => key : EncryptionService.getRawKey),
          purpose: 'inventory-photo',
          beforeStep: beforeStep,
        );

  static final instance = InventoryPhotoStore();
  static const maxPhotoBytes = 2 * 1024 * 1024;
  static const maxPhotoDimension = 1600;
  static const maxSourceBytes = 16 * 1024 * 1024;
  static const maxSourcePixels = 16 * 1000 * 1000;
  static const maxSourceDimension = 8192;
  static const targetPhotoBytes = 700 * 1024;
  static final _idPattern = RegExp(r'^[0-9a-f]{64}$');

  final InventoryEncryptedFile _files;
  Future<void> _pending = Future<void>.value();

  static bool isValidId(String id) => _idPattern.hasMatch(id);

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}inventory_photos');

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<String> importImage(Uint8List source) async {
    if (source.length > maxSourceBytes) {
      throw const InventoryPhotoSizeException();
    }
    if (source.isEmpty) {
      throw const InventoryPhotoException(
          'La imagen está vacía o no se puede leer. Elige otra foto.');
    }
    final jpeg = await compute(_normalizeImage, source);
    final id = hashes.sha256.convert(jpeg).toString();
    await importPrepared(id, jpeg);
    return id;
  }

  /// Checks an incoming backup completely before the restore writes any media.
  static Future<void> validatePrepared(String id, Uint8List jpeg) async {
    _requireId(id);
    if (jpeg.isEmpty || jpeg.length > maxPhotoBytes) {
      throw const InventoryPhotoException(
          'La fotografía tiene un tamaño inválido.');
    }
    await compute(_validatePreparedImage, <Object>[id, jpeg]);
  }

  Future<void> importPrepared(String id, Uint8List jpeg) async {
    if (jpeg.isEmpty || jpeg.length > maxPhotoBytes) {
      throw const InventoryPhotoException(
          'La fotografía tiene un tamaño inválido.');
    }
    final prepared = Uint8List.fromList(jpeg);
    await validatePrepared(id, prepared);
    await _exclusive(() async {
      try {
        final existing = await _read(id);
        if (listEquals(existing, prepared)) return;
      } on FileSystemException {
        rethrow;
      } on Object {
        // A validated backup can repair a corrupt envelope. The replacement
        // is committed atomically; a failed write preserves the old bytes.
      }
      await _files.write('$id.udm', prepared);
    });
  }

  Future<Uint8List> read(String id) {
    _requireId(id);
    return _exclusive(() => _read(id));
  }

  Future<Uint8List> _read(String id) async {
    final Uint8List? jpeg;
    try {
      jpeg = await _files.read('$id.udm', maxBytes: maxPhotoBytes);
    } on FileSystemException {
      rethrow;
    } on Object {
      throw const InventoryPhotoException(
          'No se puede leer esta foto de forma segura. Conserva tu copia de seguridad.');
    }
    if (jpeg == null) {
      throw const InventoryPhotoException(
          'No se encuentra la fotografía guardada.');
    }
    await compute(_verifyStoredImage, <Object>[id, jpeg]);
    return jpeg;
  }

  Future<void> delete(String id) {
    _requireId(id);
    return _exclusive(() => _files.delete('$id.udm'));
  }

  /// Only call after retaining IDs from diary, draft AND restore recovery.
  Future<void> prune(Set<String> retainedIds) {
    final retained = Set<String>.unmodifiable(retainedIds);
    for (final id in retained) {
      _requireId(id);
    }
    return _exclusive(() async {
      final directory = await _files.directory();
      if (!await directory.exists()) return;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.endsWith('.udm')) {
          final id = name.substring(0, name.length - 4);
          if (isValidId(id) && !retained.contains(id)) await entity.delete();
        } else if (RegExp(r'^[0-9a-f]{64}\.udm\.[0-9a-f]{24}\.tmp$')
            .hasMatch(name)) {
          await entity.delete();
        }
      }
    });
  }

  Future<void> clear() => prune(<String>{});

  static void _requireId(String id) {
    if (!isValidId(id)) {
      throw const InventoryPhotoException(
          'La referencia de la fotografía no es válida.');
    }
  }
}

Uint8List _normalizeImage(Uint8List source) {
  try {
    final header = _inspect(source, prepared: false);
    final decoder = switch (header.format) {
      _PhotoFormat.jpeg => img.JpegDecoder(),
      _PhotoFormat.png => img.PngDecoder(),
      _PhotoFormat.webp => img.WebPDecoder(),
    };
    final sanitized = _sanitizeSource(source, header.format);
    if (header.format == _PhotoFormat.png) {
      _checkPngInflation(sanitized.bytes);
    }
    var decoded = decoder.decode(sanitized.bytes, frame: 0);
    if (decoded == null) throw const FormatException('No image');
    if (decoded.width * decoded.height > InventoryPhotoStore.maxSourcePixels) {
      throw const FormatException('Invalid decoded dimensions');
    }
    if (decoded.width > InventoryPhotoStore.maxPhotoDimension ||
        decoded.height > InventoryPhotoStore.maxPhotoDimension) {
      decoded = img.copyResize(decoded,
          width: decoded.width >= decoded.height
              ? InventoryPhotoStore.maxPhotoDimension
              : null,
          height: decoded.height > decoded.width
              ? InventoryPhotoStore.maxPhotoDimension
              : null,
          interpolation: img.Interpolation.average);
    }
    // Metadata is stripped before decoding. Only a bounded IFD0 orientation
    // value is retained, then baked into the reduced pixel image.
    if (sanitized.orientation != 1) {
      decoded.exif.imageIfd.orientation = sanitized.orientation;
      decoded = img.bakeOrientation(decoded);
    }
    // Rebuild pixels into RGB: EXIF, GPS, comments and embedded thumbnails
    // are not copied. Transparent screenshots have a neutral white backing.
    final clean = img.Image(width: decoded.width, height: decoded.height);
    img.fill(clean, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(clean, decoded);
    var jpeg = img.encodeJpg(clean, quality: 85);
    for (final quality in const [76, 66, 55]) {
      if (jpeg.length <= InventoryPhotoStore.targetPhotoBytes) break;
      jpeg = img.encodeJpg(clean, quality: quality);
    }
    if (jpeg.length > InventoryPhotoStore.maxPhotoBytes) {
      throw const InventoryPhotoException(
          'No se ha podido reducir esta fotografía. Elige otra imagen.');
    }
    return jpeg;
  } on InventoryPhotoException {
    rethrow;
  } on Object {
    throw const InventoryPhotoException(
        'No se puede preparar esta imagen. Prueba con una foto JPEG, PNG o WebP.');
  }
}

void _validatePreparedImage(List<Object> request) {
  _verifyStoredImage(request);
  final jpeg = request[1] as Uint8List;
  try {
    final header = _inspect(jpeg, prepared: true);
    final decoded = img.JpegDecoder().decode(jpeg, frame: 0);
    if (decoded == null ||
        decoded.width != header.width ||
        decoded.height != header.height ||
        !decoded.exif.isEmpty) {
      throw const FormatException('Invalid normalized photograph');
    }
  } on Object {
    throw const InventoryPhotoException(
        'La fotografía guardada no tiene un formato válido.');
  }
}

void _verifyStoredImage(List<Object> request) {
  final id = request[0] as String;
  final jpeg = request[1] as Uint8List;
  if (hashes.sha256.convert(jpeg).toString() != id) {
    throw const InventoryPhotoException(
        'La fotografía está incompleta o dañada.');
  }
  try {
    final header = _inspect(jpeg, prepared: true);
    if (header.format != _PhotoFormat.jpeg) {
      throw const FormatException('Not JPEG');
    }
  } on Object {
    throw const InventoryPhotoException(
        'La fotografía guardada no tiene un formato válido.');
  }
}

/// Validate the actual inflate length before image's PNG decoder calls its
/// unbounded decodeBytes implementation. Input is fed in small chunks and the
/// sink discards output, so a tiny IDAT decompression bomb cannot exhaust RAM.
void _checkPngInflation(Uint8List png) {
  final data = ByteData.sublistView(png);
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  final bits = png[24];
  final channels = const {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[png[25]];
  if (channels == null ||
      !const [1, 2, 4, 8, 16].contains(bits) ||
      png[26] != 0 ||
      png[27] != 0 ||
      png[28] > 1) {
    throw const FormatException('Unsupported PNG layout');
  }
  int passBytes(int passWidth, int passHeight) =>
      passWidth <= 0 || passHeight <= 0
          ? 0
          : (((passWidth * channels * bits + 7) ~/ 8) + 1) * passHeight;
  var expected = 0;
  if (png[28] == 0) {
    expected = passBytes(width, height);
  } else {
    for (final pass in const [
      [0, 0, 8, 8],
      [4, 0, 8, 8],
      [0, 4, 4, 8],
      [2, 0, 4, 4],
      [0, 2, 2, 4],
      [1, 0, 2, 2],
      [0, 1, 1, 2],
    ]) {
      final passWidth =
          width <= pass[0] ? 0 : (width - pass[0] + pass[2] - 1) ~/ pass[2];
      final passHeight =
          height <= pass[1] ? 0 : (height - pass[1] + pass[3] - 1) ~/ pass[3];
      expected += passBytes(passWidth, passHeight);
    }
  }
  final sink = _PngCountSink(expected);
  final decoder = ZLibDecoder().startChunkedConversion(sink);
  var offset = 8;
  while (offset + 12 <= png.length) {
    final length = data.getUint32(offset);
    final type = String.fromCharCodes(png.sublist(offset + 4, offset + 8));
    if (type == 'IDAT') {
      final end = offset + 8 + length;
      for (var start = offset + 8; start < end; start += 4096) {
        decoder.add(Uint8List.sublistView(
            png, start, start + 4096 < end ? start + 4096 : end));
      }
    }
    offset += length + 12;
  }
  decoder.close();
}

class _PngCountSink implements Sink<List<int>> {
  _PngCountSink(this.expected);
  final int expected;
  int count = 0;
  @override
  void add(List<int> data) {
    count += data.length;
    if (count > expected) throw const FormatException('Excess PNG pixel data');
  }

  @override
  void close() {
    if (count != expected) {
      throw const FormatException('Incomplete PNG pixel data');
    }
  }
}

enum _PhotoFormat { jpeg, png, webp }

class _PhotoHeader {
  const _PhotoHeader(this.format, this.width, this.height);
  final _PhotoFormat format;
  final int width;
  final int height;
}

/// Parse fixed-size dimensions before invoking image decoders. In particular,
/// image.JpegDecoder.startDecode itself allocates DCT buffers, so it is not a
/// safe substitute for this small header inspection on untrusted input.
_PhotoHeader _inspect(Uint8List bytes, {required bool prepared}) {
  final maxBytes = prepared
      ? InventoryPhotoStore.maxPhotoBytes
      : InventoryPhotoStore.maxSourceBytes;
  if (bytes.length < 12 || bytes.length > maxBytes) {
    throw const FormatException('Invalid image size');
  }
  final data = ByteData.sublistView(bytes);
  _PhotoHeader? header;
  if (bytes[0] == 0xff && bytes[1] == 0xd8) {
    var offset = 2;
    while (offset + 3 < bytes.length) {
      if (bytes[offset++] != 0xff) {
        throw const FormatException('Invalid JPEG marker');
      }
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset++;
      }
      if (offset >= bytes.length) break;
      final marker = bytes[offset++];
      if (marker == 0xda || marker == 0xd9) break;
      if (marker == 0x00 ||
          marker == 0xd8 ||
          marker == 0x01 ||
          (marker >= 0xd0 && marker <= 0xd7)) {
        throw const FormatException('Unexpected JPEG marker');
      }
      if (offset + 2 > bytes.length) {
        throw const FormatException('Short JPEG marker');
      }
      final length = data.getUint16(offset);
      if (length < 2 || offset + length > bytes.length) {
        throw const FormatException('Invalid JPEG segment');
      }
      if (prepared && ((marker >= 0xe1 && marker <= 0xef) || marker == 0xfe)) {
        throw const FormatException('Unexpected photo metadata');
      }
      if (marker == 0xc0 || marker == 0xc1 || marker == 0xc2) {
        if (length < 8 || header != null) {
          throw const FormatException('Invalid JPEG frame');
        }
        final components = bytes[offset + 7];
        if (bytes[offset + 2] != 8 ||
            !const [1, 3, 4].contains(components) ||
            length != 8 + components * 3) {
          throw const FormatException('Unsupported JPEG components');
        }
        var blocksPerMcu = 0;
        for (var i = 0; i < components; i++) {
          final sampling = bytes[offset + 9 + i * 3];
          final horizontal = sampling >> 4;
          final vertical = sampling & 15;
          if (horizontal < 1 ||
              horizontal > 4 ||
              vertical < 1 ||
              vertical > 4) {
            throw const FormatException('Invalid JPEG sampling');
          }
          blocksPerMcu += horizontal * vertical;
        }
        if (blocksPerMcu > 10) {
          throw const FormatException('Excessive JPEG sampling');
        }
        header = _PhotoHeader(_PhotoFormat.jpeg, data.getUint16(offset + 5),
            data.getUint16(offset + 3));
        _checkDimensions(header, prepared);
      }
      offset += length;
    }
    if (bytes[bytes.length - 2] != 0xff || bytes.last != 0xd9) {
      throw const FormatException('Incomplete JPEG');
    }
  } else if (!prepared &&
      listEquals(
          bytes.sublist(0, 8), const [137, 80, 78, 71, 13, 10, 26, 10])) {
    if (bytes.length < 33 ||
        data.getUint32(8) != 13 ||
        String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') {
      throw const FormatException('Invalid PNG header');
    }
    header =
        _PhotoHeader(_PhotoFormat.png, data.getUint32(16), data.getUint32(20));
    _checkDimensions(header, prepared);
    var offset = 8;
    while (offset + 12 <= bytes.length) {
      final length = data.getUint32(offset);
      if (length > bytes.length - offset - 12) {
        throw const FormatException('Invalid PNG chunk');
      }
      final name = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      if (name == 'acTL') {
        throw const FormatException('Animated PNG');
      }
      offset += length + 12;
      if (name == 'IEND') break;
    }
  } else if (!prepared &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    if (data.getUint32(4, Endian.little) + 8 != bytes.length) {
      throw const FormatException('Invalid WebP size');
    }
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final name = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final length = data.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      if (length > bytes.length - start) {
        throw const FormatException('Invalid WebP chunk');
      }
      if (name == 'VP8X' && length >= 10) {
        if ((bytes[start] & 2) != 0) {
          throw const FormatException('Animated WebP');
        }
        header = _PhotoHeader(_PhotoFormat.webp, _uint24(bytes, start + 4) + 1,
            _uint24(bytes, start + 7) + 1);
      } else if (name == 'VP8 ' && length >= 10) {
        if (!listEquals(
            bytes.sublist(start + 3, start + 6), const [0x9d, 1, 0x2a])) {
          throw const FormatException('Invalid WebP frame');
        }
        final frameHeader = _PhotoHeader(
            _PhotoFormat.webp,
            data.getUint16(start + 6, Endian.little) & 0x3fff,
            data.getUint16(start + 8, Endian.little) & 0x3fff);
        _checkWebpFrame(header, frameHeader, prepared);
        header = frameHeader;
      } else if (name == 'VP8L' && length >= 5) {
        if (bytes[start] != 0x2f) {
          throw const FormatException('Invalid WebP lossless frame');
        }
        final bits = data.getUint32(start + 1, Endian.little);
        final frameHeader = _PhotoHeader(_PhotoFormat.webp, (bits & 0x3fff) + 1,
            ((bits >> 14) & 0x3fff) + 1);
        _checkWebpFrame(header, frameHeader, prepared);
        header = frameHeader;
      }
      if (header != null) _checkDimensions(header, prepared);
      offset = start + length + (length & 1);
    }
  }
  if (header == null) throw const FormatException('Unsupported photo format');
  _checkDimensions(header, prepared);
  return header;
}

/// Remove ancillary metadata before decoders can expand or traverse it. The
/// gallery file remains untouched; this operates on the in-memory copy only.
({Uint8List bytes, int orientation}) _sanitizeSource(
    Uint8List source, _PhotoFormat format) {
  final data = ByteData.sublistView(source);
  final output = BytesBuilder(copy: false);
  var orientation = 1;
  if (format == _PhotoFormat.jpeg) {
    output.add(source.sublist(0, 2));
    var offset = 2;
    while (offset + 3 < source.length) {
      final markerStart = offset;
      offset++;
      while (source[offset] == 0xff) {
        offset++;
      }
      final marker = source[offset++];
      if (marker == 0xda || marker == 0xd9) {
        output.add(source.sublist(markerStart));
        break;
      }
      final length = data.getUint16(offset);
      if (marker == 0xe1) {
        final candidate =
            _readOrientation(source.sublist(offset + 2, offset + length));
        // A later APP1 segment can contain XMP instead of EXIF. It must not
        // reset the orientation already found in the camera's EXIF segment.
        if (candidate != 1) orientation = candidate;
      }
      // APP14 records the Adobe color transform for CMYK JPEGs. It is needed
      // for decoding, and will not be carried into our fresh RGB JPEG.
      if (!((marker >= 0xe1 && marker <= 0xef && marker != 0xee) ||
          marker == 0xfe)) {
        output.add(source.sublist(markerStart, offset + length));
      }
      offset += length;
    }
    return (bytes: output.takeBytes(), orientation: orientation);
  }
  if (format == _PhotoFormat.png) {
    output.add(source.sublist(0, 8));
    var offset = 8;
    while (offset + 12 <= source.length) {
      final length = data.getUint32(offset);
      final name = String.fromCharCodes(source.sublist(offset + 4, offset + 8));
      if (name == 'eXIf' && length <= 65536) {
        orientation =
            _readOrientation(source.sublist(offset + 8, offset + 8 + length));
      }
      if (const ['IHDR', 'PLTE', 'tRNS', 'IDAT', 'IEND'].contains(name)) {
        output.add(source.sublist(offset, offset + length + 12));
      }
      offset += length + 12;
      if (name == 'IEND') break;
    }
    return (bytes: output.takeBytes(), orientation: orientation);
  }
  final chunks = BytesBuilder(copy: false);
  var offset = 12;
  while (offset + 8 <= source.length) {
    final name = String.fromCharCodes(source.sublist(offset, offset + 4));
    final length = data.getUint32(offset + 4, Endian.little);
    final end = offset + 8 + length + (length & 1);
    if (name == 'EXIF' && length <= 65536) {
      orientation =
          _readOrientation(source.sublist(offset + 8, offset + 8 + length));
    }
    if (!const ['EXIF', 'XMP ', 'ICCP'].contains(name)) {
      final chunk = source.sublist(offset, end);
      if (name == 'VP8X') chunk[8] &= ~0x2c;
      chunks.add(chunk);
    }
    offset = end;
  }
  final payload = chunks.takeBytes();
  final riffHeader = Uint8List.fromList(source.sublist(0, 12));
  ByteData.sublistView(riffHeader)
      .setUint32(4, payload.length + 4, Endian.little);
  output.add(riffHeader);
  output.add(payload);
  return (bytes: output.takeBytes(), orientation: orientation);
}

/// Read only the orientation scalar in TIFF IFD0, never recursive EXIF/GPS
/// directories, compressed thumbnails, or external offsets.
int _readOrientation(Uint8List metadata) {
  try {
    var bytes = metadata;
    if (bytes.length >= 6 &&
        listEquals(bytes.sublist(0, 6), const [69, 120, 105, 102, 0, 0])) {
      bytes = bytes.sublist(6);
    }
    if (bytes.length < 8) return 1;
    final endian =
        bytes[0] == 0x49 && bytes[1] == 0x49 ? Endian.little : Endian.big;
    if (!(bytes[0] == 0x49 && bytes[1] == 0x49) &&
        !(bytes[0] == 0x4d && bytes[1] == 0x4d)) {
      return 1;
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint16(2, endian) != 42) return 1;
    final start = data.getUint32(4, endian);
    if (start < 8 || start + 2 > bytes.length) return 1;
    final count = data.getUint16(start, endian);
    if (count > 256 || start + 2 + count * 12 > bytes.length) return 1;
    for (var i = 0; i < count; i++) {
      final offset = start + 2 + i * 12;
      if (data.getUint16(offset, endian) == 0x112 &&
          data.getUint16(offset + 2, endian) == 3 &&
          data.getUint32(offset + 4, endian) == 1) {
        final value = data.getUint16(offset + 8, endian);
        return value >= 1 && value <= 8 ? value : 1;
      }
    }
  } on Object {
    // Malformed metadata is discarded. It never prevents valid pixel recovery.
  }
  return 1;
}

int _uint24(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);

void _checkWebpFrame(_PhotoHeader? canvas, _PhotoHeader frame, bool prepared) {
  _checkDimensions(frame, prepared);
  if (canvas != null &&
      (canvas.width != frame.width || canvas.height != frame.height)) {
    throw const FormatException('Inconsistent WebP canvas');
  }
}

void _checkDimensions(_PhotoHeader header, bool prepared) {
  final dimension = prepared
      ? InventoryPhotoStore.maxPhotoDimension
      : InventoryPhotoStore.maxSourceDimension;
  final pixels =
      prepared ? dimension * dimension : InventoryPhotoStore.maxSourcePixels;
  if (header.width <= 0 ||
      header.height <= 0 ||
      header.width > dimension ||
      header.height > dimension ||
      header.width * header.height > pixels) {
    throw const InventoryPhotoSizeException();
  }
}
