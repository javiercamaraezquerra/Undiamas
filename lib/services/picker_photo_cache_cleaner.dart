import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';

import 'encryption_service.dart';
import 'inventory_encrypted_file.dart';

/// Owns only the exact cache paths returned by image_picker_android 0.8.13+1.
/// The picker must run without native resizing (imageQuality: 100, no maxima),
/// so it does not leave a second, unreported original under another UUID.
/// No discovery or deletion by UUID pattern is performed.
class PickerPhotoCacheCleaner {
  PickerPhotoCacheCleaner({
    Directory? temporaryDirectory,
    Future<Directory> Function()? temporaryDirectoryProvider,
    Directory? stateDirectory,
    Future<Directory> Function()? stateDirectoryProvider,
    Uint8List? key,
    Future<Uint8List> Function()? keyProvider,
    Future<void> Function(String)? beforeStep,
  })  : _temporaryDirectory = temporaryDirectoryProvider ??
            (temporaryDirectory != null
                ? () async => temporaryDirectory
                : getTemporaryDirectory),
        _files = InventoryEncryptedFile(
          directoryProvider: stateDirectoryProvider ??
              (stateDirectory != null
                  ? () async => stateDirectory
                  : _defaultStateDirectory),
          keyProvider: keyProvider ??
              (key != null ? () async => key : EncryptionService.getRawKey),
          purpose: 'picker-cache-registry',
          beforeStep: beforeStep,
        );

