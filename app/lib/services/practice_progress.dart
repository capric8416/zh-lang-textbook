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
    this.blockedUntil,
    this.skipUntil,
    this.skipRemaining = 0,
  });

  factory QuestionProgress.fromJson(Map<String, dynamic> json) =>
      QuestionProgress(
        correctCount: json['correct_count'] is int
            ? json['correct_count'] as int
            : 0,
        wrongCount: json['wrong_count'] is int ? json['wrong_count'] as int : 0,
        lastCorrectAt: _date(json['last_correct_at']),
        lastWrongAt: _date(json['last_wrong_at']),
        blockedUntil: _date(json['blocked_until']),
        skipUntil: _date(json['skip_until']),
        skipRemaining: json['skip_remaining'] is int
            ? json['skip_remaining'] as int
            : 0,
      );

  final int correctCount;
  final int wrongCount;
  final DateTime? lastCorrectAt;
  final DateTime? lastWrongAt;
  final DateTime? blockedUntil;
  final DateTime? skipUntil;
  final int skipRemaining;

  int get totalCount => correctCount + wrongCount;

  /// A mistaken attempt remains in focused practice until it has been
  /// answered correctly more than three times for every wrong answer.
  bool get isWrong => wrongCount > 0 && correctCount <= wrongCount * 3;

  Map<String, dynamic> toJson() => {
    'correct_count': correctCount,
    'wrong_count': wrongCount,
    if (lastCorrectAt != null)
      'last_correct_at': lastCorrectAt!.toIso8601String(),
    if (lastWrongAt != null) 'last_wrong_at': lastWrongAt!.toIso8601String(),
    if (blockedUntil != null) 'blocked_until': blockedUntil!.toIso8601String(),
    if (skipUntil != null) 'skip_until': skipUntil!.toIso8601String(),
    if (skipRemaining > 0) 'skip_remaining': skipRemaining,
  };

  QuestionProgress copyWith({int? skipRemaining}) => QuestionProgress(
    correctCount: correctCount,
    wrongCount: wrongCount,
    lastCorrectAt: lastCorrectAt,
    lastWrongAt: lastWrongAt,
    blockedUntil: blockedUntil,
    skipUntil: skipUntil,
    skipRemaining: skipRemaining ?? this.skipRemaining,
  );
}

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
    final record = _progress.forQuestion(id);
    return record.blockedUntil?.isAfter(now) ?? false;
  }

  double weight(String id) {
    final record = _progress.forQuestion(id);
    if (record.totalCount == 0) return 8;
    return 1 + record.wrongCount * 5 / (record.correctCount + 1);
  }

  Future<bool> consumeSkip(String id, DateTime now) async {
    final record = _progress.forQuestion(id);
    if (record.skipRemaining <= 0 ||
        !(record.skipUntil?.isAfter(now) ?? false)) {
      return false;
    }
    final records = {..._progress.questions};
    records[id] = record.copyWith(skipRemaining: record.skipRemaining - 1);
    _progress = PracticeProgress(records);
    await _save();
    return true;
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

QuestionProgress _afterAttempt(
  QuestionProgress previous, {
  required bool correct,
  required DateTime occurredAt,
}) {
  final updatedCorrect = previous.correctCount + (correct ? 1 : 0);
  final updatedWrong = previous.wrongCount + (correct ? 0 : 1);
  final lastCorrect = correct ? occurredAt : previous.lastCorrectAt;
  final lastWrong = correct ? previous.lastWrongAt : occurredAt;
  final days = _dayDifference(lastCorrect, lastWrong);
  final times = updatedCorrect - updatedWrong;
  if (days > 0 || times < 0) {
    return QuestionProgress(
      correctCount: updatedCorrect,
      wrongCount: updatedWrong,
      lastCorrectAt: lastCorrect,
      lastWrongAt: lastWrong,
      blockedUntil: occurredAt.add(Duration(days: days.abs() + times.abs())),
    );
  }
  return QuestionProgress(
    correctCount: updatedCorrect,
    wrongCount: updatedWrong,
    lastCorrectAt: lastCorrect,
    lastWrongAt: lastWrong,
    skipUntil: occurredAt.add(Duration(days: days.abs())),
    skipRemaining: times.abs(),
  );
}

int _dayDifference(DateTime? correct, DateTime? wrong) {
  if (correct == null && wrong == null) return 0;
  if (correct != null && wrong == null) return 1;
  if (correct == null) return -1;
  final correctDay = DateTime(correct.year, correct.month, correct.day);
  final wrongDay = DateTime(wrong!.year, wrong.month, wrong.day);
  return correctDay.difference(wrongDay).inDays;
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

Set<String> _strings(Object? value) => value is List
    ? value.whereType<String>().where((item) => item.isNotEmpty).toSet()
    : {};
