import 'dart:isolate';
import 'dart:io';

import '../models/ocr.dart';
import 'inference_worker.dart';
import 'ocr_native.dart';
import 'speech_native.dart';

/// The UI sends paths, text and transferable pixels, never native pointers.
class NativeInference {
  NativeInference._();
  static final instance = NativeInference._();
  InferenceWorker _worker = InferenceWorker(_createHandler);

  Future<void> initializeOcr(String config) async {
    await _worker.run('ocrInit', {'config': config});
  }

  Future<List<String>> recognize(String config, List<OcrImage> images) async {
    final result = await _worker.run('ocr', {
      'config': config,
      'images': [
        for (final image in images)
          {
            'pixels': TransferableTypedData.fromList([image.rgba]),
            'width': image.width,
            'height': image.height,
          },
      ],
    });
    return (result as List).cast<String>();
  }

  Future<void> initializeTts(String model, String config) async {
    await _worker.run('ttsInit', {'model': model, 'config': config});
  }

  Future<void> synthesize({
    required String model,
    required String config,
    required String pinyin,
    required String output,
    required double lengthScale,
    required int repeat,
  }) async {
    await _worker.run('tts', {
      'model': model,
      'config': config,
      'pinyin': pinyin,
      'output': output,
      'lengthScale': lengthScale,
      'repeat': repeat,
    });
  }

  Future<void> initializeAsr(String model, String vad) async {
    await _worker.run('asrInit', {'model': model, 'vad': vad});
  }

  Future<String> recognizeWav(String model, String vad, String wav) async {
    return await _worker.run('asr', {'model': model, 'vad': vad, 'wav': wav})
        as String;
  }

  Future<void> encodeSnac(
    String encoder,
    String decoder,
    String wav,
    String output,
  ) async {
    await _worker.run('snacEncode', {
      'encoder': encoder,
      'decoder': decoder,
      'input': wav,
      'output': output,
    });
  }

  Future<void> decodeSnac(
    String encoder,
    String decoder,
    String input,
    String wav,
  ) async {
    await _worker.run('snacDecode', {
      'encoder': encoder,
      'decoder': decoder,
      'input': input,
      'output': wav,
    });
  }

  Future<void> releaseOcr() async => await _worker.run('ocrDispose', {});

  Future<void> dispose() async {
    final old = _worker;
    await old.close();
    _worker = InferenceWorker(_createHandler);
  }
}

InferenceHandler _createHandler() => _NativeHandler();

class _NativeHandler implements InferenceHandler {
  final _ocr = OcrNative();
  SpeechNative? _speech;
  SpeechNative get speech => _speech ??= SpeechNative.instance;

  @override
  Object? execute(String operation, Map<String, Object?> arguments) {
    String text(String key) => arguments[key] as String;
    switch (operation) {
      case 'ocrInit':
        _ocr.initialize(text('config'));
        return null;
      case 'ocr':
        _ocr.initialize(text('config'));
        return [
          for (final raw in arguments['images'] as List)
            _ocr.recognize(
              (raw['pixels'] as TransferableTypedData)
                  .materialize()
                  .asUint8List(),
              raw['width'] as int,
              raw['height'] as int,
            ),
        ];
      case 'ttsInit':
      case 'tts':
        speech.initializeTts(model: text('model'), config: text('config'));
        if (operation == 'tts') {
          final output = File(text('output'));
          if (!output.existsSync() || output.lengthSync() <= 44) {
            final temporary = File('${output.path}.writing.wav');
            try {
              speech.synthesizeWav(
                numericPinyin: text('pinyin'),
                outputPath: temporary.path,
                lengthScale: arguments['lengthScale'] as double,
                repeat: arguments['repeat'] as int,
              );
              temporary.renameSync(output.path);
            } finally {
              if (temporary.existsSync()) temporary.deleteSync();
            }
          }
        }
        return null;
      case 'asrInit':
      case 'asr':
        speech.initializeAsr(
          modelDirectory: text('model'),
          vadDirectory: text('vad'),
        );
        return operation == 'asr' ? speech.recognizeWav(text('wav')) : null;
      case 'snacEncode':
      case 'snacDecode':
        speech.initializeSnac(
          encoder: text('encoder'),
          decoder: text('decoder'),
        );
        if (operation == 'snacEncode') {
          speech.encodeSnac(text('input'), text('output'));
        } else {
          speech.decodeSnac(text('input'), text('output'));
        }
        return null;
      case 'ocrDispose':
        _ocr.dispose();
        return null;
      default:
        throw ArgumentError('Unknown inference operation: $operation');
    }
  }

  @override
  void dispose() {
    _ocr.dispose();
    _speech?.dispose();
  }
}
