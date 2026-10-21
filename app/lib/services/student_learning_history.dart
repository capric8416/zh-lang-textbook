import 'account_api.dart';
import 'local_study_identity.dart';
import 'practice_attempt_store.dart';
import 'practice_record_sync.dart';

enum AttemptSyncState {
  pending('待同步'),
  uploaded('已上传'),
  unknown('上传状态未确认');

  const AttemptSyncState(this.label);
  final String label;
}

class StudentLearningRecord {
  const StudentLearningRecord(this.data, this.syncState);

  final Map<String, Object?> data;
  final AttemptSyncState syncState;
  String text(String key) => data[key]?.toString() ?? '';
  bool get isCorrect => data['isCorrect'] == true || data['isCorrect'] == 1;
  DateTime? get occurredAt => DateTime.tryParse(text('occurredAt'));
}

class StudentLearningHistory {
  static Future<List<StudentLearningRecord>> load(String accountId) async {
    final namespace = LocalStudyIdentity.accountNamespace(accountId);
    final attempts = await PracticeAttemptStore.read(namespace);
    final pending = await PracticeRecordSync.pendingFor(accountId);
    final receipts = await PracticeAttemptStore.read('${namespace}_uploaded');
    final remote = await PracticeAttemptStore.read('${namespace}_remote');
    return merge(accountId, attempts, pending, receipts, remote: remote);
  }

  static Stream<List<StudentLearningRecord>> refresh(
    AccountApi api,
    String accountId,
  ) async* {
    final token = await api.token;
    if (token == null || await api.accountId != accountId) {
      throw const AccountApiException('请重新登录后查看学习记录');
    }
    final cacheNamespace =
        '${LocalStudyIdentity.accountNamespace(accountId)}_remote';
    final cached = await PracticeAttemptStore.read(cacheNamespace);
    final knownIds = cached.map((r) => r['id']).toSet();
    var query = <String, String>{'limit': '100'};
    final visitedCursors = <String>{};
    while (true) {
      if (await api.accountId != accountId || await api.token != token) {
        throw const AccountApiException('账号已切换，请重新进入学习记录');
      }
      final response = await api
          .request(
            'practice/records',
            queryParameters: query,
            tokenOverride: token,
          )
          .timeout(const Duration(seconds: 30));
      final page = (response['records'] as List)
          .map((r) => Map<String, Object?>.from(r as Map))
          .toList();
      if (page.any((r) => r['studentId'] != accountId)) {
        throw const FormatException('学习记录账号不匹配');
      }
      final additions = page.where((r) => knownIds.add(r['id'])).toList();
      if (additions.isNotEmpty) {
        await PracticeAttemptStore.appendAll(cacheNamespace, additions);
      }
      final next = response['nextCursor'];
      if (next == null) {
        await PracticeRecordSync.rememberRemoteRecords(accountId, knownIds);
        yield await load(accountId);
        break;
      }
      final cursor = Map<String, dynamic>.from(next as Map);
      final key = '${cursor['beforeTime']}|${cursor['afterId']}';
      if (!visitedCursors.add(key)) throw const FormatException('分页游标重复');
      query = {
        'limit': '100',
        'beforeTime': cursor['beforeTime'] as String,
        'afterId': cursor['afterId'] as String,
      };
    }
  }

  // Queue entries also preserve older attempts that predate the local journal.
  static List<StudentLearningRecord> merge(
    String accountId,
    List<Map<String, Object?>> attempts,
    List<Map<String, Object?>> pending,
    List<Map<String, Object?>> receipts, {
    List<Map<String, Object?>> remote = const [],
  }) {
    final ownPending = pending.where((r) => r['studentId'] == accountId);
    final pendingIds = ownPending.map((r) => r['id']).toSet();
    final ownRemote = remote.where((r) => r['studentId'] == accountId);
    final uploadedIds = [...receipts, ...ownRemote].map((r) => r['id']).toSet();
    final byId = <String, Map<String, Object?>>{};
    for (final record in [...attempts, ...ownPending, ...ownRemote]) {
      final id = record['id'];
      if (record['studentId'] != accountId || id is! String || id.isEmpty) {
        continue;
      }
      byId[id] = record;
    }
    final result = byId.entries.map((entry) {
      final state = uploadedIds.contains(entry.key)
          ? AttemptSyncState.uploaded
          : pendingIds.contains(entry.key)
          ? AttemptSyncState.pending
          : AttemptSyncState.unknown;
      return StudentLearningRecord(entry.value, state);
    }).toList();
    result.sort((a, b) {
      final time = (b.occurredAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.occurredAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      return time != 0 ? time : a.text('id').compareTo(b.text('id'));
    });
    return result;
  }
}
