# 后台模型推理

OCR、TTS、ASR 共用一个按需启动、常驻的 isolate。模型句柄只在工作 isolate 内创建、使用和释放，消息不携带指针。每次任务仍携带模型路径，工作 isolate 意外退出后，下一个请求可以重新初始化模型。

- 同步 FFI 在工作 isolate 串行执行，重复调用复用已加载模型。
- 主 isolate 保留资源解包、录音、音频播放和 UI；首次资源解包尚未优化。
- OCR 只传递尺寸及 TransferableTypedData 像素，不传递预览 PNG。
- 模型初始化失败允许下次重试。单次推理失败会回传错误，不阻断后续任务。
- 退出练习页面后忽略 OCR/ASR 结果，取消 TTS 播放意图，防止合成结束后突然播放。
- 正在执行的同步原生调用不能强行取消；其结果可丢弃，但后台仍需执行完毕。当前没有硬超时，也不会超时后销毁正在使用的模型或录音文件。
- `NativeInference.dispose()` 在已提交任务完成后于后台销毁所有模型并关闭端口，之后允许新任务重建 worker。正常使用保留模型直到进程结束，以避免每题重复加载。
- TTS 先写临时 WAV，完成后重命名；并发请求不会播放尚未写完的缓存。

## 自动测试

在 `app/` 下运行：

```bash
flutter test --no-pub test/inference_worker_test.dart test/numeric_pinyin_test.dart test/speech_assessment_test.dart
```

覆盖阻塞任务期间主 isolate 响应、FIFO 顺序与状态复用、像素传递、任务报错后恢复、意外退出后重建、等待任务完成再释放资源。

## Linux 真实模型验证

已有 Linux release bundle 时，在 `app/` 下运行：

```bash
LD_LIBRARY_PATH="$PWD/build/linux/x64/release/bundle/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  dart run tool/inference_smoke.dart
```

脚本使用打包前的 assets 模型，执行空白图 OCR、拼音 TTS 和合成音频 ASR，不调用录音和播放器、不读写账号数据。临时文件在 app/ 下创建，完成后清理。

每项输出耗时与调用侧 20ms 定时器的运行次数。它验证真实 FFI 调用期间调用侧仍能响应，不等价于 Flutter 帧耗时或 Android 真机测试。

手动验收：Linux 和 Android 的 debug/profile App 分别执行手写批改、听写播放、朗读检查，观察加载动画及滚动响应；在合成/识别过程中返回上一页，确认没有迟到的播放、弹窗或自动保存。再次进入页面后重试，确认模型可复用。首次初始化和预热后的耗时、DevTools 帧耗时及内存应分别记录。
