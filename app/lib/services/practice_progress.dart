import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PracticeProgress {
  const PracticeProgress({required this.done, required this.wrong});

  final Set<String> done;
  final Set<String> wrong;

  bool isDone(String id) => done.contains(id);

  bool isWrong(String id) => wrong.contains(id);
}

class PracticeProgressStore {
  PracticeProgressStore._(this._preferences, this._key, this._progress);

  final SharedPreferences _preferences;
  final String _key;
  PracticeProgress _progress;

  PracticeProgress get progress => _progress;

  static Future<PracticeProgressStore> open(String textbookKey) async {
    final preferences = await SharedPreferences.getInstance();
    final key = 'practice_progress_$textbookKey';
    final raw = preferences.getString(key);
    try {
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PracticeProgressStore._(
          preferences,
          key,
          PracticeProgress(
            done: _stringSet(decoded['done']),
            wrong: _stringSet(decoded['wrong']),
          ),
        );
      }
    } on FormatException {
      // A corrupted local record should not block practice.
    }
    return PracticeProgressStore._(
      preferences,
      key,
      const PracticeProgress(done: {}, wrong: {}),
    );
  }

  Future<void> record(String questionId, {required bool correct}) async {
    final done = {..._progress.done, questionId};
    final wrong = {..._progress.wrong};
    if (correct) {
      wrong.remove(questionId);
    } else {
      wrong.add(questionId);
    }
    _progress = PracticeProgress(done: done, wrong: wrong);
    await _preferences.setString(
      _key,
      jsonEncode({
        'done': done.toList()..sort(),
        'wrong': wrong.toList()..sort(),
      }),
    );
  }
}

Set<String> _stringSet(Object? value) => value is List
    ? value.whereType<String>().where((item) => item.isNotEmpty).toSet()
    : {};
