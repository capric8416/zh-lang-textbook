import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zh_textbook/services/textbook_repository.dart';
import 'package:zh_textbook/services/account_api.dart';
import 'package:zh_textbook/services/textbook_preference.dart';

class PreferenceApi extends AccountApi {
  Map<String, Object?>? selection;
  bool offline = false;
  Completer<void>? gate;
  @override
  bool get configured => true;
  @override
  Future<String?> get accountId async => 'student-a';
  @override
  Future<String?> get token async => 'token';
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    Map<String, String>? queryParameters,
    bool authenticated = true,
    String? tokenOverride,
  }) async {
    expect(path, 'me/textbook-preference');
    if (offline) throw const AccountApiException('offline');
    if (gate != null) await gate!.future;
    if (method == 'PUT') selection = body;
    return {'selection': selection};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'fresh device restores selection without leaking to another account',
    () async {
      final api = PreferenceApi()..selection = {'grade': 3, 'semester': 'b'};
      await TextbookPreference.synchronize(api);
      final saved = await TextbookPreference.load('student-a');
      expect(saved?.grade, 3);
      expect(saved?.semester, Semester.second);
      expect(await TextbookPreference.load('student-b'), isNull);
    },
  );

  test('offline choice survives failure and uploads on retry', () async {
    final api = PreferenceApi()..offline = true;
    await TextbookPreference.save(
      'student-a',
      const TextbookSelection(grade: 5, semester: Semester.first),
    );
    await expectLater(
      TextbookPreference.synchronize(api),
      throwsA(isA<AccountApiException>()),
    );
    expect((await TextbookPreference.load('student-a'))?.grade, 5);
    api.offline = false;
    await TextbookPreference.synchronize(api);
    expect(api.selection, {'grade': 5, 'semester': 'a'});
    api.selection = {'grade': 6, 'semester': 'b'};
    await TextbookPreference.synchronize(api);
    expect((await TextbookPreference.load('student-a'))?.grade, 6);
  });
}
