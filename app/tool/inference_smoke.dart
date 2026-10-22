import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:zh_textbook/models/ocr.dart';
import 'package:zh_textbook/services/native_inference.dart';

/// Run from app/ with the Linux bundle's lib directory on LD_LIBRARY_PATH.
/// Exercises actual models without microphone, playback, account or user data.
Future<void> main() async {
  final temporary = await Directory.current.createTemp('.inference-smoke-');
  final inference = NativeInference.instance;
  final assets = '${Directory.current.path}/assets';
  var ticks = 0;
  final timer = Timer.periodic(
    const Duration(milliseconds: 20),
    (_) => ticks++,
  );
  Future<void> measure(String name, Future<void> Function() operation) async {
    final before = ticks;
    final watch = Stopwatch()..start();
    await operation();
    stdout.writeln(
      '$name: ${watch.elapsedMilliseconds} ms; main-isolate ticks: ${ticks - before}',
    );
  }

  try {
    final ocr = '$assets/ocr';
    final config = File('${temporary.path}/ocr.json');
    await config.writeAsString(
      jsonEncode({
        'save': false,
        'det': {
          'infer_threads': 2,
          'model_path': '$ocr/PP_OCRv6_small_det',
          'padding': 16,
          'max_side_len': 768,
          'box_thres': 0.45,
          'bitmap_thres': 0.2,
          'unclip_ratio': 1.4,
          'fp16': false,
        },
        'cls': {
          'infer_threads': 1,
          'reco_threads': 2,
          'model_path': '$ocr/PP_LCNet_x0_25_textline_ori',
          'enable': true,
          'most_angle': true,
          'fp16': false,
        },
        'rec': {
          'infer_threads': 1,
          'reco_threads': 2,
          'model_path': '$ocr/PP_OCRv6_small_rec',
          'keys_path': '$ocr/ppocr_keys_v6.txt',
          'fp16': false,
        },
      }),
    );
    await measure('OCR initialize + blank-image inference', () async {
      await inference.initializeOcr(config.path);
      final result = await inference.recognize(config.path, [
        OcrImage(
          rgba: Uint8List(128 * 128 * 4)..fillRange(0, 128 * 128 * 4, 255),
          previewPng: Uint8List(0),
          width: 128,
          height: 128,
        ),
      ]);
      if (result.length != 1 || result.single.isNotEmpty) {
        throw StateError('Unexpected blank-image OCR result: $result');
      }
    });
    final tts = '$assets/speech/piper-zh_CN-xiao_ya-medium';
    final wav = '${temporary.path}/hello.wav';
    await measure('TTS initialize + synthesis', () async {
      await inference.synthesize(
        model: '$tts/model.onnx',
        config: '$tts/model.onnx.json',
        pinyin: 'ni3 hao3',
        output: wav,
        lengthScale: 1.0,
        repeat: 1,
      );
      if (await File(wav).length() <= 44) throw StateError('Empty WAV');
    });
    await measure('ASR initialize + recognition', () async {
      final recognized = await inference.recognizeWav(
        '$assets/speech/funasr-paraformer-zh',
        '$assets/speech/funasr-fsmn-vad',
        wav,
      );
      stdout.writeln('ASR: $recognized');
      if (recognized.trim().isEmpty) throw StateError('Empty ASR result');
    });
  } finally {
    await inference.dispose();
    timer.cancel();
    await temporary.delete(recursive: true);
  }
}
