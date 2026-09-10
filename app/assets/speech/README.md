# Speech models

The release workflow populates this directory with the pinned offline models:

- `piper-zh_CN-xiao_ya-medium` for numeric-pinyin dictation audio;
- `funasr-paraformer-zh` for the experimental reading check;
- `funasr-fsmn-vad` for voice activity detection.

Run `scripts/download_speech_models.sh` before a local release build. The
downloaded model files are intentionally ignored by Git and are bundled into
the Flutter asset output. Model cards are copied beside the models so every
release retains the voice/model attribution and license information.

Xiao Ya was trained from the BZNSYP/DataBaker dataset, whose model card marks
the data for non-commercial use. Do not distribute this voice in a commercial
release without obtaining separate permission.
