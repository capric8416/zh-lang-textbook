import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/models/handwriting.dart';
import 'package:zh_textbook/models/practice.dart';
import 'package:zh_textbook/models/practice_record_answers.dart';
import 'package:zh_textbook/widgets/original_handwriting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'multiple cells preserve geometry, brush and out-of-cell points in file',
    () async {
      final document = InkDocument.empty();
      for (final cell in document.cells) {
        cell.strokes.add(
          InkStroke(0xff2040ff, 0.025, [
            const Offset(-0.02, 0.3),
            const Offset(0.5, 0.6),
            const Offset(1.02, 0.9),
          ]),
        );
        cell.strokes.add(InkStroke(0xffff0000, 0.05, [const Offset(0.4, 0.2)]));
      }
      final directory = await Directory.systemTemp.createTemp(
        'handwriting-lab-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/strokes.json.gz');
      await file.writeAsBytes(document.encodeCompressed());
      final bytes = await file.readAsBytes();
      expect(utf8.decode(gzip.decode(bytes)), document.encode());
      final restored = InkDocument.decodeBytes(bytes);
      expect(restored.encode(), document.encode());
      expect(restored.cells.length, 7);
      expect(restored.cells.where((c) => c.grid == 'pinyin').length, 3);
      for (var i = 0; i < document.cells.length; i++) {
        for (final scale in [0.5, 1.0, 1.5]) {
          expect(
            await pixels(restored.cells[i], scale),
            await pixels(document.cells[i], scale),
          );
        }
      }
    },
  );

  test('empty cells round-trip; unsupported version is rejected', () {
    final document = InkDocument([
      InkCell('hanzi', const Size(72, 72), []),
      InkCell('hanzi', const Size(72, 72), []),
    ]);
    expect(InkDocument.decode(document.encode()).encode(), document.encode());
    expect(
      () => InkDocument.decode(
        document.encode().replaceFirst('"version":1', '"version":2'),
      ),
      throwsFormatException,
    );
  });

  test('file reader rejects plain JSON and corrupt gzip', () {
    expect(
      () => InkDocument.decodeBytes(utf8.encode(InkDocument.empty().encode())),
      throwsA(isA<Exception>()),
    );
    expect(
      () => InkDocument.decodeBytes([0x1f, 0x8b, 0]),
      throwsA(isA<Exception>()),
    );
  });

  testWidgets('history expands and renders handwriting with per-cell OCR', (
    tester,
  ) async {
    final document = InkDocument([
      InkCell('hanzi', const Size(72, 72), []),
      InkCell('hanzi', const Size(72, 72), []),
    ]);
    document.cells.first.strokes.add(
      InkStroke(0xff000000, 0.04, const [Offset(0.2, 0.3), Offset(0.8, 0.7)]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OriginalHandwriting(
            record: {
              'direction': 'writeHanzi',
              'expectedAnswer': '春天',
              'handwritingGzip': base64Encode(document.encodeCompressed()),
              'ocrResults': const ['春', ''],
              'reviewBits': base64Encode(const [1]),
            },
          ),
        ),
      ),
    );
    expect(find.text('作答与批改'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('识别：春'), findsOneWidget);
    expect(find.text('识别：—'), findsOneWidget);
    expect(find.text('正确：春'), findsOneWidget);
    expect(find.text('复核：正确'), findsOneWidget);
    expect(find.text('复核：错误'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is InkPainter,
      ),
      findsNWidgets(2),
    );
  });

  test(
    'fixed black brush converts absolute points and width to cell-relative',
    () {
      final stroke = InkStroke.fromAbsolute(
        color: 0xff000000,
        width: 2.2,
        cellSize: const Size(72, 72),
        points: const [Offset(18, 36), Offset(72, 72)],
      );
      expect(stroke.color, 0xff000000);
      expect(stroke.width, closeTo(2.2 / 72, 0.000001));
      expect(stroke.points, const [Offset(0.25, 0.5), Offset(1, 1)]);
    },
  );

  test(
    'practice prompt and expected answer follow the requested direction',
    () {
      final question = PracticeQuestion(
        id: 'q',
        kind: '词语',
        category: '词',
        answerLines: const ['洁白'],
        promptLines: const ['jié bái'],
        source: '测试',
        chapterId: 'c',
      );
      expect(
        promptForPracticeDirection(question, PracticeDirection.writePinyin),
        '洁白',
      );
      expect(
        expectedAnswerForPracticeDirection(
          question,
          PracticeDirection.writePinyin,
        ),
        'jié bái',
      );
      expect(
        expectedAnswerForPracticeDirection(
          question,
          PracticeDirection.writeHanzi,
        ),
        '洁白',
      );
    },
  );
}

Future<List<int>> pixels(InkCell cell, double scale) async {
  final size = Size(cell.size.width * scale, cell.size.height * scale);
  final recorder = ui.PictureRecorder();
  InkPainter(cell).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return bytes!.buffer
        .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)
        .toList();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
