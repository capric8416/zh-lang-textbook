#include "speech_bridge.h"
#include <cstdio>

int main(int argc, char** argv) {
  if (argc != 6) {
    std::fprintf(stderr, "usage: snac_smoke encoder.onnx decoder.onnx input.wav output.snaclab restored.wav\n");
    return 2;
  }
  void* codec = zh_speech_snac_create(argv[1], argv[2]);
  if (!codec) {
    std::fprintf(stderr, "failed to load SNAC models\n");
    return 1;
  }
  int encoded = zh_speech_snac_encode_wav(codec, argv[3], argv[4]);
  int decoded = encoded == 0 ? zh_speech_snac_decode_wav(codec, argv[4], argv[5]) : -1;
  zh_speech_snac_destroy(codec);
  std::fprintf(stderr, "encode=%d decode=%d\n", encoded, decoded);
  return encoded == 0 && decoded == 0 ? 0 : 1;
}
