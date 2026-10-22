import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/practice.dart';
import 'local_study_identity.dart';

class QuestionProgress {
  const QuestionProgress({
    this.correctCount = 0,
    this.wrongCount = 0,
    this.lastCorrectAt,
    this.lastWrongAt,
    this.correctStreakStartedAt,
  });

  factory QuestionProgress.fromJson(Map<String, dynamic> json) =>
      QuestionProgress(
        correctCount: json['correct_count'] is int
            ? json['correct_count'] as int
            : 0,
        wrongCount: json['wrong_count'] is int ? json['wrong_count'] as int : 0,
        lastCorrectAt: _date(json['last_correct_at']),
        lastWrongAt: _date(json['last_wrong_at']),
        correctStreakStartedAt: _date(json['correct_streak_started_at']),
      );

  final int correctCount;
  final int wrongCount;
  final DateTime? lastCorrectAt;
  final DateTime? lastWrongAt;

  /// The first correct attempt after the latest wrong attempt (or first-ever
  /// correct attempt), used to determine spaced, stable mastery.
  final DateTime? correctStreakStartedAt;

  int get totalCount => correctCount + wrongCount;

  QuestionMasteryStage get masteryStage {
    if (totalCount == 0) return QuestionMasteryStage.notPracticed;
    final latestWrong = lastWrongAt;
    final latestCorrect = lastCorrectAt;
    if (latestWrong != null &&
        (latestCorrect == null || !latestWrong.isBefore(latestCorrect))) {
      return QuestionMasteryStage.needsReinforcement;
    }
    if (correctCount == 0 || latestCorrect == null) {
      return QuestionMasteryStage.needsReinforcement;
    }
    final streakStart = correctStreakStartedAt;
    if (streakStart != null &&
        latestCorrect.difference(streakStart) >= const Duration(hours: 24)) {
      return QuestionMasteryStage.stable;
    }
    return QuestionMasteryStage.initial;
  }

  /// Previously missed questions stay in focused practice until they reach
  /// stable mastery; a same-day correct answer is only initial mastery.
  bool get isWrong =>
      wrongCount > 0 && masteryStage != QuestionMasteryStage.stable;

  /// Derived from attempt timestamps so restores and old local files use the
  /// same schedule. Repeating an initial success does not postpone its review.
  DateTime? get reviewDueAt => switch (masteryStage) {
    QuestionMasteryStage.initial =>
      (correctStreakStartedAt ?? lastCorrectAt)?.add(const Duration(hours: 24)),
    QuestionMasteryStage.stable => lastCorrectAt?.add(const Duration(days: 7)),
    _ => null,
  };

  bool isAvailableAt(DateTime now) => !(reviewDueAt?.isAfter(now) ?? false);

  double selectionWeight(DateTime now) {
    if (!isAvailableAt(now)) return 0;
    return switch (masteryStage) {
      QuestionMasteryStage.needsReinforcement => 12,
      QuestionMasteryStage.initial => 12,
      QuestionMasteryStage.notPracticed => 6,
      QuestionMasteryStage.stable => 1,
    };
  }

  String reviewMessage(DateTime now) {
    final due = reviewDueAt?.toLocal();
    final waiting = due != null && due.isAfter(now);
    final date = due == null
        ? ''
        : '${due.month}月${due.day}日 ${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}';
    return switch (masteryStage) {
      QuestionMasteryStage.notPracticed => '这个练习方向还没试过，一起来试试。',
      QuestionMasteryStage.needsReinforcement => '这题还需要订正，慢慢想，再试一次。',
      QuestionMasteryStage.initial when waiting =>
        '已答对，稍后再巩固：$date 起可再次练习。间隔至少 24 小时再答对，就能稳定掌握。',
      QuestionMasteryStage.initial => '已到巩固时间，这个练习方向再答对一次，就能稳定掌握。',
      QuestionMasteryStage.stable when waiting => '已经稳定掌握！$date 起再来复习。',
      QuestionMasteryStage.stable => '已经稳定掌握，一起复习一下，保持熟悉。',
    };
  }

  Map<String, dynamic> toJson() => {
    'correct_count': correctCount,
    'wrong_count': wrongCount,
    if (lastCorrectAt != null)
      'last_correct_at': lastCorrectAt!.toIso8601String(),
    if (lastWrongAt != null) 'last_wrong_at': lastWrongAt!.toIso8601String(),
    if (correctStreakStartedAt != null)
      'correct_streak_started_at': correctStreakStartedAt!.toIso8601String(),
  };
}

