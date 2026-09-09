#ifndef ZH_OCR_BRIDGE_H_
#define ZH_OCR_BRIDGE_H_

#include <stdint.h>

#if defined(_WIN32)
#define ZH_OCR_API __declspec(dllexport)
#else
#define ZH_OCR_API __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

ZH_OCR_API void *zh_ocr_create(const char *config_path);

ZH_OCR_API void zh_ocr_destroy(void *handle);

// Returns the UTF-8 byte length (excluding the trailing NUL), or a negative
// value on failure. If output is too small, no partial text is returned.
ZH_OCR_API int32_t zh_ocr_recognize_rgba(
    void *handle,
    const uint8_t *rgba,
    int32_t width,
    int32_t height,
    int32_t row_bytes,
    char *output,
    int32_t output_capacity);

#ifdef __cplusplus
}
#endif

#endif  // ZH_OCR_BRIDGE_H_
