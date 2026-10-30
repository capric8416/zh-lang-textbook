#ifndef UTILS_H_
#define UTILS_H_

#include <vector>
#include <fstream>
#include <string>
#include <opencv2/core.hpp>

namespace ncnn
{
class Net;
}

namespace OCR
{

int GetThreads(const int threads);

std::vector<cv::Point2f> GetMinBoxes(const cv::RotatedRect &rrect, int &max_side_len);

float BoxScoreFast(const std::vector<cv::Point2f> &boxes, const cv::Mat &binary);

float GetUnclipDistance(const std::vector<cv::Point2f> &boxes, const float unclip_ratio);

cv::RotatedRect Unclip(const std::vector<cv::Point2f> &boxes, const float unclip_ratio);

cv::Mat GetRotatedCropImage(const cv::Mat &image, std::vector<cv::Point> points);

void Trim(std::string &s);

// Open UTF-8 paths through the native wide-character APIs on Windows.
std::ifstream OpenUtf8Input(const std::string &path);

// Load both .param and .bin through FILE handles opened with Unicode support.
bool LoadNcnnModel(ncnn::Net &net, const std::string &model_path);

}   // namespace OCR

#endif  // UTILS_H_
