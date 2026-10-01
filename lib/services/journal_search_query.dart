/// A transient, local-only query. No journal text or search term is persisted
/// or sent to a service; the original text and Hive keys stay unchanged.
class JournalSearchQuery {
  JournalSearchQuery(String text)
      : _terms = _fold(text)
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .toList();

  final List<String> _terms;

  bool get isEmpty => _terms.isEmpty;

  /// Each word can appear anywhere in the entry, in any order.
  bool matches(String text) {
    if (isEmpty) return true;
    final normalized = _fold(text);
    return _terms.every(normalized.contains);
  }

  static String _fold(String value) {
    const accents = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ñ': 'n',
      'ç': 'c',
    };
    return value
        .toLowerCase()
        .replaceAllMapped(
            RegExp('[${accents.keys.join()}]'), (match) => accents[match[0]]!)
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '');
  }
}
