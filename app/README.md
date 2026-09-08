# 语文巩固

面向 Linux、Windows、macOS、Android 和 iOS 的 Flutter 语文复习应用。

## 同步教材

教材源文件位于仓库根目录的 `json_reviewed/`。每次打包前，在本目录执行：

```bash
dart run tool/sync_textbooks.dart
```

脚本会递归读取 `../json_reviewed` 中的全部 JSON，并按文件名复制到
`assets/json_reviewed/`。如果不同目录中存在同名 JSON，脚本会停止，避免静默覆盖。

应用根据年级和学期生成教材文件名：

```text
zh-lang-grade{grade}{a|b}-textbook-struct.json
```

例如二年级下学期对应：

```text
assets/json_reviewed/zh-lang-grade2b-textbook-struct.json
```

## 开发

```bash
flutter pub get
dart run tool/sync_textbooks.dart
flutter analyze
flutter test
flutter run -d linux
```

Windows 应用需在 Windows 上构建；macOS 和 iOS 应用需在 macOS 上构建。
