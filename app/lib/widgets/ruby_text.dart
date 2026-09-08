import 'package:flutter/material.dart';

import '../models/textbook.dart';

class RubyText extends StatelessWidget {
  const RubyText({
    super.key,
    required this.text,
    required this.pinyin,
    this.highlights = const [],
    this.fontSize = 22,
    this.fontWeight = FontWeight.normal,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final String pinyin;
  final List<HighlightRange> highlights;
  final double fontSize;
  final FontWeight fontWeight;
  final TextAlign textAlign;

  static final RegExp _pinyinPattern = RegExp(
    r'[A-Za-z\u00c0-\u024f\u1e00-\u1eff]+',
    unicode: true,
  );

  @override
  Widget build(BuildContext context) {
    final runes = text.runes.toList();
    final syllables = _pinyinPattern
        .allMatches(pinyin)
        .map((match) => match.group(0)!)
        .toList();
    final pronounceableCount = runes.where(_isPronounceable).length;
    if (syllables.length != pronounceableCount) {
      return _fallback(context, runes);
    }

    final cells = <Widget>[];
    var syllableIndex = 0;
    for (var runeIndex = 0; runeIndex < runes.length; runeIndex++) {
      final rune = runes[runeIndex];
      final character = String.fromCharCode(rune);
      if (character.trim().isEmpty) {
        cells.add(SizedBox(width: fontSize * .55));
        continue;
      }
      final hasPronunciation = _isPronounceable(rune);
      final syllable = hasPronunciation ? syllables[syllableIndex++] : '';
      final highlighted = _isHighlighted(runeIndex);
      final color = highlighted
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.onSurface;
      cells.add(
        Padding(
          padding: EdgeInsets.symmetric(horizontal: fontSize * .045),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: fontSize * .78,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  widthFactor: 1,
                  child: Text(
                    syllable,
                    style: TextStyle(
                      color: color,
                      fontSize: fontSize * .48,
                      height: 1,
                      fontFamilyFallback: const [
                        'Noto Sans CJK SC',
                        'Microsoft YaHei',
                      ],
                    ),
                  ),
                ),
              ),
              Text(
                character,
                style: TextStyle(
                  color: color,
                  fontSize: fontSize,
                  height: 1.35,
                  fontWeight: fontWeight,
                  fontFamilyFallback: const [
                    'Kaiti SC',
                    'STKaiti',
                    'KaiTi',
                    'Noto Serif CJK SC',
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final alignment = switch (textAlign) {
      TextAlign.center => WrapAlignment.center,
      TextAlign.end || TextAlign.right => WrapAlignment.end,
      _ => WrapAlignment.start,
    };
    return SelectionArea(
      child: Wrap(
        alignment: alignment,
        crossAxisAlignment: WrapCrossAlignment.end,
        runSpacing: fontSize * .45,
        children: cells,
      ),
    );
  }

  Widget _fallback(BuildContext context, List<int> runes) {
    final normal = Theme.of(context).colorScheme.onSurface;
    final red = Theme.of(context).colorScheme.error;
    final hasHighlight = highlights.isNotEmpty;
    return SelectionArea(
      child: Column(
        crossAxisAlignment: switch (textAlign) {
          TextAlign.center => CrossAxisAlignment.center,
          TextAlign.end || TextAlign.right => CrossAxisAlignment.end,
          _ => CrossAxisAlignment.start,
        },
        children: [
          Text(
            pinyin,
            textAlign: textAlign,
            style: TextStyle(
              color: hasHighlight ? red : normal,
              fontSize: fontSize * .5,
              height: 1.4,
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                for (var index = 0; index < runes.length; index++)
                  TextSpan(
                    text: String.fromCharCode(runes[index]),
                    style: TextStyle(
                      color: _isHighlighted(index) ? red : normal,
                    ),
                  ),
              ],
            ),
            textAlign: textAlign,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.6,
              fontWeight: fontWeight,
              fontFamilyFallback: const [
                'Kaiti SC',
                'STKaiti',
                'KaiTi',
                'Noto Serif CJK SC',
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isHighlighted(int index) =>
      highlights.any((range) => range.contains(index));

  static bool _isPronounceable(int rune) {
    final isHan =
        (rune >= 0x3400 && rune <= 0x4dbf) ||
        (rune >= 0x4e00 && rune <= 0x9fff) ||
        (rune >= 0xf900 && rune <= 0xfaff);
    final isRadical = rune >= 0x2e80 && rune <= 0x2fff;
    final isLatinLetter =
        (rune >= 0x41 && rune <= 0x5a) || (rune >= 0x61 && rune <= 0x7a);
    return isHan || isRadical || isLatinLetter;
  }
}
