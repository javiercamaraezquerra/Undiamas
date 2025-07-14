import 'package:flutter_test/flutter_test.dart';

/// Prueba de humo que siempre pasa.
///
/// Mantiene el paso `flutter test` en el CI sin interferir hasta
/// que añadas tests reales.
void main() {
  test('smoke test – 2 + 2 = 4', () {
    expect(2 + 2, equals(4));
  });
}
