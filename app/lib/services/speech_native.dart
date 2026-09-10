import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _TtsCreateNative =
    Pointer<Void> Function(Pointer<Utf8> model, Pointer<Utf8> config);
typedef _TtsCreateDart =
    Pointer<Void> Function(Pointer<Utf8> model, Pointer<Utf8> config);
typedef _DestroyNative = Void Function(Pointer<Void> handle);
typedef _DestroyDart = void Function(Pointer<Void> handle);
typedef _SynthesizeNative =
    Int32 Function(
      Pointer<Void> handle,
      Pointer<Utf8> pinyin,
      Pointer<Utf8> output,
      Float lengthScale,
      Int32 repeat,
    );
typedef _SynthesizeDart =
    int Function(
      Pointer<Void> handle,
      Pointer<Utf8> pinyin,
      Pointer<Utf8> output,
      double lengthScale,
      int repeat,
    );
typedef _AsrCreateNative =
    Pointer<Void> Function(
      Pointer<Utf8> modelDirectory,
      Pointer<Utf8> vadDirectory,
    );
typedef _AsrCreateDart =
    Pointer<Void> Function(
      Pointer<Utf8> modelDirectory,
      Pointer<Utf8> vadDirectory,
    );
typedef _RecognizeNative =
    Int32 Function(
      Pointer<Void> handle,
      Pointer<Utf8> wavPath,
      Pointer<Utf8> output,
      Int32 outputCapacity,
    );
typedef _RecognizeDart =
    int Function(
      Pointer<Void> handle,
      Pointer<Utf8> wavPath,
      Pointer<Utf8> output,
      int outputCapacity,
    );

class SpeechNative {
  SpeechNative._() {
    final library = _openLibrary();
    _ttsCreate = library.lookupFunction<_TtsCreateNative, _TtsCreateDart>(
      'zh_speech_tts_create',
    );
    _ttsDestroy = library.lookupFunction<_DestroyNative, _DestroyDart>(
      'zh_speech_tts_destroy',
    );
    _synthesize = library.lookupFunction<_SynthesizeNative, _SynthesizeDart>(
      'zh_speech_tts_synthesize_wav',
    );
    _asrCreate = library.lookupFunction<_AsrCreateNative, _AsrCreateDart>(
      'zh_speech_asr_create',
    );
    _asrDestroy = library.lookupFunction<_DestroyNative, _DestroyDart>(
      'zh_speech_asr_destroy',
    );
    _recognize = library.lookupFunction<_RecognizeNative, _RecognizeDart>(
      'zh_speech_asr_recognize_wav',
    );
  }

  static SpeechNative? _instance;
  static SpeechNative get instance => _instance ??= SpeechNative._();

  late final _TtsCreateDart _ttsCreate;
  late final _DestroyDart _ttsDestroy;
  late final _SynthesizeDart _synthesize;
  late final _AsrCreateDart _asrCreate;
  late final _DestroyDart _asrDestroy;
  late final _RecognizeDart _recognize;
  Pointer<Void>? _ttsHandle;
  Pointer<Void>? _asrHandle;

  void initializeTts({required String model, required String config}) {
    if (_ttsHandle != null) return;
    final modelPath = model.toNativeUtf8();
    final configPath = config.toNativeUtf8();
    try {
      final handle = _ttsCreate(modelPath, configPath);
      if (handle == nullptr) throw StateError('Piper 模型初始化失败');
      _ttsHandle = handle;
    } finally {
      malloc.free(configPath);
      malloc.free(modelPath);
    }
  }

  void synthesizeWav({
    required String numericPinyin,
    required String outputPath,
    double lengthScale = 1.25,
    int repeat = 1,
  }) {
    final handle = _ttsHandle;
    if (handle == null) throw StateError('Piper 尚未初始化');
    final pinyin = numericPinyin.toNativeUtf8();
    final output = outputPath.toNativeUtf8();
    try {
      final code = _synthesize(handle, pinyin, output, lengthScale, repeat);
      if (code != 0) throw StateError('Piper 合成失败，错误码 $code');
    } finally {
      malloc.free(output);
      malloc.free(pinyin);
    }
  }

  void initializeAsr({
    required String modelDirectory,
    required String vadDirectory,
  }) {
    if (_asrHandle != null) return;
    final model = modelDirectory.toNativeUtf8();
    final vad = vadDirectory.toNativeUtf8();
    try {
      final handle = _asrCreate(model, vad);
      if (handle == nullptr) throw StateError('FunASR 模型初始化失败');
      _asrHandle = handle;
    } finally {
      malloc.free(vad);
      malloc.free(model);
    }
  }

  String recognizeWav(String wavPath) {
    final handle = _asrHandle;
    if (handle == null) throw StateError('FunASR 尚未初始化');
    final path = wavPath.toNativeUtf8();
    const capacity = 16 * 1024;
    final output = malloc<Uint8>(capacity).cast<Utf8>();
    try {
      final length = _recognize(handle, path, output, capacity);
      if (length == -3) throw StateError('没有检测到清晰的朗读语音');
      if (length < 0) throw StateError('FunASR 识别失败，错误码 $length');
      if (length >= capacity) throw StateError('FunASR 返回内容过长');
      return output.toDartString(length: length);
    } finally {
      malloc.free(output);
      malloc.free(path);
    }
  }

  void dispose() {
    final tts = _ttsHandle;
    final asr = _asrHandle;
    if (tts != null) _ttsDestroy(tts);
    if (asr != null) _asrDestroy(asr);
    _ttsHandle = null;
    _asrHandle = null;
  }

  DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) return DynamicLibrary.open('libzh_speech.so');
    if (Platform.isIOS) return DynamicLibrary.process();
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isLinux) {
      final bundled = File('$executableDirectory/lib/libzh_speech.so');
      if (bundled.existsSync()) return DynamicLibrary.open(bundled.path);
      return DynamicLibrary.open('libzh_speech.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('$executableDirectory/zh_speech.dll');
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open(
        '$executableDirectory/../Frameworks/libzh_speech.dylib',
      );
    }
    throw UnsupportedError('当前平台没有可用的语音原生库');
  }
}
