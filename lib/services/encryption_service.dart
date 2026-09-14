import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

/// Maneja la clave única (32 bytes) almacenada en el Keystore / Keychain
/// y ofrece el `HiveAesCipher` que usan las cajas cifradas.
class EncryptionService {
  static const _k = 'hive_key';
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  /// Cipher para Hive
  static Future<HiveAesCipher> getCipher() async =>
      HiveAesCipher(await getRawKey());

  /// Devuelve la clave bruta (Uint8List) para otros cifrados (Drive, etc.).
  static Future<Uint8List> getRawKey({
    Future<Directory> Function()? supportDirectory,
  }) async {
    var key = await _secure.read(key: _k);
    if (key == null) {
      // A missing secure-storage key is not a fresh installation when encrypted
      // boxes remain. Replacing it could make Hive truncate unreadable data.
      for (final boxName in const [
        'udm_secure',
        'diary_secure',
        'restore_recovery_secure',
      ]) {
        if (await Hive.boxExists(boxName)) {
          throw StateError(
              'No se encuentra la clave de los datos cifrados existentes. '
              'No se ha creado otra clave ni se han modificado esos archivos.');
        }
      }
      // Photo and draft files also outlive a missing Hive box. Never create a
      // replacement key while any encrypted private payload remains on disk.
      final support =
          await (supportDirectory ?? getApplicationSupportDirectory)();
      for (final name in const ['inventory_photos', 'journal_draft']) {
        final directory =
            Directory('${support.path}${Platform.pathSeparator}$name');
        if (await directory.exists() && !await directory.list().isEmpty) {
          throw StateError('No se encuentra la clave de tus archivos privados. '
              'Se han conservado sin crear otra clave.');
        }
      }
      key = base64UrlEncode(Hive.generateSecureKey());
      await _secure.write(key: _k, value: key);
    }
    final Uint8List decoded;
    try {
      decoded = Uint8List.fromList(base64Url.decode(key));
    } catch (_) {
      throw StateError('La clave de los datos cifrados no se puede leer.');
    }
    if (decoded.length != 32) {
      throw StateError(
          'La clave de los datos cifrados no tiene un formato válido.');
    }
    return decoded;
  }

  /* ── NUEVO · Elimina la clave para “Reset total” ── */
  static Future<void> wipeKey() async {
    await _secure.delete(key: _k);
  }
}
