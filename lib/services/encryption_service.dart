import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

/// Maneja la clave única (32 bytes) almacenada en el Keystore / Keychain
/// y ofrece el `HiveAesCipher` que usan las cajas cifradas.
class EncryptionService {
  static const _k = 'hive_key';
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  /// Cipher para Hive
  static Future<HiveAesCipher> getCipher() async =>
      HiveAesCipher(await getRawKey());

  /// Devuelve la clave bruta (Uint8List) para otros cifrados (Drive, etc.).
  static Future<Uint8List> getRawKey() async {
    var key = await _secure.read(key: _k);
    if (key == null) {
      key = base64UrlEncode(Hive.generateSecureKey());
      await _secure.write(key: _k, value: key);
    }
    return Uint8List.fromList(base64Url.decode(key));
  }
}
