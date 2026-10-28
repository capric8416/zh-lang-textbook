#ifndef ZH_SPEECH_BRIDGE_H_
#define ZH_SPEECH_BRIDGE_H_

#include <stdint.h>

#if defined(_WIN32)
#define ZH_SPEECH_API __declspec(dllexport)
#else
#define ZH_SPEECH_API __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

ZH_SPEECH_API void *zh_speech_tts_create(
    const char *model_path, const char *config_path);
ZH_SPEECH_API void zh_speech_tts_destroy(void *handle);

// Synthesizes whitespace-separated numeric pinyin (for example "si4 dao1")
// and writes a mono 16-bit PCM WAV. Returns 0 on success.
ZH_SPEECH_API int32_t zh_speech_tts_synthesize_wav(
    void *handle, const char *numeric_pinyin, const char *output_path,
    float length_scale, int32_t repeat);

ZH_SPEECH_API void *zh_speech_asr_create(
    const char *paraformer_model_dir, const char *vad_model_dir);
ZH_SPEECH_API void zh_speech_asr_destroy(void *handle);

// Returns the UTF-8 byte length (excluding NUL), or a negative error code.
ZH_SPEECH_API int32_t zh_speech_asr_recognize_wav(
    void *handle, const char *wav_path, char *output, int32_t output_capacity);

// SNAC 24 kHz INT8 ONNX. The codec container stores three 12-bit token streams.
// 0 means success; negative values indicate invalid input, I/O or inference.
ZH_SPEECH_API void *zh_speech_snac_create(const char *encoder_path,
                                          const char *decoder_path);
ZH_SPEECH_API void zh_speech_snac_destroy(void *handle);
ZH_SPEECH_API int32_t zh_speech_snac_encode_wav(void *handle,
                                               const char *wav_path,
                                               const char *output_path);
ZH_SPEECH_API int32_t zh_speech_snac_decode_wav(void *handle,
                                               const char *snac_path,
                                               const char *output_path);

#ifdef __cplusplus
}
#endif

#endif  // ZH_SPEECH_BRIDGE_H_
