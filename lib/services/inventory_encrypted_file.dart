import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Small, versioned AEAD envelope shared by photos and the composer draft.
/// Purpose and record name are authenticated, so records cannot be exchanged.
class InventoryEncryptedFile {
  InventoryEncryptedFile({
    required this.directoryProvider,
    required this.keyProvider,
    required this.purpose,
    this.beforeStep,
  });

  final Future<Directory> Function() directoryProvider;
  final Future<Uint8List> Function() keyProvider;
  final String purpose;
  final Future<void> Function(String)? beforeStep;

  static const overheadBytes = 8 + 12 + 16;
  static final _safeName = RegExp(r'^[a-zA-Z0-9_.-]+$');

  Future<Directory> directory({bool create = false}) async {
    final result = await directoryProvider();
    final type = await FileSystemEntity.type(result.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw const FileSystemException('La carpeta privada no es válida.');
    }
    if (create && type == FileSystemEntityType.notFound) {
      await result.create(recursive: true);
    }
    return result;
  }

  Future<File> file(String name, {bool createDirectory = false}) async {
    if (!_safeName.hasMatch(name) || name == '.' || name == '..') {
      throw const FormatException('Nombre de archivo privado no válido.');
    }
    final folder = await directory(create: createDirectory);
    final result = File('${folder.path}${Platform.pathSeparator}$name');
    final type = await FileSystemEntity.type(result.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const FileSystemException('El archivo privado no es válido.');
    }
    return result;
  }

  Future<Uint8List?> read(String name, {required int maxBytes}) async {
    final target = await file(name);
    if (!await target.exists()) return null;
    final size = await target.length();
    if (size < overheadBytes || size > maxBytes + overheadBytes) {
      throw const FormatException(
          'El archivo cifrado tiene un tamaño inválido.');
    }
    final encoded = await target.readAsBytes();
    if (encoded.length != size) {
      throw const FormatException('El archivo cifrado está incompleto.');
    }
    final key = await keyProvider();
    return compute(_decryptRecord, <Object>[encoded, key, purpose, name]);
  }

  Future<void> write(String name, Uint8List plaintext) async {
    // Fetch the key before creating a directory. An empty directory must not
    // make a fresh install look like an installation with orphaned ciphertext.
    final key = await keyProvider();
    final encoded =
        await compute(_encryptRecord, <Object>[plaintext, key, purpose, name]);
    final target = await file(name, createDirectory: true);
    final random = Random.secure();
    final suffix = List<int>.generate(12, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final temporary = File('${target.path}.$suffix.tmp');
    try {
      await beforeStep?.call('beforeWrite');
      await temporary.writeAsBytes(encoded, flush: true);
      await beforeStep?.call('beforeCommit');
      // Same-directory rename: the previous committed record remains intact
      // if encoding, writing, flushing or the pre-commit step fails.
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> delete(String name) async {
    final target = await file(name);
    if (await target.exists()) await target.delete();
  }
}

const _magic = <int>[85, 68, 77, 65, 69, 48, 48, 49]; // UDMAE001

Future<SecretKey> _deriveKey(Uint8List key, String purpose) {
  if (key.length != 32) {
    throw const FormatException('La clave privada no tiene un formato válido.');
  }
  return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: SecretKey(key),
    nonce: utf8.encode('un-dia-mas/private-storage/v1'),
    info: utf8.encode(purpose),
  );
}

Future<Uint8List> _encryptRecord(List<Object> request) async {
  final plaintext = request[0] as Uint8List;
  final key = request[1] as Uint8List;
  final purpose = request[2] as String;
  final name = request[3] as String;
  final algorithm = AesGcm.with256bits();
  final box = await algorithm.encrypt(
    plaintext,
    secretKey: await _deriveKey(key, purpose),
    aad: utf8.encode('UDMAE001/$purpose/$name'),
  );
  return Uint8List.fromList([..._magic, ...box.concatenation()]);
}

Future<Uint8List> _decryptRecord(List<Object> request) async {
  final encoded = request[0] as Uint8List;
  final key = request[1] as Uint8List;
  final purpose = request[2] as String;
  final name = request[3] as String;
  if (encoded.length < InventoryEncryptedFile.overheadBytes ||
      !listEquals(encoded.sublist(0, _magic.length), _magic)) {
    throw const FormatException('El archivo cifrado no es compatible.');
  }
  final box = SecretBox.fromConcatenation(
    encoded.sublist(_magic.length),
    nonceLength: 12,
    macLength: 16,
  );
  final plaintext = await AesGcm.with256bits().decrypt(
    box,
    secretKey: await _deriveKey(key, purpose),
    aad: utf8.encode('UDMAE001/$purpose/$name'),
  );
  return Uint8List.fromList(plaintext);
}
