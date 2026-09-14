# Native OCR builds

The Flutter application loads a small C ABI bridge around PP-OCRv6. OpenCV
4.11.0 and ncnn 20241226 are built from source as static libraries, then linked
into the platform OCR binary.

Linux and Android are built in the same Ubuntu 20.04 CI container. This keeps
the Linux desktop bundle at glibc 2.31 instead of inheriting a newer hosted
runner userspace.

Generated source trees, build directories, and installed native dependencies
live under `.build-deps/`, `build-*`, and `vendor/`. They are intentionally
ignored by Git.

## Unix-like platforms

Run from the `app` directory:

```sh
uv run python -m zh_native_build ocrdeps --target linux-x64
uv run python -m zh_native_build ocrdeps --target android-arm64-v8a
uv run python -m zh_native_build ocrdeps --target macos-x86_64 # or macos-arm64
uv run python -m zh_native_build ocrdeps --target ios-arm64
```

Android requires `ANDROID_NDK_HOME`. The CI build uses NDK 28.2.13676358 and
produces an arm64 APK. iOS produces an unsigned device application; signing is
left to the distributor.

## Windows

From a Visual Studio 2022 PowerShell environment:

```powershell
uv run python -m zh_native_build ocrdeps --target windows-x64
```

The Flutter Linux and Windows CMake projects build and bundle the OCR shared
library. Android packages it through Gradle externalNativeBuild. The release
workflow builds the macOS dynamic library before inserting it into the app
bundle, and combines all iOS static archives into the library force-loaded by
Runner.
