/// Converts textbook pinyin with diacritics to the whitespace-separated
/// numeric notation accepted by Piper's Chinese phonemizer.
///
/// Examples: `sì dāo` -> `si4 dao1`, `nǚ ér` -> `nv3 er2`.
String toNumericPinyin(String value) {
  const marked = <String, (String, int)>{
    'ā': ('a', 1),
    'á': ('a', 2),
    'ǎ': ('a', 3),
    'à': ('a', 4),
    'ē': ('e', 1),
    'é': ('e', 2),
    'ě': ('e', 3),
    'è': ('e', 4),
    'ī': ('i', 1),
    'í': ('i', 2),
    'ǐ': ('i', 3),
    'ì': ('i', 4),
    'ō': ('o', 1),
    'ó': ('o', 2),
    'ǒ': ('o', 3),
    'ò': ('o', 4),
    'ū': ('u', 1),
    'ú': ('u', 2),
    'ǔ': ('u', 3),
    'ù': ('u', 4),
    'ǖ': ('v', 1),
    'ǘ': ('v', 2),
    'ǚ': ('v', 3),
    'ǜ': ('v', 4),
    'ü': ('v', 5),
    'Ā': ('a', 1),
    'Á': ('a', 2),
    'Ǎ': ('a', 3),
    'À': ('a', 4),
    'Ē': ('e', 1),
    'É': ('e', 2),
    'Ě': ('e', 3),
    'È': ('e', 4),
    'Ī': ('i', 1),
    'Í': ('i', 2),
    'Ǐ': ('i', 3),
    'Ì': ('i', 4),
    'Ō': ('o', 1),
    'Ó': ('o', 2),
    'Ǒ': ('o', 3),
    'Ò': ('o', 4),
    'Ū': ('u', 1),
    'Ú': ('u', 2),
    'Ǔ': ('u', 3),
    'Ù': ('u', 4),
    'Ǖ': ('v', 1),
    'Ǘ': ('v', 2),
    'Ǚ': ('v', 3),
    'Ǜ': ('v', 4),
    'Ü': ('v', 5),
  };

  final normalized = value
      .replaceAll('u:', 'v')
      .replaceAll('U:', 'v')
      .replaceAll('ü', 'v')
      .replaceAll('Ü', 'v')
      .toLowerCase();
  final result = <String>[];
  // Tone marks are split between Latin-1 (á/è/ì/ó/ú) and Latin Extended-A
  // (ā/ě/ǜ...). Keep both Unicode blocks inside a syllable.
  final syllables = normalized.split(
    RegExp(r"[^a-zv\u00c0-\u00ff\u0100-\u01dc0-5]+"),
  );
  for (final raw in syllables) {
    if (raw.isEmpty) continue;
    final buffer = StringBuffer();
    var tone = 0;
    for (final rune in raw.runes) {
      final char = String.fromCharCode(rune);
      final replacement = marked[char];
      if (replacement != null) {
        buffer.write(replacement.$1);
        if (replacement.$2 != 5) tone = replacement.$2;
      } else if (RegExp(r'[1-5]').hasMatch(char)) {
        tone = int.parse(char);
      } else if (RegExp(r'[a-zv]').hasMatch(char)) {
        buffer.write(char);
      }
    }
    final syllable = buffer.toString();
    if (syllable.isNotEmpty) result.add('$syllable${tone == 0 ? 5 : tone}');
  }
  return result.join(' ');
}
