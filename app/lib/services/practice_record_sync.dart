import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_api.dart';
import 'local_study_identity.dart';
import 'practice_attempt_store.dart';

class PracticeRecordSync {
  static const _storageKey = 'pending_practice_records_v1';
  static const _lastSuccessPrefix = 'practice_record_sync_last_success_v1_';
  static const _lastErrorPrefix = 'practice_record_sync_last_error_v1_';
  static bool _flushing = false;
  static String? _flushingAccountId;
  static Future<void> _pendingTail = Future<void>.value();
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static void _notifyChanged() => changes.value++;

  static Future<PracticeRecordSyncStatus> statusFor(String accountId) async {
    final preferences = await SharedPreferences.getInstance();
    final pendingCount = _readPending(
      preferences,
    ).where((record) => record['studentId'] == accountId).length;
    final lastSuccess = DateTime.tryParse(
      preferences.getString('$_lastSuccessPrefix$accountId') ?? '',
    );
    return PracticeRecordSyncStatus(
      pendingCount: pendingCount,
      isSyncing: _flushing && _flushingAccountId == accountId,
      lastSuccessAt: lastSuccess,
      lastError: preferences.getString('$_lastErrorPrefix$accountId'),
    );
  }

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
    if (_flushing) return;
    _flushing = true;
    String? activeAccountId;
    try {
      final accountId = await api.accountId;
      if (accountId == null) return;
      activeAccountId = accountId;
      _flushingAccountId = accountId;
      _notifyChanged();
      if (!api.configured) {
        await _saveFailure(accountId, '账号服务地址未配置，记录已保留。');
        return;
      }
      final sessionToken = await api.token;
      if (sessionToken == null || sessionToken.isEmpty) {
        await _saveFailure(accountId, '当前未登录，记录已保留；重新登录后可继续同步。');
        return;
      }
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
          await _saveFailure(accountId, _explainFailure(error));
          return;
        } catch (error) {
          // Keep pending records on network/server errors for a later retry.
          await _saveFailure(accountId, _explainFailure(error));
          return;
        }
        await _removePending(record['id']);
        await preferences.setString(
          '$_lastSuccessPrefix$accountId',
          DateTime.now().toUtc().toIso8601String(),
        );
        await preferences.remove('$_lastErrorPrefix$accountId');
        _notifyChanged();
      }
    } finally {
      _flushing = false;
      _flushingAccountId = null;
      if (activeAccountId != null) _notifyChanged();
    }
  }

  static Future<void> _saveFailure(String accountId, String message) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('$_lastErrorPrefix$accountId', message);
    _notifyChanged();
  }

  static String _explainFailure(Object error) {
    if (error is AccountApiException) {
      final code = error.statusCode;
      if (code == 400 || code == 403) {
        return '记录未被服务器接受（$code）：${error.message}。记录已保留，可修复后重试。';
      }
      if (code == 401) return '登录状态已失效，请重新登录后重试。';
      return '服务器暂时无法接收记录${code == null ? '' : '（$code）'}：${error.message}';
    }
    return '网络或本地存储暂时不可用：$error';
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
  ) async {
    await preferences.setString(_storageKey, jsonEncode(pending));
    _notifyChanged();
  }

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

@immutable
class PracticeRecordSyncStatus {
  const PracticeRecordSyncStatus({
    required this.pendingCount,
    required this.isSyncing,
    required this.lastSuccessAt,
    required this.lastError,
  });

  final int pendingCount;
  final bool isSyncing;
  final DateTime? lastSuccessAt;
  final String? lastError;
}
