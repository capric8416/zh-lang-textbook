import 'dart:typed_data';

class OcrImage {
  const OcrImage({
    required this.rgba,
    required this.previewPng,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final Uint8List previewPng;
  final int width;
  final int height;

  int get rowBytes => width * 4;
}
