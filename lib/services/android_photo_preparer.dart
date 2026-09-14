import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Android samples the original file before pixels cross the Flutter channel.
/// Only the small, metadata-free JPEG enters the Dart image validator.
class AndroidPhotoPreparer {
  const AndroidPhotoPreparer({
    MethodChannel channel = const MethodChannel('undiamas/photos'),
  }) : _channel = channel;

  static const maxSourceBytes = 128 * 1024 * 1024;
  static const maxPreparedBytes = 2 * 1024 * 1024;
  final MethodChannel _channel;

  Future<Uint8List> prepare(XFile file) async {
    if (await file.length() > maxSourceBytes) {
      throw PlatformException(code: 'photo_too_large');
    }
    final jpeg = await _channel.invokeMethod<Uint8List>(
        'prepare', <String, Object>{'path': file.path});
    if (jpeg == null || jpeg.isEmpty || jpeg.length > maxPreparedBytes) {
      throw PlatformException(code: 'photo_prepare_failed');
    }
    return jpeg;
  }
}
