import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/speech_engine.dart';

class OriginalSpeech extends StatefulWidget {
  const OriginalSpeech({super.key, required this.record});

  final Map<String, dynamic> record;

  @override
  State<OriginalSpeech> createState() => _OriginalSpeechState();
}

class _OriginalSpeechState extends State<OriginalSpeech> {
  bool _busy = false;

  Future<void> _play() async {
    final encoded = widget.record['speechSnac'];
    if (encoded is! String || encoded.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final wav = await SpeechEngine.instance.decodeSnac(base64Decode(encoded));
      await SpeechEngine.instance.playWav(wav);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('录音播放失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final answer = widget.record['expectedAnswer'] as String? ?? '';
    final chars = answer.runes
        .map(String.fromCharCode)
        .where((ch) => RegExp(r'[\u3400-\u9fff]').hasMatch(ch))
        .toList();
    final encoded = widget.record['speechReviewBits'];
    final bits = encoded is String ? base64Decode(encoded) : <int>[];
    final recognized = widget.record['studentAnswer'] as String? ?? '';
    final pinyin = widget.record['speechRecognizedPinyin'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('原始朗读与批改'),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _play,
            icon: Icon(_busy ? Icons.hourglass_top : Icons.play_arrow),
            label: const Text('播放原始录音'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var index = 0; index < chars.length; index++)
                Chip(
                  label: Text(chars[index]),
                  avatar: Icon(
                    index ~/ 8 < bits.length &&
                            bits[index ~/ 8] & (1 << (index % 8)) != 0
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 17,
                    color: index ~/ 8 < bits.length &&
                            bits[index ~/ 8] & (1 << (index % 8)) != 0
                        ? Colors.green.shade700
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ),
          SelectableText('ASR 识别：${recognized.isEmpty ? '—' : recognized}'),
          if (pinyin.isNotEmpty) SelectableText('识别拼音：$pinyin'),
        ],
      ),
    );
  }
}
