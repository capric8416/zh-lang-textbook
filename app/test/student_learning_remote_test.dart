import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zh_textbook/services/account_api.dart';
import 'package:zh_textbook/services/practice_record_sync.dart';
import 'package:zh_textbook/services/student_learning_history.dart';

class HistoryApi extends AccountApi {
  bool offline = false;
  final queries = <Map<String, String>?>[];
  @override
  Future<String?> get token async => 'session-a';
  @override
  Future<String?> get accountId async => 'a';
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    Map<String, String>? queryParameters,
    bool authenticated = true,
    String? tokenOverride,
  }) async {
    expect(path, 'practice/records');
    expect(tokenOverride, 'session-a');
    if (offline) throw const AccountApiException('offline');
    queries.add(queryParameters);
    final first = queryParameters?['afterId'] == null;
    return {
      'records': [
        {
          'id': first ? 'one' : 'two',
          'studentId': 'a',
          'classId': first ? null : 'old-class',
          'isCorrect': 1,
        },
      ],
      'nextCursor': first
          ? {'beforeTime': '2026-10-21T10:00:00Z', 'afterId': 'one'}
          : null,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('student-history-test-');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test(
    'a fresh device fetches every page, persists cache and keeps it on network failure',
    () async {
      final api = HistoryApi();
      expect(await StudentLearningHistory.load('a'), isEmpty);
      final pages = await StudentLearningHistory.refresh(api, 'a').toList();
      expect(pages.map((p) => p.length), [2]);
      expect(api.queries.last?['afterId'], 'one');
      expect(
        pages.last.every((r) => r.syncState == AttemptSyncState.uploaded),
        isTrue,
      );
      expect((await PracticeRecordSync.statusFor('a')).uploadedCount, 2);
      api.offline = true;
      await expectLater(
        StudentLearningHistory.refresh(api, 'a').toList(),
        throwsA(isA<AccountApiException>()),
      );
      expect((await StudentLearningHistory.load('a')).length, 2);
      expect(await StudentLearningHistory.load('b'), isEmpty);
    },
  );

  test(
    'a different signed-in account cannot fetch into this account cache',
    () async {
      final api = HistoryApi();
      await expectLater(
        StudentLearningHistory.refresh(api, 'b').toList(),
        throwsA(isA<AccountApiException>()),
      );
      expect(api.queries, isEmpty);
      expect(await StudentLearningHistory.load('b'), isEmpty);
    },
  );
}
