# Pinned components

- Piper: `OHF-Voice/piper1-gpl` commit
  `404aefedbd74baa0bd43e451bc407a2b3aace0f5` (GPL-3.0)
- FunASR: `modelscope/FunASR` commit
  `231ec5dda739c83f35e59e875736cde3ef1af161` (MIT)
- ONNX Runtime: `v1.22.0` (MIT)
- Piper voice: `zh_CN-xiao_ya-medium` (non-commercial dataset; see the bundled
  `MODEL_CARD`)
- ASR: `funasr/Paraformer-large`, quantized ONNX (Apache-2.0)
- VAD: `funasr/fsmn-vad-onnx` (model license is bundled with the model)

The dependency build scripts consume only these revisions. Updating any entry
requires rebuilding every target archive and checking the licenses again.
