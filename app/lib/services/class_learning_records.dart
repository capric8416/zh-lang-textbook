import 'account_api.dart';

class ClassLearningRecordsCursor {
  const ClassLearningRecordsCursor({
    required this.beforeTime,
    required this.afterId,
    required this.snapshotRowId,
  });

  final String beforeTime;
  final String afterId;
  final int snapshotRowId;

  Map<String, String> toQueryParameters() => {
    'beforeTime': beforeTime,
    'afterId': afterId,
    'snapshotRowId': '$snapshotRowId',
  };

  static ClassLearningRecordsCursor? fromJson(Object? value) {
    if (value is! Map) return null;
    final beforeTime = value['beforeTime'];
    final afterId = value['afterId'];
    final snapshotRowId = value['snapshotRowId'];
    final rowId = snapshotRowId is int
        ? snapshotRowId
        : snapshotRowId is num
        ? snapshotRowId.toInt()
        : null;
    if (beforeTime is! String ||
        afterId is! String ||
        beforeTime.isEmpty ||
        afterId.isEmpty ||
        rowId == null ||
        rowId <= 0) {
      return null;
    }
    return ClassLearningRecordsCursor(
      beforeTime: beforeTime,
      afterId: afterId,
      snapshotRowId: rowId,
    );
  }
}

class ClassLearningRecordPage {
  const ClassLearningRecordPage({required this.records, required this.cursor});

  final List<Map<String, dynamic>> records;
  final ClassLearningRecordsCursor? cursor;

  bool get hasMore => cursor != null;
}

class ClassLearningRecords {
  ClassLearningRecords._();

  static Future<ClassLearningRecordPage> fetchPage(
    AccountApi api,
    String classId, {
    ClassLearningRecordsCursor? cursor,
    required int limit,
  }) async {
    if (limit < 1 || limit > 500) throw ArgumentError('分页参数无效');
    final response = await api.request(
      'classes/$classId/records',
      queryParameters: {'limit': '$limit', ...?cursor?.toQueryParameters()},
    );
    final records = (response['records'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((record) => Map<String, dynamic>.from(record))
        .toList(growable: false);
    final next = response['nextCursor'];
    final nextCursor = next == null
        ? null
        : ClassLearningRecordsCursor.fromJson(next);
    if (next != null && nextCursor == null) {
      throw const FormatException('班级学习记录分页游标无效');
    }
    return ClassLearningRecordPage(records: records, cursor: nextCursor);
  }
}
