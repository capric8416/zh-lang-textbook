import 'dart:io';

void main() {
  final source = Directory('../json_reviewed');
  final destination = Directory('assets/json_reviewed');

  if (!source.existsSync()) {
    stderr.writeln('找不到数据目录：${source.path}');
    exitCode = 1;
    return;
  }

  destination.createSync(recursive: true);

  final jsonFiles =
      source
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final names = <String, String>{};
  for (final file in jsonFiles) {
    final name = file.uri.pathSegments.last;
    final previous = names[name];
    if (previous != null) {
      stderr.writeln('发现同名 JSON，无法扁平化复制：$previous 与 ${file.path}');
      exitCode = 1;
      return;
    }
    names[name] = file.path;
  }

  for (final oldAsset
      in destination
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.json'))) {
    oldAsset.deleteSync();
  }

  for (final entry in names.entries) {
    File(entry.value).copySync('${destination.path}/${entry.key}');
  }

  stdout.writeln('已同步 ${names.length} 个 JSON 到 ${destination.path}');
}
