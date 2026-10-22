import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'textbook_repository.dart';
import 'account_api.dart';

class TextbookPreference {
  static String _key(String accountId) => 'textbook_selection_v1_$accountId';
  static Future<void> _tail = Future<void>.value();

  static TextbookSelection? _decode(String? value) {
    if (value == null) return null;
    try {
      final data = jsonDecode(value) as Map;
      final grade = data['grade'];
      final semester = switch (data['semester']) {
        'a' => Semester.first,
        'b' => Semester.second,
        _ => null,
      };
      if (grade is! int || grade < 1 || grade > 6 || semester == null) {
        return null;
      }
      return TextbookSelection(grade: grade, semester: semester);
    } catch (_) {
      return null;
    }
  }

  static Future<TextbookSelection?> load(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_key(accountId)));
  }

  static Future<void> save(
    String accountId,
    TextbookSelection selection,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(accountId),
      jsonEncode({
        'grade': selection.grade,
        'semester': selection.semester.code,
        'dirty': true,
      }),
    );
  }

  static Future<void> synchronize(AccountApi api) {
    final operation = _tail.then((_) => _synchronize(api));
    _tail = operation.catchError((_) {});
    return operation;
  }

  static Future<void> _synchronize(AccountApi api) async {
    final accountId = await api.accountId;
    final token = await api.token;
    if (!api.configured || accountId == null || token == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _key(accountId);
    final before = prefs.getString(key);
    final local = _decode(before);
    final dirty =
        local != null && (jsonDecode(before!) as Map)['dirty'] == true;
    final response = await api
        .request(
          'me/textbook-preference',
          method: dirty ? 'PUT' : 'GET',
          tokenOverride: token,
          body: dirty
              ? {'grade': local.grade, 'semester': local.semester.code}
              : null,
        )
        .timeout(const Duration(seconds: 15));
    if (await api.accountId != accountId || prefs.getString(key) != before) {
      return;
    }
    final selection = _decode(jsonEncode(response['selection']));
    if (selection == null) return;
    await prefs.setString(
      key,
      jsonEncode({
        'grade': selection.grade,
        'semester': selection.semester.code,
        'dirty': false,
      }),
    );
  }
}
