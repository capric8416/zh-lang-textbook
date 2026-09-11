#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd "$script_dir/.." && pwd)"
asset_dir="$app_dir/assets/speech"
cache_dir="${SPEECH_MODEL_CACHE:-$app_dir/.dart_tool/speech-models-v2}"
tts_dir="$asset_dir/piper-zh_CN-xiao_ya-medium"
asr_dir="$asset_dir/funasr-paraformer-zh"
vad_dir="$asset_dir/funasr-fsmn-vad"

mkdir -p "$cache_dir" "$tts_dir" "$asr_dir" "$vad_dir"

fetch() {
  local url="$1" sha256="$2" target="$3"
  local cached="$cache_dir/$sha256"
  if [[ ! -f "$cached" ]] || ! echo "$sha256  $cached" | sha256sum -c - >/dev/null 2>&1; then
    rm -f "$cached"
    local attempt seed delay
    for attempt in 1 2 3 4 5 6; do
      seed="$(date +%s%N 2>/dev/null || true)"
      if [[ "$seed" == *N* || -z "$seed" ]]; then
        seed="$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000000' 2>/dev/null || date +%s)"
      fi
      if [[ ! "$seed" =~ ^[0-9]+$ ]]; then
        seed="$(date +%s)"
      fi
      delay=$((seed % 8 + 3))
      sleep "$delay"
      if curl --fail --location "$url" --output "$cached"; then
        break
      fi
      rm -f "$cached"
      if [[ "$attempt" -eq 6 ]]; then
        echo "Failed to download $url after $attempt attempts" >&2
        return 1
      fi
      sleep $((attempt * 15))
    done
    echo "$sha256  $cached" | sha256sum -c -
  fi
  cp "$cached" "$target"
}

piper_root="https://huggingface.co/rhasspy/piper-voices/resolve/main/zh/zh_CN/xiao_ya/medium"
fetch "$piper_root/zh_CN-xiao_ya-medium.onnx" \
  cb2ce4ca1f5a36a7b23ae48f0651ce2c854c331ef7a804e5c5dc643d0f74f0e2 \
  "$tts_dir/model.onnx"
fetch "$piper_root/zh_CN-xiao_ya-medium.onnx.json" \
  e1ec027b7065959643c1463705398d413ed4fdaa626d7d8ef1d12ab87e9a0320 "$tts_dir/model.onnx.json"
fetch "$piper_root/MODEL_CARD" \
  5720e170d3872dcea10803c77a4a6b4424a9af366431fdc5668adafd95e33f42 "$tts_dir/MODEL_CARD"

asr_root="https://modelscope.cn/models/iic/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-onnx/resolve/master"
fetch "$asr_root/model_quant.onnx" \
  c3a06538f867c8e3d9bb9c9e1b44b126a50d732862f6c428b1b5896ee9be65c5 \
  "$asr_dir/model_quant.onnx"
fetch "$asr_root/am.mvn" \
  29b3c740a2c0cfc6b308126d31d7f265fa2be74f3bb095cd2f143ea970896ae5 \
  "$asr_dir/am.mvn"
fetch "$asr_root/config.yaml" \
  bfd424b9f61846aac63591e96fe24d66b35f4643bddcb4b9bb759db8f987ab79 \
  "$asr_dir/config.yaml"
fetch "$asr_root/tokens.json" \
  2b20c2b12572d682afff84ce1c8d560f67b8b32a4c1f21567411d141ed352127 \
  "$asr_dir/tokens.json"
fetch "$asr_root/README.md" \
  1ab1f3225e04ba4b731c819a15d498825e52cd13aac80f5d457d4d7e37aab76f \
  "$asr_dir/MODEL_CARD.md"

vad_root="https://huggingface.co/funasr/fsmn-vad-onnx/resolve/main"
fetch "$vad_root/model_quant.onnx" \
  9b28837838fce9685503c63139fadbad35d6c8ed485485dafdbb32e725969660 \
  "$vad_dir/model_quant.onnx"
fetch "$vad_root/vad.mvn" \
  6820fef9687708c4fc3fab2530179c8fcea6262daa25514380056cd8f6eb1754 "$vad_dir/am.mvn"
fetch "$vad_root/vad.yaml" \
  db524c680b80b0ea0a617110f6a269019da9fe4db1c38500f7552aeb6fad08b4 "$vad_dir/config.yaml"
# The pinned FunASR C++ runtime reads this section as model_conf. The model
# repository calls the same settings vad_post_conf.
sed -i.bak 's/^vad_post_conf:/model_conf:/' "$vad_dir/config.yaml"
rm -f "$vad_dir/config.yaml.bak"
fetch "$vad_root/README.md" \
  59ad5ed1e004a8a2b431ad4d86715f0093dee023ff7018073d3c261f60ec0e1e "$vad_dir/MODEL_CARD.md"

test -s "$tts_dir/model.onnx"
test -s "$asr_dir/model_quant.onnx"
test -s "$asr_dir/tokens.json"
test -s "$vad_dir/model_quant.onnx"
