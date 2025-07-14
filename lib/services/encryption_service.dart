import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

class EncryptionService {
  static const _k = 'hive_key';
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  static Future<HiveAesCipher> getCipher() async {
    var key = await _secure.read(key: _k);
    if (key == null) {
      key = base64UrlEncode(Hive.generateSecureKey());
      await _secure.write(key: _k, value: key);
    }
    return HiveAesCipher(base64Url.decode(key));
  }
}
