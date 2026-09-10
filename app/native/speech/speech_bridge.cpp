#include "speech_bridge.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include <piper.h>
#include <funasrruntime.h>

namespace {

struct TtsHandle {
  piper_synthesizer *synth = nullptr;
  std::mutex mutex;
  ~TtsHandle() { piper_free(synth); }
};

struct AsrHandle {
  FUNASR_HANDLE asr = nullptr;
  FUNASR_HANDLE vad = nullptr;
  std::mutex mutex;
  ~AsrHandle() {
    if (vad != nullptr) FsmnVadUninit(vad);
    if (asr != nullptr) FunASRUninit(asr);
  }
};

void write_u16(std::ofstream &out, uint16_t value) {
  const char bytes[] = {static_cast<char>(value),
                        static_cast<char>(value >> 8)};
  out.write(bytes, sizeof(bytes));
}

void write_u32(std::ofstream &out, uint32_t value) {
  const char bytes[] = {
      static_cast<char>(value), static_cast<char>(value >> 8),
      static_cast<char>(value >> 16), static_cast<char>(value >> 24)};
  out.write(bytes, sizeof(bytes));
}

uint16_t read_u16(const unsigned char *bytes) {
  return static_cast<uint16_t>(bytes[0]) |
         (static_cast<uint16_t>(bytes[1]) << 8);
}

uint32_t read_u32(const unsigned char *bytes) {
  return static_cast<uint32_t>(bytes[0]) |
         (static_cast<uint32_t>(bytes[1]) << 8) |
         (static_cast<uint32_t>(bytes[2]) << 16) |
         (static_cast<uint32_t>(bytes[3]) << 24);
}

bool has_audible_pcm16(const char *path) {
  std::ifstream input(path, std::ios::binary);
  unsigned char riff[12]{};
  if (!input.read(reinterpret_cast<char *>(riff), sizeof(riff)) ||
      std::memcmp(riff, "RIFF", 4) != 0 ||
      std::memcmp(riff + 8, "WAVE", 4) != 0) {
    return false;
  }

  uint16_t format = 0;
  uint16_t channels = 0;
  uint16_t bits_per_sample = 0;
  uint32_t sample_rate = 0;
  std::vector<unsigned char> audio;
  while (input) {
    unsigned char chunk[8]{};
    if (!input.read(reinterpret_cast<char *>(chunk), sizeof(chunk))) break;
    const uint32_t size = read_u32(chunk + 4);
    if (std::memcmp(chunk, "fmt ", 4) == 0 && size >= 16) {
      std::vector<unsigned char> contents(size);
      if (!input.read(reinterpret_cast<char *>(contents.data()), size))
        return false;
      format = read_u16(contents.data());
      channels = read_u16(contents.data() + 2);
      sample_rate = read_u32(contents.data() + 4);
      bits_per_sample = read_u16(contents.data() + 14);
    } else if (std::memcmp(chunk, "data", 4) == 0) {
      audio.resize(size);
      if (!input.read(reinterpret_cast<char *>(audio.data()), size))
        return false;
    } else {
      input.seekg(size, std::ios::cur);
    }
    if ((size & 1U) != 0) input.seekg(1, std::ios::cur);
  }

  if (format != 1 || channels == 0 || bits_per_sample != 16 ||
      sample_rate == 0 || audio.size() < sample_rate / 5 * channels * 2) {
    return false;
  }
  double energy = 0.0;
  int peak = 0;
  const size_t sample_count = audio.size() / 2;
  for (size_t i = 0; i < sample_count; ++i) {
    const int16_t sample = static_cast<int16_t>(read_u16(audio.data() + i * 2));
    const int magnitude = std::abs(static_cast<int>(sample));
    peak = std::max(peak, magnitude);
    energy += static_cast<double>(sample) * sample;
  }
  const double rms = std::sqrt(energy / sample_count);
  return peak >= 256 && rms >= 64.0;
}

bool write_wav(const char *path, const std::vector<float> &samples,
               int sample_rate) {
  if (path == nullptr || samples.empty() || sample_rate <= 0) return false;
  std::ofstream out(path, std::ios::binary);
  if (!out) return false;
  const uint32_t data_size = static_cast<uint32_t>(samples.size() * 2);
  out.write("RIFF", 4);
  write_u32(out, 36 + data_size);
  out.write("WAVEfmt ", 8);
  write_u32(out, 16);
  write_u16(out, 1);
  write_u16(out, 1);
  write_u32(out, static_cast<uint32_t>(sample_rate));
  write_u32(out, static_cast<uint32_t>(sample_rate * 2));
  write_u16(out, 2);
  write_u16(out, 16);
  out.write("data", 4);
  write_u32(out, data_size);
  for (float sample : samples) {
    const float clipped = std::max(-1.0f, std::min(1.0f, sample));
    const auto pcm = static_cast<int16_t>(std::lrint(clipped * 32767.0f));
    write_u16(out, static_cast<uint16_t>(pcm));
  }
  return out.good();
}

}  // namespace

