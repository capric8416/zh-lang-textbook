#include "tts_compare.h"

#include <piper.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

struct Arguments {
  std::string model;
  std::string config;
  std::string g2pw_dir;
  std::string output;
  std::string text;
  float length_scale = 1.0F;
};

struct PiperDeleter {
  void operator()(piper_synthesizer *value) const { piper_free(value); }
};

using PiperPtr = std::unique_ptr<piper_synthesizer, PiperDeleter>;

void print_usage(const char *program, InputMode mode) {
  std::cerr
      << "Usage: " << program
      << " --model MODEL.onnx [--config MODEL.onnx.json]"
      << (mode == InputMode::Hanzi ? " --g2pw-dir DIR" : "")
      << " --output OUTPUT.wav [--length-scale 1.0] [--text TEXT]\n"
      << "If --text is omitted, UTF-8 text is read from standard input.\n";
}

std::string require_value(int argc, char **argv, int &index) {
  if (++index >= argc) {
    throw std::runtime_error(std::string("Missing value after ") +
                             argv[index - 1]);
  }
  return argv[index];
}

Arguments parse_arguments(int argc, char **argv, InputMode mode) {
  Arguments args;
  for (int index = 1; index < argc; ++index) {
    const std::string option = argv[index];
    if (option == "--model") {
      args.model = require_value(argc, argv, index);
    } else if (option == "--config") {
      args.config = require_value(argc, argv, index);
    } else if (option == "--g2pw-dir" && mode == InputMode::Hanzi) {
      args.g2pw_dir = require_value(argc, argv, index);
    } else if (option == "--output") {
      args.output = require_value(argc, argv, index);
    } else if (option == "--length-scale") {
      args.length_scale = std::stof(require_value(argc, argv, index));
    } else if (option == "--text") {
      args.text = require_value(argc, argv, index);
    } else if (option == "--help" || option == "-h") {
      print_usage(argv[0], mode);
      return {};
    } else {
      throw std::runtime_error("Unknown argument: " + option);
    }
  }

  if (args.model.empty()) throw std::runtime_error("--model is required");
  if (args.config.empty()) args.config = args.model + ".json";
  if (args.output.empty()) throw std::runtime_error("--output is required");
  if (args.length_scale <= 0) {
    throw std::runtime_error("--length-scale must be greater than zero");
  }
  if (mode == InputMode::Hanzi && args.g2pw_dir.empty()) {
    throw std::runtime_error("--g2pw-dir is required for Hanzi input");
  }
  if (args.text.empty()) {
    std::ostringstream input;
    input << std::cin.rdbuf();
    args.text = input.str();
    while (!args.text.empty() &&
           (args.text.back() == '\n' || args.text.back() == '\r')) {
      args.text.pop_back();
    }
  }
  if (args.text.empty()) throw std::runtime_error("Input text is empty");
  return args;
}

void require_file(const std::string &path, const char *description) {
  if (!std::filesystem::is_regular_file(path)) {
    throw std::runtime_error(std::string(description) + " not found: " + path);
  }
}

void write_u16(std::ofstream &output, uint16_t value) {
  const char bytes[] = {static_cast<char>(value),
                        static_cast<char>(value >> 8)};
  output.write(bytes, sizeof(bytes));
}

void write_u32(std::ofstream &output, uint32_t value) {
  const char bytes[] = {
      static_cast<char>(value), static_cast<char>(value >> 8),
      static_cast<char>(value >> 16), static_cast<char>(value >> 24)};
  output.write(bytes, sizeof(bytes));
}

void write_wav(const std::string &path, const std::vector<float> &samples,
               int sample_rate) {
  std::ofstream output(path, std::ios::binary);
  if (!output) throw std::runtime_error("Cannot create output WAV: " + path);

  const auto data_size = static_cast<uint32_t>(samples.size() * 2);
  output.write("RIFF", 4);
  write_u32(output, 36 + data_size);
  output.write("WAVEfmt ", 8);
  write_u32(output, 16);
  write_u16(output, 1);
  write_u16(output, 1);
  write_u32(output, static_cast<uint32_t>(sample_rate));
  write_u32(output, static_cast<uint32_t>(sample_rate * 2));
  write_u16(output, 2);
  write_u16(output, 16);
  output.write("data", 4);
  write_u32(output, data_size);
  for (const float sample : samples) {
    const float clipped = std::clamp(sample, -1.0F, 1.0F);
    const auto pcm = static_cast<int16_t>(std::lrint(clipped * 32767.0F));
    write_u16(output, static_cast<uint16_t>(pcm));
  }
  if (!output.good()) throw std::runtime_error("Failed to write output WAV");
}

int synthesize(const Arguments &args, InputMode mode) {
  require_file(args.model, "Model");
  require_file(args.config, "Model config");
  if (mode == InputMode::Hanzi) {
    require_file(args.g2pw_dir + "/char_bopomofo_dict.json",
                 "G2PW character dictionary");
    require_file(args.g2pw_dir + "/bopomofo_to_pinyin_wo_tune_dict.json",
                 "G2PW pinyin dictionary");
  }

  piper_create_options create_options;
  piper_init_create_options(&create_options);
  create_options.model_path = args.model.c_str();
  create_options.config_path = args.config.c_str();
  if (mode == InputMode::Hanzi) {
    create_options.g2pw_model_dir = args.g2pw_dir.c_str();
  }
  PiperPtr piper(piper_create_with_options(&create_options));
  if (!piper) throw std::runtime_error("Failed to initialize Piper");

  auto options = piper_default_synthesize_options(piper.get());
  options.length_scale = args.length_scale;
  if (piper_synthesize_start(piper.get(), args.text.c_str(), &options) < 0) {
    throw std::runtime_error("Piper rejected the input text");
  }

  std::vector<float> samples;
  int sample_rate = 0;
  for (;;) {
    piper_audio_chunk chunk{};
    const int status = piper_synthesize_next(piper.get(), &chunk);
    if (status < 0) throw std::runtime_error("Piper synthesis failed");
    sample_rate = chunk.sample_rate;
    if (chunk.samples != nullptr && chunk.num_samples > 0) {
      samples.insert(samples.end(), chunk.samples,
                     chunk.samples + chunk.num_samples);
    }
    if (status == PIPER_DONE || chunk.is_last) break;
  }
  if (samples.empty() || sample_rate <= 0) {
    throw std::runtime_error("Piper returned no audio");
  }

  write_wav(args.output, samples, sample_rate);
  const double seconds =
      static_cast<double>(samples.size()) / static_cast<double>(sample_rate);
  std::cout << "mode=" << (mode == InputMode::Hanzi ? "hanzi" : "pinyin")
            << "\ninput=" << args.text << "\nlength_scale="
            << args.length_scale << "\nsample_rate=" << sample_rate
            << "\nsamples=" << samples.size() << "\nduration_seconds="
            << seconds << "\noutput=" << args.output << '\n';
  return 0;
}

}  // namespace

int run_tts_compare(int argc, char **argv, InputMode mode) {
  try {
    const Arguments args = parse_arguments(argc, argv, mode);
    if (args.model.empty()) return 0;
    return synthesize(args, mode);
  } catch (const std::exception &error) {
    std::cerr << "error: " << error.what() << '\n';
    print_usage(argv[0], mode);
    return 1;
  }
}
