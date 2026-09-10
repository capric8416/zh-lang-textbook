# Native speech engine

`libzh_speech` exposes one stable C ABI to Dart and contains:

- Piper (`zh_CN-xiao_ya-medium`) for numeric-pinyin TTS;
- FunASR Paraformer-large INT8 and FSMN-VAD for the experimental reading check;
- one statically linked ONNX Runtime shared by both engines.

The final platform library is dynamic (`.so`, `.dll`, `.dylib`) because Dart
loads it through FFI. Piper, FunASR, ONNX Runtime and their supporting native
libraries are static members of that one library. iOS instead force-loads a
single combined static archive into `Runner` and uses `DynamicLibrary.process`.

Pinned upstream revisions and licenses are recorded in `VERSIONS.md`. Piper is
GPL-3.0, so distributed applications containing this library must comply with
GPL-3.0, including the corresponding-source obligations. The Xiao Ya voice and
FunASR model licenses must also be shipped with release artifacts. Xiao Ya's
model card restricts its source dataset to non-commercial use.
