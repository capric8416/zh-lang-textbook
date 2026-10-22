import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Run with the Linux Flutter runner so native plugins use the app's identity:
/// flutter run -d linux -t tool/clear_local_data.dart
/// Close all other instances of the app before running this tool.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isLinux) {
    stderr.writeln('此清理脚本仅支持 Linux。');
    exit(1);
  }

  try {
    final configuredRoot = Platform.environment['XDG_DATA_HOME'];
    final home = Platform.environment['HOME'];
    if ((configuredRoot == null || configuredRoot.isEmpty) &&
        (home == null || home.isEmpty)) {
      throw StateError('无法确定 XDG_DATA_HOME 或 HOME，停止清理。');
    }
    final root = Directory(
      configuredRoot == null || configuredRoot.isEmpty
          ? '$home/.local/share'
          : configuredRoot,
    );
    final support = await getApplicationSupportDirectory();
    final rootPath = await root.resolveSymbolicLinks();
    final supportPath = await support.resolveSymbolicLinks();
    // path_provider may use the old executable-name directory when it exists.
    // Require an exact app directory, never the XDG root or a symlink elsewhere.
    if (supportPath != '$rootPath/com.zhtextbook.app' &&
        supportPath != '$rootPath/app') {
      throw StateError('应用数据路径不符合预期，停止清理：$supportPath');
    }

    stdout.writeln('清理本 App 的安全存储和本地数据：$supportPath');
    await const FlutterSecureStorage().deleteAll();
    stdout.writeln('已清理 FlutterSecureStorage（同一系统用户的 App 实例共用）。');
    await Directory(supportPath).delete(recursive: true);
    stdout.writeln('已删除本地数据，无法撤销；远端数据未删除。');
    exit(0);
  } catch (error) {
    stderr.writeln('清理未完成：$error');
    exit(1);
  }
}
