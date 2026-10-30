import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/models/handwriting.dart';
import 'package:zh_textbook/services/account_api.dart';
import 'package:zh_textbook/widgets/class_learning_results_dialog.dart';

class _PagedApi extends AccountApi {
  _PagedApi(this.pages);

  final Map<String, List<Map<String, dynamic>>> pages;
  final List<String> requestedCursors = [];

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    Map<String, String>? queryParameters,
    bool authenticated = true,
    String? tokenOverride,
  }) async {
    final beforeTime = queryParameters!['beforeTime'];
    final key = beforeTime == null
        ? 'initial'
        : '$beforeTime|${queryParameters['afterId']}|${queryParameters['snapshotRowId']}';
    requestedCursors.add(key);
    final records = pages[key] ?? const [];
    return {
      'records': records,
      'nextCursor': records.length == 100
          ? {
              'beforeTime': '2026-10-22T00:00:00.000Z',
              'afterId': '0123456789abcdef0123456789abcdef',
              'snapshotRowId': 17,
            }
          : null,
      'limit': int.parse(queryParameters['limit']!),
    };
  }
}

Map<String, dynamic> _record(int index) => {
  'id': 'record-$index',
  'studentId': 'student-${index % 2}',
  'classId': 'class-a',
  'textbookKey': 'zh-lang-grade3a-textbook-struct.json',
  'questionId': 'question-${index % 3}',
  'chapterId': 'chapter-1',
  'questionKind': '字词',
  'category': '字词',
  'source': '课文',
  'direction': 'writeHanzi',
  'prompt': '题目 $index',
  'studentAnswer': '答案',
  'expectedAnswer': '答案',
  'isCorrect': true,
  'occurredAt':
      '2026-10-22T00:${(index % 60).toString().padLeft(2, '0')}:00.000Z',
  'createdAt': '2026-10-22 00:00:00',
  'displayName': '学生',
  'username': 'student',
};

void main() {
  test('lays out exported writing cells horizontally and wraps them', () {
    expect(classLearningReportInkLayoutCss, contains('display:flex'));
    expect(classLearningReportInkLayoutCss, contains('flex-flow:row wrap'));
    expect(classLearningReportInkLayoutCss, contains('grid-column:1/-1'));
    expect(classLearningReportInkLayoutCss, contains('max-width:none'));
  });

  test('prepares handwriting SVG data and embedded speech WAV data', () async {
    final document = InkDocument([
      InkCell('hanzi', const Size(140, 140), [
        InkStroke(const Color(0xff123456).toARGB32(), 0.04, const [
          Offset(0.1, 0.2),
          Offset(0.8, 0.9),
        ]),
      ]),
    ]);
    final speechInput = Uint8List.fromList([1, 2, 3]);
    final wavOutput = Uint8List.fromList([82, 73, 70, 70, 4, 5, 6]);
    Uint8List? decodedInput;

    final records = await prepareClassLearningReportRecords(
      [
        {
          'id': 'writing',
          'direction': 'writeHanzi',
          'handwritingGzip': base64Encode(document.encodeCompressed()),
        },
        {
          'id': 'reading',
          'direction': 'readAloud',
          'speechSnac': base64Encode(speechInput),
        },
      ],
      decodeSpeech: (bytes) async {
        decodedInput = bytes;
        return wavOutput;
      },
    );

    final handwriting = records.first['handwritingDocument'] as Map;
    expect((handwriting['cells'] as List).single['grid'], 'hanzi');
    expect(records.first.containsKey('handwritingGzip'), isFalse);
    expect(decodedInput, speechInput);
    expect(records.last['speechWav'], base64Encode(wavOutput));
    expect(records.last.containsKey('speechSnac'), isFalse);
  });

  test('keeps exporting when original-answer data is malformed', () async {
    final records = await prepareClassLearningReportRecords([
      {
        'id': 'writing',
        'direction': 'writePinyin',
        'handwritingGzip': 'not-base64',
      },
      {
        'id': 'reading',
        'direction': 'readAloud',
        'speechSnac': base64Encode([1]),
      },
    ], decodeSpeech: (_) async => throw StateError('decode failed'));

    expect(records.first['handwritingError'], isTrue);
    expect(records.last['speechError'], isTrue);
  });

  testWidgets('opens after one small page and loads more only on demand', (
    tester,
  ) async {
    final api = _PagedApi({
      'initial': List.generate(100, _record),
      '2026-10-22T00:00:00.000Z|0123456789abcdef0123456789abcdef|17': [
        _record(100),
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ClassLearningResultsDialog(
          api: api,
          classId: 'class-a',
          className: '测试班',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.requestedCursors, ['initial']);
    expect(find.textContaining('已加载 100 条'), findsNWidgets(2));
    expect(find.textContaining('统计仅基于已加载记录'), findsOneWidget);

    await tester.tap(find.textContaining('加载更多记录'));
    await tester.pumpAndSettle();
    expect(api.requestedCursors, [
      'initial',
      '2026-10-22T00:00:00.000Z|0123456789abcdef0123456789abcdef|17',
    ]);
    expect(find.textContaining('已加载 101 条'), findsOneWidget);
    expect(find.textContaining('已加载全部记录'), findsOneWidget);
  });
}
