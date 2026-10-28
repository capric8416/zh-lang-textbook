#include "speech_bridge.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <fstream>
#include <limits>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#endif

#include <onnxruntime_cxx_api.h>

namespace {
constexpr int64_t kRate = 24000;
constexpr int64_t kPad = 2048;  // 512 sample DAC hop * coarsest VQ stride 4
constexpr std::array<char, 8> kMagic{'S', 'N', 'A', 'C', 'L', 'B', '0', '1'};
constexpr int kMaxSeconds = 120;

struct SnacHandle {
  Ort::Env env{ORT_LOGGING_LEVEL_WARNING, "snac"};
  Ort::SessionOptions options;
  Ort::Session encoder{nullptr};
  Ort::Session decoder{nullptr};
  std::mutex mutex;

  SnacHandle(const char *encoder_path, const char *decoder_path) {
    options.SetIntraOpNumThreads(2);
    options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
#ifdef _WIN32
    const auto wide = [](const char *utf8) {
      const int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
      if (n == 0) throw std::runtime_error("invalid model path");
      std::wstring result(n, L'\0');
      MultiByteToWideChar(CP_UTF8, 0, utf8, -1, result.data(), n);
      return result;
    };
    encoder = Ort::Session(env, wide(encoder_path).c_str(), options);
    decoder = Ort::Session(env, wide(decoder_path).c_str(), options);
#else
    encoder = Ort::Session(env, encoder_path, options);
    decoder = Ort::Session(env, decoder_path, options);
#endif
  }
};

uint16_t u16(const uint8_t *p) {
  return static_cast<uint16_t>(p[0] | (p[1] << 8));
}
uint32_t u32(const uint8_t *p) {
  return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) |
         (static_cast<uint32_t>(p[3]) << 24);
}
uint64_t u64(const uint8_t *p) {
  return static_cast<uint64_t>(u32(p)) | (static_cast<uint64_t>(u32(p + 4)) << 32);
}
void put16(std::vector<uint8_t> &out, uint16_t v) {
  out.push_back(v & 255);
  out.push_back(v >> 8);
}
void put32(std::vector<uint8_t> &out, uint32_t v) {
  for (int i = 0; i < 4; ++i) out.push_back((v >> (8 * i)) & 255);
}
void put64(std::vector<uint8_t> &out, uint64_t v) {
  put32(out, static_cast<uint32_t>(v));
  put32(out, static_cast<uint32_t>(v >> 32));
}
uint32_t crc32(const uint8_t *data, size_t length) {
  uint32_t crc = 0xffffffffU;
  for (size_t i = 0; i < length; ++i) {
    crc ^= data[i];
    for (int bit = 0; bit < 8; ++bit)
      crc = (crc >> 1) ^ ((crc & 1) ? 0xedb88320U : 0U);
  }
  return ~crc;
}
std::vector<uint8_t> read_file(const char *path) {
  std::ifstream input(path, std::ios::binary | std::ios::ate);
  if (!input) throw std::runtime_error("file not found");
  const auto length = input.tellg();
  if (length <= 0 || length > 32 * 1024 * 1024)
    throw std::runtime_error("invalid file length");
  std::vector<uint8_t> bytes(static_cast<size_t>(length));
  input.seekg(0);
  if (!input.read(reinterpret_cast<char *>(bytes.data()), length))
    throw std::runtime_error("cannot read file");
  return bytes;
}
void write_file(const char *path, const std::vector<uint8_t> &bytes) {
  std::ofstream output(path, std::ios::binary | std::ios::trunc);
  if (!output || !output.write(reinterpret_cast<const char *>(bytes.data()), bytes.size()))
    throw std::runtime_error("cannot write file");
}