enum QuestionMasteryStage { notPracticed, needsReinforcement, initial, stable }

class PracticeProgress {
  const PracticeProgress(this.questions);

  final Map<String, QuestionProgress> questions;

  QuestionProgress forQuestion(String id) =>
      questions[id] ?? const QuestionProgress();

  int get completedCount =>
      questions.values.where((item) => item.totalCount > 0).length;

  int get wrongCount => questions.values.where((item) => item.isWrong).length;

  int wrongCountFor(Iterable<PracticeQuestion> availableQuestions) =>
      availableQuestions.fold(0, (count, question) {
        return count +
            PracticeDirection.values
                .where(question.supportsDirection)
                .where(
                  (direction) =>
                      forQuestion(question.attemptId(direction)).isWrong,
                )
                .length;
      });
}

class PracticeProgressStore {
  PracticeProgressStore._(this._preferences, this._key, this._progress);

  final SharedPreferences _preferences;
  final String _key;
  PracticeProgress _progress;

  PracticeProgress get progress => _progress;

  static Future<void> restoreRemote(
    String accountId,
    List<Map<String, dynamic>> rows,
  ) async {
    final namespace = LocalStudyIdentity.accountNamespace(accountId);
    final byTextbook = <String, Map<String, QuestionProgress>>{};
    for (final row in rows) {
      final textbookKey = row['textbookKey'];
      final questionKey = row['questionKey'];
      if (textbookKey is! String ||
          textbookKey.isEmpty ||
          questionKey is! String ||
          questionKey.isEmpty) {
        continue;
      }
      byTextbook.putIfAbsent(
        textbookKey,
        () => {},
      )[questionKey] = _progressFromCounts(
        correctCount: row['correctCount'] is int
            ? row['correctCount'] as int
            : 0,
        wrongCount: row['wrongCount'] is int ? row['wrongCount'] as int : 0,
        lastCorrectAt: _date(row['lastCorrectAt']),
        lastWrongAt: _date(row['lastWrongAt']),
        correctStreakStartedAt: _date(row['correctStreakStartedAt']),
      );
    }
    for (final entry in byTextbook.entries) {
      final store = await open(entry.key, namespace: namespace);
      final merged = {...store.progress.questions};
      for (final remote in entry.value.entries) {
        merged[remote.key] = _mergeQuestionProgress(
          merged[remote.key] ?? const QuestionProgress(),
          remote.value,
        );
      }
      store._progress = PracticeProgress(merged);
      await store._save();
    }
  }

  static Future<PracticeProgressStore> open(
    String textbookKey, {
    String? namespace,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final owner = namespace ?? await LocalStudyIdentity.currentNamespace();
    final key = 'practice_progress_${owner}_$textbookKey';
    final raw = preferences.getString(key);
    try {
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final records = <String, QuestionProgress>{};
        final questions = decoded['questions'];
        if (questions is Map) {
          for (final entry in questions.entries) {
            if (entry.key is String && entry.value is Map) {
              records[entry.key as String] = QuestionProgress.fromJson(
                (entry.value as Map).cast<String, dynamic>(),
              );
            }
          }
        } else {
          final done = _strings(decoded['done']);
          final wrong = _strings(decoded['wrong']);
          for (final id in {...done, ...wrong}) {
            final migrated = QuestionProgress(
              correctCount: done.contains(id) ? 1 : 0,
              wrongCount: wrong.contains(id) ? 1 : 0,
            );
            records['$id:writeHanzi'] = migrated;
            records['$id:writePinyin'] = migrated;
          }
        }
        return PracticeProgressStore._(
          preferences,
          key,
          PracticeProgress(records),
        );
      }
    } on FormatException {
      // A corrupted local record should not block practice.
    }
    return PracticeProgressStore._(
      preferences,
      key,
      const PracticeProgress({}),
    );
  }

  bool isBlocked(String id, DateTime now) {
    return !_progress.forQuestion(id).isAvailableAt(now);
  }

  Future<void> record(String questionId, {required bool correct}) async {
    await recordAt(questionId, correct: correct, occurredAt: DateTime.now());
  }

