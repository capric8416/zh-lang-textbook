import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Append-only local journal. Each answer is preserved independently, rather
/// than attempting to reconstruct attempts from aggregate progress counters.
class PracticeAttemptStore {
  PracticeAttemptStore._();

  static final Map<String, Future<void>> _writeTails = {};

  static Future<void> append(
    String namespace,
    Map<String, Object?> record,
  ) async {
    final previous = _writeTails[namespace] ?? Future<void>.value();
    final next = previous.then((_) async {
      final file = await _file(namespace);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
        flush: true,
      );
    });
    _writeTails[namespace] = next;
    try {
      await next;
    } finally {
      if (identical(_writeTails[namespace], next)) {
        _writeTails.remove(namespace);
      }
    }
  }

  static Future<List<Map<String, Object?>>> read(String namespace) async {
    final file = await _file(namespace);
    if (!await file.exists()) return [];
    final records = <Map<String, Object?>>[];
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          records.add(decoded.cast<String, Object?>());
        }
      } on FormatException {
        // A partial or corrupt line does not hide later completed attempts.
      }
    }
    return records;
  }

  static Future<File> _file(String namespace) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/practice_attempts');
    final safeName = base64Url
        .encode(utf8.encode(namespace))
        .replaceAll('=', '');
    return File('${directory.path}/$safeName.jsonl');
  }
}
