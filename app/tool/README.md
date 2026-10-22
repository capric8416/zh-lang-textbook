# Linux 本地数据清理

先关闭所有正在运行的 App 实例，在 `app/` 目录执行：

```bash
flutter run -d linux -t tool/clear_local_data.dart
```

清理指定测试目录下的 App 数据：

```bash
XDG_DATA_HOME="$PWD/.restore-test-s3uVbg" \
  flutter run -d linux -t tool/clear_local_data.dart
```

脚本直接执行删除，完成后自动退出。它使用 App 的原生插件和应用标识，不能通过 `dart run` 执行。

- 删除本 App 的 FlutterSecureStorage 数据，包括登录凭据。同一 Linux 用户的各个 App 实例共用这些凭据，不受 XDG_DATA_HOME 隔离。
- 删除 path_provider 实际使用的应用数据目录（`com.zhtextbook.app`，兼容旧目录 `app`），包括学习进度、宠物档案、偏好设置、作答记录及该目录内的模型文件。其他应用的数据和 XDG_DATA_HOME 根目录保留。
- 本地删除不可撤销，未同步数据也会删除；远端数据保留。脚本不清理 XDG_CACHE_HOME。

随后正常运行主入口即可重新登录并测试恢复：

```bash
XDG_DATA_HOME="$PWD/.restore-test-s3uVbg" \
  flutter run -d linux -t lib/main.dart \
  --dart-define=API_BASE_URL=https://zh-lang-textbook.614088.xyz/api/v1
```