std::vector<float> read_wav_24k(const char *path) {
  const auto bytes = read_file(path);
  if (bytes.size() < 44 || std::memcmp(bytes.data(), "RIFF", 4) ||
      std::memcmp(bytes.data() + 8, "WAVE", 4))
    throw std::runtime_error("invalid WAV");
  uint16_t format = 0, channels = 0, depth = 0;
  uint32_t rate = 0;
  size_t data_offset = 0, data_size = 0;
  for (size_t offset = 12; offset + 8 <= bytes.size();) {
    const uint32_t size = u32(bytes.data() + offset + 4);
    const size_t start = offset + 8;
    if (size > bytes.size() - start) throw std::runtime_error("truncated WAV");
    if (!std::memcmp(bytes.data() + offset, "fmt ", 4) && size >= 16) {
      format = u16(bytes.data() + start);
      channels = u16(bytes.data() + start + 2);
      rate = u32(bytes.data() + start + 4);
      depth = u16(bytes.data() + start + 14);
    } else if (!std::memcmp(bytes.data() + offset, "data", 4)) {
      data_offset = start;
      data_size = size;
    }
    offset = start + size + (size & 1U);
  }
  if (format != 1 || channels != 1 || rate != kRate || depth != 16 ||
      data_size < 2 || data_size / 2 > kRate * kMaxSeconds)
    throw std::runtime_error("SNAC requires mono 24 kHz PCM16 WAV");
  std::vector<float> pcm(data_size / 2);
  for (size_t i = 0; i < pcm.size(); ++i)
    pcm[i] = static_cast<int16_t>(u16(bytes.data() + data_offset + i * 2)) / 32768.0f;
  return pcm;
}

std::vector<uint8_t> wav_bytes(const float *samples, size_t count) {
  if (count == 0 || count > static_cast<size_t>(kRate * kMaxSeconds))
    throw std::runtime_error("invalid decoded length");
  std::vector<uint8_t> out;
  out.reserve(44 + count * 2);
  out.insert(out.end(), {'R', 'I', 'F', 'F'});
  put32(out, static_cast<uint32_t>(36 + count * 2));
  out.insert(out.end(), {'W', 'A', 'V', 'E', 'f', 'm', 't', ' '});
  put32(out, 16); put16(out, 1); put16(out, 1);
  put32(out, kRate); put32(out, kRate * 2); put16(out, 2); put16(out, 16);
  out.insert(out.end(), {'d', 'a', 't', 'a'});
  put32(out, static_cast<uint32_t>(count * 2));
  for (size_t i = 0; i < count; ++i) {
    const auto clipped = std::clamp(samples[i], -1.0f, 1.0f);
    put16(out, static_cast<uint16_t>(static_cast<int16_t>(std::lrint(clipped * 32767.0f))));
  }
  return out;
}

void pack_level(std::vector<uint8_t> &out, const int64_t *values, size_t count) {
  put32(out, static_cast<uint32_t>(count));
  put32(out, static_cast<uint32_t>((count * 12 + 7) / 8));
  uint32_t bits = 0;
  int available = 0;
  for (size_t i = 0; i < count; ++i) {
    if (values[i] < 0 || values[i] >= 4096) throw std::runtime_error("invalid SNAC token");
    bits |= static_cast<uint32_t>(values[i]) << available;
    available += 12;
    while (available >= 8) {
      out.push_back(bits & 255);
      bits >>= 8;
      available -= 8;
    }
  }
  if (available) out.push_back(bits & 255);
}

std::array<std::vector<int64_t>, 3> unpack(const std::vector<uint8_t> &data,
                                            uint64_t &sample_count) {
  if (data.size() < 32 || std::memcmp(data.data(), kMagic.data(), 8) ||
      u16(data.data() + 8) != 1 || u16(data.data() + 10) != 3 ||
      u32(data.data() + 12) != kRate || u32(data.data() + 16) != 4096 ||
      u32(data.data() + data.size() - 4) != crc32(data.data(), data.size() - 4))
    throw std::runtime_error("invalid SNAC container");
  sample_count = u64(data.data() + 20);
  if (sample_count == 0 || sample_count > kRate * kMaxSeconds)
    throw std::runtime_error("invalid sample count");
  size_t offset = 28;
  std::array<std::vector<int64_t>, 3> levels;
  for (auto &level : levels) {
    if (offset + 8 > data.size() - 4) throw std::runtime_error("truncated SNAC");
    const size_t count = u32(data.data() + offset);
    const size_t length = u32(data.data() + offset + 4);
    offset += 8;
    if (count == 0 || count > kRate * kMaxSeconds / 128 ||
        length != (count * 12 + 7) / 8 || length > data.size() - 4 - offset)
      throw std::runtime_error("invalid token length");
    level.reserve(count);
    uint32_t bits = 0;
    int available = 0;
    size_t pos = offset;
    for (size_t i = 0; i < count; ++i) {
      while (available < 12) {
        bits |= static_cast<uint32_t>(data[pos++]) << available;
        available += 8;
      }
      level.push_back(bits & 4095);
      bits >>= 12;
      available -= 12;
    }
    offset += length;
  }
  if (offset != data.size() - 4) throw std::runtime_error("trailing SNAC data");
  return levels;
}
}  // namespace

