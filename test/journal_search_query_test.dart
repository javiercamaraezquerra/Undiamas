import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/services/journal_search_query.dart';

void main() {
  test('matches Spanish accents and case without changing original content',
      () {
    const text = 'CAFÉ, ilusión y un año de pequeños pasos. Qué día tan bueno.';
    expect(JournalSearchQuery('cafe DIA').matches(text), isTrue);
    expect(JournalSearchQuery('ILUSIÓN pequeños').matches(text), isTrue);
    expect(JournalSearchQuery('ano').matches(text), isTrue);
    expect(JournalSearchQuery('cafe tristeza').matches(text), isFalse);
    expect(text, contains('CAFÉ'));
  });

  test('handles combining accents, diaeresis and all whitespace', () {
    expect(
        JournalSearchQuery('  te\nverguenza ').matches('Te quité la vergüenza'),
        isTrue);
    expect(JournalSearchQuery('cafe').matches('Cafe\u0301'), isTrue);
    expect(JournalSearchQuery('Cafe\u0301').matches('CAFÉ'), isTrue);
    expect(JournalSearchQuery(' \n\t').isEmpty, isTrue);
    expect(JournalSearchQuery(' \n\t').matches(''), isTrue);
  });

  test('search is literal, all terms are required, photos alone do not match',
      () {
    expect(JournalSearchQuery('.*').matches('Salí a caminar'), isFalse);
    expect(JournalSearchQuery('.*').matches('Escribí .* literalmente'), isTrue);
    expect(
        JournalSearchQuery('caminar sali').matches('Salí al parque a caminar'),
        isTrue);
    expect(JournalSearchQuery('foto').matches(''), isFalse);
    expect(JournalSearchQuery('').matches(''), isTrue);
  });
}