void *zh_speech_tts_create(const char *model_path, const char *config_path) {
  if (model_path == nullptr || config_path == nullptr) return nullptr;
  try {
    auto handle = std::make_unique<TtsHandle>();
    piper_create_options options;
    piper_init_create_options(&options);
    options.model_path = model_path;
    options.config_path = config_path;
    // Numeric pinyin does not need espeak-ng or a Hanzi pronunciation model.
    handle->synth = piper_create_with_options(&options);
    return handle->synth == nullptr ? nullptr : handle.release();
  } catch (...) {
    return nullptr;
  }
}

void zh_speech_tts_destroy(void *handle) {
  delete static_cast<TtsHandle *>(handle);
}

int32_t zh_speech_tts_synthesize_wav(
    void *handle, const char *numeric_pinyin, const char *output_path,
    float length_scale, int32_t repeat) {
  if (handle == nullptr || numeric_pinyin == nullptr || output_path == nullptr)
    return -1;
  try {
    auto *tts = static_cast<TtsHandle *>(handle);
    std::lock_guard<std::mutex> lock(tts->mutex);
    auto options = piper_default_synthesize_options(tts->synth);
    options.length_scale = length_scale > 0 ? length_scale : 1.0f;
    if (piper_synthesize_start(tts->synth, numeric_pinyin, &options) < 0)
      return -2;

    std::vector<float> utterance;
    int sample_rate = 0;
    for (;;) {
      piper_audio_chunk chunk{};
      const int status = piper_synthesize_next(tts->synth, &chunk);
      if (status < 0) return -3;
      sample_rate = chunk.sample_rate;
      if (chunk.samples != nullptr && chunk.num_samples > 0) {
        utterance.insert(utterance.end(), chunk.samples,
                         chunk.samples + chunk.num_samples);
      }
      if (status == PIPER_DONE || chunk.is_last) break;
    }
    if (utterance.empty() || sample_rate <= 0) return -4;

    const int repetitions = std::max(1, repeat);
    const size_t leading = static_cast<size_t>(sample_rate * 0.15);
    const size_t pause = static_cast<size_t>(sample_rate * 0.5);
    const size_t trailing = static_cast<size_t>(sample_rate * 0.2);
    std::vector<float> output(leading, 0.0f);
    for (int i = 0; i < repetitions; ++i) {
      output.insert(output.end(), utterance.begin(), utterance.end());
      if (i + 1 < repetitions) output.insert(output.end(), pause, 0.0f);
    }
    output.insert(output.end(), trailing, 0.0f);
    return write_wav(output_path, output, sample_rate) ? 0 : -5;
  } catch (...) {
    return -6;
  }
}

void *zh_speech_asr_create(const char *paraformer_model_dir,
                           const char *vad_model_dir) {
  if (paraformer_model_dir == nullptr || vad_model_dir == nullptr)
    return nullptr;
  try {
    auto handle = std::make_unique<AsrHandle>();
    std::map<std::string, std::string> asr_paths{
        {"model-dir", paraformer_model_dir}, {"quantize", "true"}};
    std::map<std::string, std::string> vad_paths{
        {"model-dir", vad_model_dir}, {"quantize", "true"}};
    handle->asr = FunASRInit(asr_paths, 2, ASR_OFFLINE);
    handle->vad = FsmnVadInit(vad_paths, 1);
    return handle->asr == nullptr || handle->vad == nullptr ? nullptr
                                                            : handle.release();
  } catch (...) {
    return nullptr;
  }
}

void zh_speech_asr_destroy(void *handle) {
  delete static_cast<AsrHandle *>(handle);
}

int32_t zh_speech_asr_recognize_wav(void *handle, const char *wav_path,
                                    char *output, int32_t output_capacity) {
  if (handle == nullptr || wav_path == nullptr || output == nullptr ||
      output_capacity <= 0)
    return -1;
  try {
    auto *speech = static_cast<AsrHandle *>(handle);
    std::lock_guard<std::mutex> lock(speech->mutex);
    if (!has_audible_pcm16(wav_path)) return -3;
    FUNASR_RESULT vad_result = FsmnVadInfer(speech->vad, wav_path, nullptr);
    if (vad_result == nullptr) return -2;
    const auto *segments = FsmnVadGetResult(vad_result, 0);
    const bool has_speech = segments != nullptr && !segments->empty();
    FsmnVadFreeResult(vad_result);
    if (!has_speech) return -3;

    FUNASR_RESULT result =
        FunASRInfer(speech->asr, wav_path, RASRM_CTC_GREEDY_SEARCH, nullptr);
    if (result == nullptr) return -4;
    const char *recognized = FunASRGetResult(result, 0);
    const std::string text = recognized == nullptr ? "" : recognized;
    FunASRFreeResult(result);
    const auto length = static_cast<int32_t>(text.size());
    if (length + 1 > output_capacity) return length;
    std::memcpy(output, text.data(), text.size());
    output[length] = '\0';
    return length;
  } catch (...) {
    return -5;
  }
}
