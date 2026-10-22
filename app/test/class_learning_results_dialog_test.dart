import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
