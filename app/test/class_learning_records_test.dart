import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/services/account_api.dart';
import 'package:zh_textbook/services/class_learning_records.dart';

class _ClassRecordsApi extends AccountApi {
  _ClassRecordsApi(this.pages, this.nextCursors);

  final Map<String, List<Map<String, dynamic>>> pages;
  final Map<String, Map<String, Object?>?> nextCursors;
  final List<Map<String, String>?> requests = [];

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    Map<String, String>? queryParameters,
    bool authenticated = true,
    String? tokenOverride,
  }) async {
    expect(path, 'classes/class-a/records');
    expect(method, 'GET');
    requests.add(queryParameters);
    final cursorKey = queryParameters!['beforeTime'] == null
        ? 'initial'
        : '${queryParameters['beforeTime']}|${queryParameters['afterId']}|${queryParameters['snapshotRowId']}';
    return {
      'records': pages[cursorKey] ?? [],
      'nextCursor': nextCursors[cursorKey],
      'limit': int.parse(queryParameters['limit']!),
    };
  }
}

void main() {
  test('returns a page and carries the stable cursor forward', () async {
    const nextCursor = {
      'beforeTime': '2026-10-22T10:00:00.000Z',
      'afterId': '0123456789abcdef0123456789abcdef',
      'snapshotRowId': 42,
    };
    final api = _ClassRecordsApi(
      {
        'initial': List.generate(100, (index) => {'id': '$index'}),
        '2026-10-22T10:00:00.000Z|0123456789abcdef0123456789abcdef|42': [
          {'id': '100'},
        ],
      },
      {
        'initial': nextCursor,
        '2026-10-22T10:00:00.000Z|0123456789abcdef0123456789abcdef|42': null,
      },
    );

    final first = await ClassLearningRecords.fetchPage(
      api,
      'class-a',
      limit: 100,
    );
    expect(first.records, hasLength(100));
    expect(first.hasMore, isTrue);
    expect(first.cursor?.snapshotRowId, 42);

    final next = await ClassLearningRecords.fetchPage(
      api,
      'class-a',
      cursor: first.cursor,
      limit: 100,
    );
    expect(next.records, hasLength(1));
    expect(next.hasMore, isFalse);
    expect(api.requests, [
      {'limit': '100'},
      {
        'limit': '100',
        'beforeTime': '2026-10-22T10:00:00.000Z',
        'afterId': '0123456789abcdef0123456789abcdef',
        'snapshotRowId': '42',
      },
    ]);
  });

  test('rejects parameters beyond the Worker page limit', () async {
    final api = _ClassRecordsApi({}, {});
    await expectLater(
      ClassLearningRecords.fetchPage(api, 'class-a', limit: 501),
      throwsArgumentError,
    );
  });
}