  Future<void> recordAt(
    String questionId, {
    required bool correct,
    required DateTime occurredAt,
  }) async {
    final now = occurredAt.toLocal();
    final records = {..._progress.questions};
    records[questionId] = _afterAttempt(
      _progress.forQuestion(questionId),
      correct: correct,
      occurredAt: now,
    );
    _progress = PracticeProgress(records);
    await _save();
  }

  Future<void> _save() => _preferences.setString(
    _key,
    jsonEncode({
      'version': 2,
      'questions': {
        for (final entry in _progress.questions.entries)
          entry.key: entry.value.toJson(),
      },
    }),
  );
}

QuestionProgress _mergeQuestionProgress(
  QuestionProgress local,
  QuestionProgress remote,
) {
  final lastCorrectAt = _latest(local.lastCorrectAt, remote.lastCorrectAt);
  final lastWrongAt = _latest(local.lastWrongAt, remote.lastWrongAt);
  final streakCandidates =
      [
          local.correctStreakStartedAt,
          remote.correctStreakStartedAt,
        ].whereType<DateTime>().where((date) {
          return lastWrongAt == null || date.isAfter(lastWrongAt);
        }).toList()
        ..sort();
  return _progressFromCounts(
    correctCount: local.correctCount > remote.correctCount
        ? local.correctCount
        : remote.correctCount,
    wrongCount: local.wrongCount > remote.wrongCount
        ? local.wrongCount
        : remote.wrongCount,
    lastCorrectAt: lastCorrectAt,
    lastWrongAt: lastWrongAt,
    correctStreakStartedAt: streakCandidates.firstOrNull,
  );
}

QuestionProgress _progressFromCounts({
  required int correctCount,
  required int wrongCount,
  required DateTime? lastCorrectAt,
  required DateTime? lastWrongAt,
  DateTime? correctStreakStartedAt,
}) {
  return QuestionProgress(
    correctCount: correctCount,
    wrongCount: wrongCount,
    lastCorrectAt: lastCorrectAt,
    lastWrongAt: lastWrongAt,
    correctStreakStartedAt: correctStreakStartedAt,
  );
}

DateTime? _latest(DateTime? first, DateTime? second) {
  if (first == null) return second;
  if (second == null) return first;
  return first.isAfter(second) ? first : second;
}

QuestionProgress _afterAttempt(
  QuestionProgress previous, {
  required bool correct,
  required DateTime occurredAt,
}) {
  final updatedCorrect = previous.correctCount + (correct ? 1 : 0);
  final updatedWrong = previous.wrongCount + (correct ? 0 : 1);
  final lastCorrect = correct ? occurredAt : previous.lastCorrectAt;
  final lastWrong = correct ? previous.lastWrongAt : occurredAt;
  final correctStreakStartedAt = _correctStreakStart(
    previous,
    correct: correct,
    occurredAt: occurredAt,
    lastCorrectAt: lastCorrect,
    lastWrongAt: lastWrong,
  );
  return QuestionProgress(
    correctCount: updatedCorrect,
    wrongCount: updatedWrong,
    lastCorrectAt: lastCorrect,
    lastWrongAt: lastWrong,
    correctStreakStartedAt: correctStreakStartedAt,
  );
}

DateTime? _correctStreakStart(
  QuestionProgress previous, {
  required bool correct,
  required DateTime occurredAt,
  required DateTime? lastCorrectAt,
  required DateTime? lastWrongAt,
}) {
  if (lastCorrectAt == null ||
      (lastWrongAt != null && !lastWrongAt.isBefore(lastCorrectAt))) {
    return null;
  }
  if (!correct) {
    // An older, out-of-order wrong record must not invalidate a newer success.
    return previous.correctStreakStartedAt;
  }
  if (previous.lastCorrectAt == null ||
      (previous.lastWrongAt != null &&
          !previous.lastWrongAt!.isBefore(previous.lastCorrectAt!))) {
    return occurredAt;
  }
  // Older local/remote formats only stored the latest success. It is safe to
  // use that success as the start when a new correct answer arrives.
  return previous.correctStreakStartedAt ?? previous.lastCorrectAt;
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

Set<String> _strings(Object? value) => value is List
    ? value.whereType<String>().where((item) => item.isNotEmpty).toSet()
    : {};
