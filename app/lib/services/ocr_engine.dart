import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ocr.dart';

typedef _CreateNative = Pointer<Void> Function(Pointer<Utf8> configPath);
typedef _CreateDart = Pointer<Void> Function(Pointer<Utf8> configPath);
typedef _DestroyNative = Void Function(Pointer<Void> handle);
typedef _DestroyDart = void Function(Pointer<Void> handle);
typedef _RecognizeNative =
    Int32 Function(
      Pointer<Void> handle,
      Pointer<Uint8> rgba,
      Int32 width,
      Int32 height,
      Int32 rowBytes,
      Pointer<Utf8> output,
      Int32 outputCapacity,
    );
typedef _RecognizeDart =
    int Function(
      Pointer<Void> handle,
      Pointer<Uint8> rgba,
      int width,
      int height,
      int rowBytes,
      Pointer<Utf8> output,
      int outputCapacity,
    );

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

  Pointer<Void>? _handle;
  _DestroyDart? _destroy;
  _RecognizeDart? _recognize;
  Future<void>? _initializing;

  Future<void> initialize() => _initializing ??= _initialize();

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

    final library = _openLibrary();
    final create = library.lookupFunction<_CreateNative, _CreateDart>(
      'zh_ocr_create',
    );
    _destroy = library.lookupFunction<_DestroyNative, _DestroyDart>(
      'zh_ocr_destroy',
    );
    _recognize = library.lookupFunction<_RecognizeNative, _RecognizeDart>(
      'zh_ocr_recognize_rgba',
    );
    final configPath = config.path.toNativeUtf8();
    try {
      final handle = create(configPath);
      if (handle == nullptr) {
        throw StateError('PP-OCRv6 small 模型初始化失败');
      }
      _handle = handle;
    } finally {
      malloc.free(configPath);
    }
  }

  Future<List<String>> recognizeAll(List<OcrImage> images) async {
    await initialize();
    // Yield once so the progress indicator is painted before native inference.
    await Future<void>.delayed(Duration.zero);
    return [for (final image in images) _recognizeOne(image)];
  }

  String _recognizeOne(OcrImage image) {
    final handle = _handle;
    final recognize = _recognize;
    if (handle == null || recognize == null) {
      throw StateError('OCR 引擎尚未初始化');
    }
    final pixels = malloc<Uint8>(image.rgba.length);
    const outputCapacity = 4096;
    final output = malloc<Uint8>(outputCapacity).cast<Utf8>();
    try {
      pixels.asTypedList(image.rgba.length).setAll(0, image.rgba);
      final length = recognize(
        handle,
        pixels,
        image.width,
        image.height,
        image.rowBytes,
        output,
        outputCapacity,
      );
      if (length < 0) throw StateError('OCR 推理失败，错误码 $length');
      if (length >= outputCapacity) throw StateError('OCR 返回内容过长');
      return output.toDartString(length: length);
    } finally {
      malloc.free(output);
      malloc.free(pixels);
    }
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

  DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) return DynamicLibrary.open('libzh_ocr.so');
    if (Platform.isIOS) return DynamicLibrary.process();
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isLinux) {
      final bundled = File('$executableDirectory/lib/libzh_ocr.so');
      if (bundled.existsSync()) return DynamicLibrary.open(bundled.path);
      final development = File(
        '${Directory.current.path}/native/ocr/build/libzh_ocr.so',
      );
      if (development.existsSync()) {
        return DynamicLibrary.open(development.path);
      }
      return DynamicLibrary.open('libzh_ocr.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('$executableDirectory/zh_ocr.dll');
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open(
        '$executableDirectory/../Frameworks/libzh_ocr.dylib',
      );
    }
    throw UnsupportedError('当前平台没有可用的 OCR 原生库');
  }

  void dispose() {
    final handle = _handle;
    if (handle != null) _destroy?.call(handle);
    _handle = null;
  }
}
