import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

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

/// Only accessed by the inference isolate.
class OcrNative {
  Pointer<Void>? _handle;
  _DestroyDart? _destroy;
  _RecognizeDart? _recognize;
  void initialize(String path) {
    if (_handle != null) return;
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
    final configPath = path.toNativeUtf8();
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

  String recognize(Uint8List rgba, int width, int height) {
    if (width <= 0 || height <= 0 || rgba.length != width * height * 4) {
      throw ArgumentError('OCR 图像尺寸与 RGBA 数据不匹配');
    }
    final handle = _handle;
    final recognize = _recognize;
    if (handle == null || recognize == null) {
      throw StateError('OCR 引擎尚未初始化');
    }
    final pixels = malloc<Uint8>(rgba.length);
    const outputCapacity = 4096;
    final output = malloc<Uint8>(outputCapacity).cast<Utf8>();
    try {
      pixels.asTypedList(rgba.length).setAll(0, rgba);
      final length = recognize(
        handle,
        pixels,
        width,
        height,
        width * 4,
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
