import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'account_api.dart';
import 'local_study_identity.dart';
import 'practice_attempt_store.dart';

class PracticeRecordSync {
  static const _storageKey = 'pending_practice_records_v1';
  static bool _flushing = false;
  static Future<void> _pendingTail = Future<void>.value();

  static Future<void> record({
    required AccountApi api,
    required String textbookKey,
    required String questionId,
    required String chapterId,
    required String questionKind,
    required String category,
    required String source,
    required String direction,
    required String prompt,
    required String studentAnswer,
    required String expectedAnswer,
    required bool isCorrect,
    DateTime? occurredAt,
  }) async {
    final sessionToken = await api.token;
    final accountId = await api.accountId;
    final id = _newId();
    final record = <String, Object?>{
      'id': id,
      'studentId': accountId,
      'textbookKey': textbookKey,
      'questionId': questionId,
      'chapterId': chapterId,
      'questionKind': questionKind,
      'category': category,
      'source': source,
      'direction': direction,
      'prompt': prompt,
      'studentAnswer': studentAnswer,
      'expectedAnswer': expectedAnswer,
      'isCorrect': isCorrect,
      'occurredAt': (occurredAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
    if (sessionToken == null || sessionToken.isEmpty || accountId == null) {
      throw StateError('请先登录后再作答');
    }
    final namespace = LocalStudyIdentity.accountNamespace(accountId);
    await PracticeAttemptStore.append(namespace, record);
    await _enqueue(record);
    schedule(api: api);
  }

  static void schedule({required AccountApi api}) {
    unawaited(_flushSafely(api));
  }

  static Future<void> _flushSafely(AccountApi api) async {
    try {
      await flush(api: api);
    } catch (_) {
      // Uploads are best-effort; local practice progress remains authoritative.
    }
  }

  static Future<void> flush({required AccountApi api}) async {
    if (_flushing || !api.configured) return;
    _flushing = true;
    try {
      final accountId = await api.accountId;
      if (accountId == null) return;
      final sessionToken = await api.token;
      if (sessionToken == null) return;
      while (true) {
        final preferences = await SharedPreferences.getInstance();
        final pending = _readPending(preferences);
        if (pending.isEmpty) return;
        final recordIndex = pending.indexWhere(
          (record) => record['studentId'] == accountId,
        );
        if (recordIndex < 0) return;
        final record = pending[recordIndex];
        final payload = Map<String, Object?>.from(record)..remove('studentId');
        try {
          await api.request(
            'practice/records',
            method: 'POST',
            body: payload,
            tokenOverride: sessionToken,
          );
        } on AccountApiException catch (error) {
          if (error.statusCode == 400 || error.statusCode == 403) {
            await _removePending(record['id']);
            continue;
          }
          return;
        } catch (_) {
          // Keep pending records on network/server errors for a later retry.
          return;
        }
        await _removePending(record['id']);
      }
    } finally {
      _flushing = false;
    }
  }

  static List<Map<String, Object?>> _readPending(
    SharedPreferences preferences,
  ) {
    final raw = preferences.getString(_storageKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();
    } on FormatException {
      return [];
    }
  }

  static Future<void> _savePending(
    SharedPreferences preferences,
    List<Map<String, Object?>> pending,
  ) => preferences.setString(_storageKey, jsonEncode(pending));

  static Future<void> _enqueue(Map<String, Object?> record) =>
      _mutatePending((pending) async {
        if (!pending.any((item) => item['id'] == record['id'])) {
          pending.add(record);
        }
      });

  static Future<void> _removePending(Object? id) =>
      _mutatePending((pending) async {
        pending.removeWhere((record) => record['id'] == id);
      });

  static Future<void> _mutatePending(
    Future<void> Function(List<Map<String, Object?>> pending) update,
  ) {
    final result = Completer<void>();
    final operation = _pendingTail.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        final pending = _readPending(preferences);
        await update(pending);
        await _savePending(preferences, pending);
        result.complete();
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    _pendingTail = operation.catchError((_) {});
    return result.future;
  }

  static String _newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
