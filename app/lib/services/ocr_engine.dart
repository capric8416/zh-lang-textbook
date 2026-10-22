import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ocr.dart';
import 'native_inference.dart';

class OcrEngine {
  OcrEngine._();

  static final OcrEngine instance = OcrEngine._();

  static const _assetRoot = 'assets/ocr';
  static const _modelFiles = [
    'PP_OCRv6_small_det.bin',
    'PP_OCRv6_small_det.param',
    'PP_OCRv6_small_rec.bin',
    'PP_OCRv6_small_rec.param',
    'PP_LCNet_x0_25_textline_ori.bin',
    'PP_LCNet_x0_25_textline_ori.param',
    'ppocr_keys_v6.txt',
  ];

  String? _configPath;
  Future<void>? _initializing;

  Future<void> initialize() =>
      _initializing ??= _initialize().catchError((Object error) {
        _initializing = null;
        throw error;
      });

  Future<void> _initialize() async {
    final modelDirectory = await _extractModels();
    final config = File('${modelDirectory.path}/config.json');
    await config.writeAsString(
      jsonEncode({
        'save': false,
        'det': {
          'infer_threads': -1,
          'model_path': '${modelDirectory.path}/PP_OCRv6_small_det',
          'padding': 16,
          'max_side_len': 768,
          'box_thres': 0.45,
          'bitmap_thres': 0.2,
          'unclip_ratio': 1.4,
          'fp16': false,
        },
        'cls': {
          'infer_threads': 1,
          'reco_threads': -1,
          'model_path': '${modelDirectory.path}/PP_LCNet_x0_25_textline_ori',
          'enable': true,
          'most_angle': true,
          'fp16': false,
        },
        'rec': {
          'infer_threads': 1,
          'reco_threads': -1,
          'model_path': '${modelDirectory.path}/PP_OCRv6_small_rec',
          'keys_path': '${modelDirectory.path}/ppocr_keys_v6.txt',
          'fp16': false,
        },
      }),
      flush: true,
    );

    _configPath = config.path;
    await NativeInference.instance.initializeOcr(config.path);
  }

  Future<List<String>> recognizeAll(List<OcrImage> images) async {
    await initialize();
    return NativeInference.instance.recognize(_configPath!, images);
  }

  Future<Directory> _extractModels() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/ocr/ppocr-v6-small');
    await directory.create(recursive: true);
    for (final name in _modelFiles) {
      final data = await rootBundle.load('$_assetRoot/$name');
      final target = File('${directory.path}/$name');
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

  Future<void> dispose() async {
    _initializing = null;
    _configPath = null;
    await NativeInference.instance.releaseOcr();
  }
}
