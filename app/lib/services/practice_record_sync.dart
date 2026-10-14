import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'account_api.dart';

class PracticeRecordSync {
  static const _storageKey = 'pending_practice_records_v1';
  static const _maxPending = 2000;
  static bool _flushing = false;

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
    if (await api.token == null) return;
    final accountId = await api.accountId;
    if (accountId == null) return;
    final preferences = await SharedPreferences.getInstance();
    final pending = _readPending(preferences);
    final id = _newId();
    pending.add({
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
    });
    if (pending.length > _maxPending) {
      pending.removeRange(0, pending.length - _maxPending);
    }
    await _savePending(preferences, pending);
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
      final preferences = await SharedPreferences.getInstance();
      while (true) {
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
          // These records cannot be accepted for this account/current class.
          // Preserve local practice progress, but do not reassign stale records
          // to a different class after the student joins one later.
          if (error.statusCode == 400 ||
              error.statusCode == 403 ||
              error.statusCode == 409) {
            pending.removeAt(recordIndex);
            await _savePending(preferences, pending);
            continue;
          }
          return;
        } catch (_) {
          // Keep pending records on network/server errors for a later retry.
          return;
        }
        pending.removeAt(recordIndex);
        await _savePending(preferences, pending);
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

  static String _newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
