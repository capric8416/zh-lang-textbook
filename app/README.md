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

## 全量清理并重建

原生依赖由仓库根目录的 Python adapter 管理。清理命令只删除指定目标的
编译输出、vendor 归档和 Flutter 生成物，默认保留源码 checkout 与语音模型缓存：

```bash
cd ..
TARGET=android-arm64-v8a mise run clean
TARGET=android-arm64-v8a mise run native
```

可用 `MODULE=speech`、`MODULE=ocr` 或 `MODULE=flutter` 只清理一个模块；
需要连依赖源码一起删除时，直接调用：

```bash
uv run python -m zh_native_build clean \
  --target linux-x64 --module all --purge-sources
```

清理脚本覆盖 Linux、Windows、macOS、Android 和 iOS adapter 的目标目录，
不会删除 `.dart_tool/speech-models-v2` 中已下载的语音模型。
