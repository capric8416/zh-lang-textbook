import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';

import '../models/textbook.dart';

enum Semester {
  first('a', '上学期'),
  second('b', '下学期');

  const Semester(this.code, this.label);

  final String code;
  final String label;
}

class TextbookSelection {
  const TextbookSelection({required this.grade, required this.semester});

  final int grade;
  final Semester semester;

  String get fileName =>
      'zh-lang-grade$grade${semester.code}-textbook-struct.json';

  String get assetPath => 'assets/json_reviewed/$fileName';

  String get label => '$grade年级 · ${semester.label}';
}

class TextbookRepository {
  const TextbookRepository();

  Future<Textbook> load(TextbookSelection selection) async {
    try {
      final source = await rootBundle.loadString(selection.assetPath);
      final decoded = Textbook.fromJsonString(source);
      // Build the reference index directly from the original structure so
      // appendix refs do not need to be retained by display models.
      return decoded;
    } on FlutterError catch (_) {
      throw TextbookLoadException(
        '未找到 ${selection.label} 教材：${selection.fileName}',
      );
    } on FormatException catch (error) {
      throw TextbookLoadException('教材格式错误：${error.message}');
    }
  }
}

class TextbookLoadException implements Exception {
  const TextbookLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}
