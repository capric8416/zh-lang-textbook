#include "ocr_bridge.h"

#include <cstring>
#include <memory>
#include <mutex>
#include <string>

#include <opencv2/imgproc.hpp>

#include "src/ocr_engine.h"

namespace
{

struct OcrHandle
{
    OCR::OCREngine engine;
    std::mutex mutex;
};

}  // namespace

void *zh_ocr_create(const char *config_path)
{
    if (config_path == nullptr)
        return nullptr;

    try
    {
        auto handle = std::make_unique<OcrHandle>();
        if (!handle->engine.Initialize(config_path))
            return nullptr;
        return handle.release();
    }
    catch (...)
    {
        return nullptr;
    }
}

void zh_ocr_destroy(void *handle)
{
    delete static_cast<OcrHandle *>(handle);
}

int32_t zh_ocr_recognize_rgba(
    void *handle,
    const uint8_t *rgba,
    int32_t width,
    int32_t height,
    int32_t row_bytes,
    char *output,
    int32_t output_capacity)
{
    if (handle == nullptr || rgba == nullptr || width <= 0 || height <= 0 ||
        row_bytes < width * 4 || output == nullptr || output_capacity <= 0)
        return -1;

    try
    {
        cv::Mat rgba_image(height, width, CV_8UC4,
            const_cast<uint8_t *>(rgba), static_cast<size_t>(row_bytes));
        cv::Mat bgr_image;
        cv::cvtColor(rgba_image, bgr_image, cv::COLOR_RGBA2BGR);

        auto *ocr = static_cast<OcrHandle *>(handle);
        std::lock_guard<std::mutex> lock(ocr->mutex);
        const auto results = ocr->engine.Run(bgr_image);

        std::string text;
        for (const auto &result : results)
            text += result.line.text;

        const auto length = static_cast<int32_t>(text.size());
        if (length + 1 > output_capacity)
            return length;
        std::memcpy(output, text.data(), text.size());
        output[length] = '\0';
        return length;
    }
    catch (...)
    {
        return -2;
    }
}
