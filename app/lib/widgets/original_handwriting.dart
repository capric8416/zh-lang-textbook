import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/handwriting.dart';

/// Decodes compressed ink only after a history row is expanded.
class OriginalHandwriting extends StatefulWidget {
  const OriginalHandwriting({super.key, required this.record});

  final Map<String, Object?> record;

  @override
  State<OriginalHandwriting> createState() => _OriginalHandwritingState();
}

class _OriginalHandwritingState extends State<OriginalHandwriting> {
  InkDocument? _document;
  List<String> _ocrResults = const [];
  List<String> _expectedResults = const [];
  List<bool> _reviewResults = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant OriginalHandwriting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record['handwritingGzip'] !=
        widget.record['handwritingGzip']) {
      _document = null;
      _ocrResults = const [];
      _expectedResults = const [];
      _reviewResults = const [];
      _error = null;
      _decode();
    }
  }

  void _decode() {
    if (_document != null || _error != null) return;
    try {
      final document = InkDocument.decodeBytes(
        base64Decode(widget.record['handwritingGzip'] as String),
      );
      final ocrValue = widget.record['ocrResults'];
      final reviewValue = widget.record['reviewBits'];
      if (ocrValue is! List || reviewValue is! String) {
        throw const FormatException('逐格批改数据缺失');
      }
      final ocr = ocrValue.map((item) => item.toString()).toList();
      final expected = _expectedSlots(
        widget.record['expectedAnswer']?.toString() ?? '',
        widget.record['direction']?.toString() ?? '',
      );
      final reviewBytes = base64Decode(reviewValue);
      if (ocr.length != document.cells.length ||
          expected.length != document.cells.length ||
          reviewBytes.length != (document.cells.length + 7) ~/ 8) {
        throw const FormatException('逐格批改数据数量不匹配');
      }
      _document = document;
      _ocrResults = ocr;
      _expectedResults = expected;
      _reviewResults = [
        for (var index = 0; index < document.cells.length; index++)
          reviewBytes[index ~/ 8] & (1 << (index % 8)) != 0,
      ];
    } catch (_) {
      _error = '作答与批改数据无法读取';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.record['direction'] == 'readAloud') {
      return const SizedBox.shrink();
    }
    if (widget.record['handwritingGzip'] is! String) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('作答轨迹数据缺失'),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('作答与批改'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!),
            ),
          if (_document != null && _document!.cells.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final spacing = _document!.cells.first.grid == 'hanzi'
                      ? 6.0
                      : 10.0;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (
                        var index = 0;
                        index < _document!.cells.length;
                        index++
                      )
                        _cell(
                          _document!.cells[index],
                          index,
                          constraints.maxWidth,
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(InkCell cell, int index, double maxWidth) {
    final width = cell.size.width.clamp(1.0, maxWidth);
    final reviewed = _reviewResults[index];
    final resultColor = reviewed
        ? Colors.green.shade800
        : Theme.of(context).colorScheme.error;
    return SizedBox(
      width: width,
      child: Column(
        children: [
          ClipRect(
            child: ColoredBox(
              color: Colors.white,
              child: CustomPaint(
                size: Size(width, cell.size.height * width / cell.size.width),
                painter: InkPainter(cell),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('第 ${index + 1} 格'),
          Text('识别：${_ocrResults[index].isEmpty ? '—' : _ocrResults[index]}'),
          Text('正确：${_expectedResults[index]}'),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  reviewed ? Icons.check_circle_outline : Icons.cancel_outlined,
                  size: 16,
                  color: resultColor,
                ),
                const SizedBox(width: 4),
                Text(
                  reviewed ? '复核：正确' : '复核：错误',
                  style: TextStyle(color: resultColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<String> _expectedSlots(String text, String direction) {
  final pattern = direction == 'writePinyin'
      ? RegExp(r'[A-Za-z\u00C0-\u024F]+')
      : RegExp(r'[\u4E00-\u9FFF]');
  return [for (final match in pattern.allMatches(text)) match.group(0)!];
}
