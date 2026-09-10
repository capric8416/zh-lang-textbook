import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/speech_assessment.dart';
import 'numeric_pinyin.dart';
import 'speech_native.dart';

class SpeechEngine {
  SpeechEngine._();

  static final SpeechEngine instance = SpeechEngine._();

  static const _ttsAsset = 'assets/speech/piper-zh_CN-xiao_ya-medium/';
  static const _asrAsset = 'assets/speech/funasr-paraformer-zh/';
  static const _vadAsset = 'assets/speech/funasr-fsmn-vad/';

  final SoLoud _player = SoLoud.instance;
  final AudioRecorder _recorder = AudioRecorder();
  Future<void>? _audioInitializing;
  Future<void>? _ttsInitializing;
  Future<void>? _asrInitializing;
  String? _recordingPath;
  SoundHandle? _playingHandle;
  AudioSource? _playingSource;

  Future<void> speak({required String pinyin, required String cacheKey}) async {
    final numeric = toNumericPinyin(pinyin);
    if (numeric.isEmpty) throw StateError('教材没有可用于听写的拼音');
    final syllableCount = numeric.split(RegExp(r'\s+')).length;
    final lengthScale = syllableCount > 2 ? 0.8 : 1.25;
    await _initializeTts();
    final cache = await _audioCacheDirectory();
    final output = File(
      '${cache.path}/piper-xiao-ya-v4-${_stableHash('$cacheKey|$numeric')}.wav',
    );
    if (!await output.exists()) {
      // Native inference is synchronous. Yield first so Flutter can paint the
      // loading state before Piper starts running.
      await Future<void>.delayed(Duration.zero);
      SpeechNative.instance.synthesizeWav(
        numericPinyin: numeric,
        outputPath: output.path,
        lengthScale: lengthScale,
        repeat: syllableCount <= 4 ? 2 : 1,
      );
    }
    await _initializeAudio();
    final previous = _playingHandle;
    final previousSource = _playingSource;
    if (previous != null) await _player.stop(previous);
    if (previousSource != null) _player.disposeSource(previousSource);
    final source = await _player.loadFile(output.path, autoDispose: false);
    final handle = _player.play(source);
    if (handle.isError) {
      _player.disposeSource(source);
      throw StateError('系统音频设备无法开始播放');
    }
    _playingHandle = handle;
    _playingSource = source;
    source.allInstancesFinished.first.then((_) {
      if (identical(_playingSource, source)) {
        _playingSource = null;
        _playingHandle = null;
      }
      _player.disposeSource(source);
    });
  }

  Future<void> startRecording() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('没有麦克风权限，请在系统设置中允许录音。');
    }
    final cache = await _audioCacheDirectory();
    final path =
        '${cache.path}/reading-${DateTime.now().microsecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    _recordingPath = path;
  }

  Future<SpeechAssessment> stopAndAssess({
    required String expectedPinyin,
  }) async {
    final path = await _recorder.stop() ?? _recordingPath;
    _recordingPath = null;
    if (path == null) throw StateError('没有可检查的录音');
    try {
      await _initializeAsr();
      await Future<void>.delayed(Duration.zero);
      final text = SpeechNative.instance.recognizeWav(path).trim();
      if (text.isEmpty) throw StateError('没有识别到朗读内容');
      return SpeechAssessment.compare(
        expectedPinyin: expectedPinyin,
        recognizedText: text,
      );
    } finally {
      File(path).delete().ignore();
    }
  }

  Future<void> cancelRecording() async {
    await _recorder.cancel();
    _recordingPath = null;
  }

  Future<void> _initializeAudio() => _audioInitializing ??= _player.init(
    automaticCleanup: true,
    lowLatency: false,
    bufferSize: 4096,
  );

  Future<void> _initializeTts() => _ttsInitializing ??= _loadTts();

  Future<Directory> _audioCacheDirectory() async {
    final temporary = await getTemporaryDirectory();
    final directory = Directory('${temporary.path}/zh_textbook_audio');
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _loadTts() async {
    final directory = await _extractTree(
      _ttsAsset,
      'piper-zh_CN-xiao_ya-medium',
    );
    SpeechNative.instance.initializeTts(
      model: '${directory.path}/model.onnx',
      config: '${directory.path}/model.onnx.json',
    );
  }

  Future<void> _initializeAsr() => _asrInitializing ??= _loadAsr();

  Future<void> _loadAsr() async {
    final models = await Future.wait([
      _extractTree(_asrAsset, 'funasr-paraformer-zh'),
      _extractTree(_vadAsset, 'funasr-fsmn-vad'),
    ]);
    SpeechNative.instance.initializeAsr(
      modelDirectory: models[0].path,
      vadDirectory: models[1].path,
    );
  }

  Future<Directory> _extractTree(String prefix, String targetName) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest
        .listAssets()
        .where((name) => name.startsWith(prefix))
        .toList(growable: false);
    if (assets.isEmpty) throw _missingModels();
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/speech/$targetName');
    await directory.create(recursive: true);
    for (final asset in assets) {
      final relative = asset.substring(prefix.length);
      if (relative.isEmpty) continue;
      final target = File('${directory.path}/$relative');
      await target.parent.create(recursive: true);
      final data = await rootBundle.load(asset);
      if (!await target.exists() ||
          await target.length() != data.lengthInBytes) {
        await target.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
    }
    return directory;
  }

  StateError _missingModels() =>
      StateError('语音模型未打包。请先运行 scripts/download_speech_models.sh。');

  int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final byte in value.codeUnits) {
      hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
