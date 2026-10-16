import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zh_textbook/services/practice_record_sync.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'sync status is scoped to the account and reports saved details',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('pending_practice_records_v1', '''
      [
        {"id":"one","studentId":"student-a"},
        {"id":"two","studentId":"student-a"},
        {"id":"three","studentId":"student-b"}
      ]
      ''');
      await preferences.setString(
        'practice_record_sync_last_success_v1_student-a',
        '2026-10-16T10:30:00.000Z',
      );
      await preferences.setString(
        'practice_record_sync_last_error_v1_student-a',
        '网络暂时不可用',
      );

      final status = await PracticeRecordSync.statusFor('student-a');
      final otherStatus = await PracticeRecordSync.statusFor('student-b');

      expect(status.pendingCount, 2);
      expect(status.lastSuccessAt, DateTime.utc(2026, 10, 16, 10, 30));
      expect(status.lastError, '网络暂时不可用');
      expect(otherStatus.pendingCount, 1);
      expect(otherStatus.lastSuccessAt, isNull);
      expect(otherStatus.lastError, isNull);
    },
  );
}
