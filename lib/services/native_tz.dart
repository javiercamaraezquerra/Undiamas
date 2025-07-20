import 'package:flutter/services.dart';

/// Devuelve el ID IANA de la zona horaria local usando el plugin nativo.
class NativeTz {
  static const _ch = MethodChannel('undiamas/tz');

  static Future<String> getLocalTz() async =>
      await _ch.invokeMethod<String>('getLocalTz') ?? 'UTC';
}
