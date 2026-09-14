import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:un_dia_mas/services/android_photo_preparer.dart';

class _OriginalFile extends Fake implements XFile {
  _OriginalFile({this.size = 120000000});
  final int size;
  bool readAttempted = false;
  @override
  String get path => '/data/user/0/example/cache/camera.jpg';
  @override
  Future<int> length() async => size;
  @override
  Future<Uint8List> readAsBytes() async {
    readAttempted = true;
    throw StateError('The original must never be loaded into Dart.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('undiamas/photos');
  const preparer = AndroidPhotoPreparer();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
      'sends only a path, receives prepared bytes without reading a large original',
      () async {
    final source = _OriginalFile();
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'prepare');
      expect(call.arguments, {'path': source.path});
      return Uint8List.fromList([255, 216, 255, 217]);
    });
    expect(await preparer.prepare(source), [255, 216, 255, 217]);
    expect(source.readAttempted, isFalse);
  });

  test('rejects an oversized source before invoking Android', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      called = true;
      return null;
    });
    final source = _OriginalFile(size: AndroidPhotoPreparer.maxSourceBytes + 1);
    await expectLater(
        preparer.prepare(source),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'photo_too_large')));
    expect(called, isFalse);
    expect(source.readAttempted, isFalse);
  });

  for (final (label, payload) in <(String, Uint8List?)>[
    ('null', null),
    ('empty', Uint8List(0)),
    ('too large', Uint8List(AndroidPhotoPreparer.maxPreparedBytes + 1)),
  ]) {
    test('rejects $label native result', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => payload);
      await expectLater(
          preparer.prepare(_OriginalFile()),
          throwsA(isA<PlatformException>()
              .having((e) => e.code, 'code', 'photo_prepare_failed')));
    });
  }

  test('native errors remain typed and never trigger an unsafe Dart fallback',
      () async {
    final source = _OriginalFile();
    messenger.setMockMethodCallHandler(channel,
        (_) async => throw PlatformException(code: 'photo_unsupported'));
    await expectLater(
        preparer.prepare(source),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'photo_unsupported')));
    expect(source.readAttempted, isFalse);
  });
}