void *zh_speech_snac_create(const char *encoder_path, const char *decoder_path) {
  if (!encoder_path || !decoder_path) return nullptr;
  try { return new SnacHandle(encoder_path, decoder_path); }
  catch (const std::exception& error) {
    std::fprintf(stderr, "SNAC model load failed: %s\n", error.what());
    return nullptr;
  }
}
void zh_speech_snac_destroy(void *handle) { delete static_cast<SnacHandle *>(handle); }

int32_t zh_speech_snac_encode_wav(void *handle, const char *wav_path,
                                  const char *output_path) {
  if (!handle || !wav_path || !output_path) return -1;
  try {
    auto &codec = *static_cast<SnacHandle *>(handle);
    std::lock_guard<std::mutex> lock(codec.mutex);
    auto samples = read_wav_24k(wav_path);
    const auto original_count = samples.size();
    samples.resize(((samples.size() + kPad - 1) / kPad) * kPad, 0.0f);
    std::array<int64_t, 3> shape{1, 1, static_cast<int64_t>(samples.size())};
    auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    auto input = Ort::Value::CreateTensor<float>(memory, samples.data(), samples.size(),
                                                  shape.data(), shape.size());
    const char *input_names[] = {"input_values"};
    const char *output_names[] = {"audio_codes.0", "audio_codes.1", "audio_codes.2"};
    auto outputs = codec.encoder.Run(Ort::RunOptions{nullptr}, input_names, &input, 1,
                                     output_names, 3);
    std::vector<uint8_t> out(kMagic.begin(), kMagic.end());
    put16(out, 1); put16(out, 3); put32(out, kRate); put32(out, 4096);
    put64(out, original_count);
    for (const auto &tensor : outputs) {
      const auto info = tensor.GetTensorTypeAndShapeInfo();
      if (info.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64)
        throw std::runtime_error("wrong encoder output type");
      pack_level(out, tensor.GetTensorData<int64_t>(), info.GetElementCount());
    }
    put32(out, crc32(out.data(), out.size()));
    write_file(output_path, out);
    return 0;
  } catch (const std::exception& error) {
    std::fprintf(stderr, "SNAC encode failed: %s\n", error.what());
    return -2;
  }
}

int32_t zh_speech_snac_decode_wav(void *handle, const char *snac_path,
                                  const char *output_path) {
  if (!handle || !snac_path || !output_path) return -1;
  try {
    auto &codec = *static_cast<SnacHandle *>(handle);
    std::lock_guard<std::mutex> lock(codec.mutex);
    uint64_t count = 0;
    auto levels = unpack(read_file(snac_path), count);
    auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    std::array<std::array<int64_t, 2>, 3> shapes{};
    std::vector<Ort::Value> inputs;
    for (size_t i = 0; i < 3; ++i) {
      shapes[i] = {1, static_cast<int64_t>(levels[i].size())};
      inputs.push_back(Ort::Value::CreateTensor<int64_t>(
          memory, levels[i].data(), levels[i].size(), shapes[i].data(), 2));
    }
    const char *input_names[] = {"audio_codes.0", "audio_codes.1", "audio_codes.2"};
    const char *output_names[] = {"audio_values"};
    auto outputs = codec.decoder.Run(Ort::RunOptions{nullptr}, input_names,
                                     inputs.data(), 3, output_names, 1);
    const auto info = outputs[0].GetTensorTypeAndShapeInfo();
    if (info.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT ||
        info.GetElementCount() < count)
      throw std::runtime_error("wrong decoder output");
    write_file(output_path, wav_bytes(outputs[0].GetTensorData<float>(), count));
    return 0;
  } catch (const std::exception& error) {
    std::fprintf(stderr, "SNAC decode failed: %s\n", error.what());
    return -2;
  }
}
