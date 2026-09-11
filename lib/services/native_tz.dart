import 'package:flutter/services.dart';

/// Devuelve el ID IANA de la zona horaria local usando el plugin nativo.
class NativeTz {
  static const _ch = MethodChannel('undiamas/tz');

  static Future<String> getLocalTz() async {
    final name = await _ch.invokeMethod<String>('getLocalTz');
    if (name == null || name.trim().isEmpty) {
      throw StateError(
          'No se pudo identificar la zona horaria del dispositivo.');
    }
    return name.trim();
  }
}
