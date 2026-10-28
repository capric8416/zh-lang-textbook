# Speech models

The release workflow populates this directory with the pinned offline models:

- `piper-zh_CN-xiao_ya-medium` for numeric-pinyin dictation audio;
- `funasr-paraformer-zh` for the experimental reading check;
- `funasr-fsmn-vad` for voice activity detection.
- `snac-24khz` for compact original-reading audio (INT8 encoder and decoder).

Run `scripts/download_speech_models.sh` before a local release build. The
downloaded model files are intentionally ignored by Git and are bundled into
the Flutter asset output. In CI, set `SPEECH_MODEL_ARCHIVE_URL` to a release
archive (the project workflow uses the `models` release) to download all models
in one request; the SNAC models are fetched separately by checksum. Model cards are copied beside the models so every release
retains the voice/model attribution and license information.

The SNAC ONNX export is from `onnx-community/snac_24khz-ONNX` (MIT). Its
encoder and decoder SHA-256 values are pinned in the download script.

Xiao Ya was trained from the BZNSYP/DataBaker dataset, whose model card marks
the data for non-commercial use. Do not distribute this voice in a commercial
release without obtaining separate permission.