  static final instance = PickerPhotoCacheCleaner();
  static const _registryName = 'picker-cache.udm';
  static const _registryMaxBytes = 256 * 1024;
  static const _maxPaths = 1000;
  static const _uuid =
      r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}';
  static final _uuidDirectory = RegExp('^$_uuid\$');
  static final _cameraFile = RegExp('^$_uuid-?[0-9]{1,20}\\.jpg\$');

  final Future<Directory> Function() _temporaryDirectory;
  final InventoryEncryptedFile _files;
  Future<void> _pending = Future<void>.value();

  static Future<Directory> _defaultStateDirectory() async => Directory(paths
      .join((await getApplicationSupportDirectory()).path, 'journal_draft'));

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Call immediately after pick/retrieveLostData, before reading the XFile.
  /// Returns false for external originals or unexpected layouts; those paths
  /// are never registered and must never be deleted by this helper.
  Future<bool> registerPickedPath(String pickedPath) => _exclusive(() async {
        final root = await _root();
        if (root == null) {
          return false;
        }
        final relative = _relative(root, pickedPath);
        if (relative == null ||
            !await _isRegularOwnedPath(root.canonical, relative)) {
          return false;
        }
        final registered = await _readRegistry();
        if (registered.contains(relative)) {
          return true;
        }
        if (registered.length >= _maxPaths) {
          throw const FileSystemException(
              'No se han podido limpiar los temporales anteriores.');
        }
        registered.add(relative);
        await _writeRegistry(registered);
        return true;
      });

  /// Called after successful import, rejection, or cancellation after a result.
  /// Only a previously registered returned path can be removed.
  Future<void> cleanupPickedPath(String pickedPath) => _exclusive(() async {
        final root = await _root();
        if (root == null) {
          return;
        }
        final relative = _relative(root, pickedPath);
        if (relative == null) {
          return;
        }
        final registered = await _readRegistry();
        if (!registered.contains(relative)) {
          return;
        }
        await _deleteOwned(root.canonical, relative);
        registered.remove(relative);
        await _writeRegistry(registered);
      });

  /// Call after lost-result recovery has completed, not before it. Kept paths
  /// allow the caller to protect any XFile still being imported.
  Future<void> cleanupStale({Set<String> retainedPaths = const {}}) {
    final retainedSnapshot = Set<String>.unmodifiable(retainedPaths);
    return _exclusive(() async {
      final registered = await _readRegistry();
      if (registered.isEmpty) {
        return;
      }
      final root = await _root();
      if (root == null) {
        // Android may evict the cache. Forget already-absent paths while the
        // encryption key still exists, so reset cannot leave an orphan registry.
        await _writeRegistry(<String>{});
        return;
      }
      final retained = <String>{};
      for (final path in retainedSnapshot) {
        final relative = _relative(root, path);
        if (relative != null) {
          retained.add(relative);
        }
      }
      for (final relative in registered.toList()) {
        if (retained.contains(relative)) {
          continue;
        }
        await _deleteOwned(root.canonical, relative);
        registered.remove(relative);
        // Commit each removal so an I/O failure on a later file can be retried.
        await _writeRegistry(registered);
      }
    });
  }

  /// Invoke before wiping the encryption key during a full local reset.
  Future<void> clear() => cleanupStale();

  Future<_CacheRoot?> _root() async {
    final root = await _temporaryDirectory();
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return null;
    }
    return _CacheRoot(Directory(paths.normalize(root.absolute.path)),
        Directory(paths.normalize(await root.resolveSymbolicLinks())));
  }

  String? _relative(_CacheRoot root, String pickedPath) {
    if (!paths.isAbsolute(pickedPath) ||
        paths.split(pickedPath).contains('..')) {
      return null;
    }
    final normalized = paths.normalize(pickedPath);
    final base = paths.isWithin(root.requested.path, normalized)
        ? root.requested.path
        : paths.isWithin(root.canonical.path, normalized)
            ? root.canonical.path
            : null;
    if (base == null) {
      return null;
    }
    final relative = paths.relative(normalized, from: base);
    return _recognizedLayout(relative) ? relative : null;
  }

  static bool _recognizedLayout(String relative) {
    if (paths.isAbsolute(relative)) {
      return false;
    }
    final parts = paths.split(relative);
    if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      return false;
    }
    if (parts.length == 1) {
      return _cameraFile.hasMatch(parts.single);
    }
    return parts.length == 2 &&
        _uuidDirectory.hasMatch(parts.first) &&
        parts.last.length <= 255;
  }

  Future<bool> _isRegularOwnedPath(Directory root, String relative,
      {bool allowMissing = false}) async {
    if (!_recognizedLayout(relative)) {
      return false;
    }
    final parts = paths.split(relative);
    var current = root.path;
    for (var index = 0; index < parts.length; index++) {
      current = paths.join(current, parts[index]);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        return allowMissing;
      }
      final expected = index == parts.length - 1
          ? FileSystemEntityType.file
          : FileSystemEntityType.directory;
      if (type != expected) {
        return false;
      }
      final canonical = await (index == parts.length - 1
          ? File(current).resolveSymbolicLinks()
          : Directory(current).resolveSymbolicLinks());
      if (!paths.equals(paths.normalize(canonical), current) ||
          !paths.isWithin(root.path, canonical)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _deleteOwned(Directory root, String relative) async {
    if (!await _isRegularOwnedPath(root, relative, allowMissing: true)) {
      return;
    }
    final file = File(paths.join(root.path, relative));
    if (await file.exists()) {
      await file.delete();
    }
    final parts = paths.split(relative);
    if (parts.length != 2) {
      return;
    }
    final folder = Directory(paths.join(root.path, parts.first));
    if (await FileSystemEntity.type(folder.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    if (await folder.list(followLinks: false).isEmpty) {
      try {
        // Non-recursive: an unexpected extra cache file must never be removed.
        await folder.delete();
      } on FileSystemException {
        if (!await folder.exists() ||
            await folder.list(followLinks: false).isEmpty) {
          rethrow;
        }
      }
    }
  }

  Future<Set<String>> _readRegistry() async {
    final bytes = await _files.read(_registryName, maxBytes: _registryMaxBytes);
    if (bytes == null) {
      return <String>{};
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map ||
        value.length != 2 ||
        value['version'] != 1 ||
        value['paths'] is! List ||
        (value['paths'] as List).length > _maxPaths) {
      throw const FormatException(
          'El registro de temporales no se puede leer.');
    }
    final result = <String>{};
    for (final relative in value['paths'] as List) {
      if (relative is! String || !_recognizedLayout(relative)) {
        throw const FormatException('El registro de temporales no es válido.');
      }
      result.add(relative);
    }
    return result;
  }

  Future<void> _writeRegistry(Set<String> registered) async {
    if (registered.isEmpty) {
      await _files.delete(_registryName);
      return;
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
      'version': 1,
      'paths': registered.toList()..sort(),
    })));
    if (bytes.length > _registryMaxBytes) {
      throw const FormatException(
          'El registro de temporales es demasiado grande.');
    }
    await _files.write(_registryName, bytes);
  }
}

class _CacheRoot {
  const _CacheRoot(this.requested, this.canonical);
  final Directory requested;
  final Directory canonical;
}
