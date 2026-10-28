# SNAC 朗读录音实验

这是独立实验，不接入 Flutter、学习记录或上传逻辑。它使用
`hubertsiuzdak/snac_24khz` 将 24 kHz 单声道语音编码为三层离散 token。

实验同时保留：

- `original.wav`：原始 24 kHz、16-bit PCM 录音；
- `recording.snaclab`：每个 token 按 12 bit 紧凑打包的实验容器；
- `restored.wav`：由 SNAC token 解码得到的音频。

`.snaclab` 是本项目的实验容器，不是 SNAC 官方文件格式。容器记录采样数、
三层 token 长度和 CRC32，因此可以恢复原始时长并发现文件损坏。

## 安装

建议使用单独的虚拟环境，避免把 PyTorch 加入项目常规依赖：

```bash
cd app
python -m venv .venv-snac
.venv-snac/bin/pip install torch --index-url https://download.pytorch.org/whl/cpu
.venv-snac/bin/pip install -r tool/snac_audio_lab_requirements.txt
```

上面的第一条安装命令明确选择 CPU 版 PyTorch，避免在没有 CUDA 的 Linux
设备上下载数 GB 的 NVIDIA 运行库。如需使用 NVIDIA GPU，可跳过第一条命令，
按照 PyTorch 官网与本机 CUDA 版本匹配的方式安装后，再安装 requirements。

Linux 录音和播放还需要 PortAudio。openSUSE 可安装 `portaudio-devel`，
Debian/Ubuntu 可安装 `libportaudio2`。

首次编码或解码会从 Hugging Face 下载约 80 MB 的模型并缓存在用户目录。

## 一次完成录音、编码、解码和试听

```bash
.venv-snac/bin/python tool/snac_audio_lab.py demo .snac-audio-lab --seconds 8
```

程序先播放原始录音，再播放 SNAC 还原结果，并打印实际文件大小、码率、
压缩比、各层 token 数及编解码耗时。没有音频输出设备时可增加 `--no-play`。

## 分步操作

```bash
# 录音并保留原始 WAV
.venv-snac/bin/python tool/snac_audio_lab.py record original.wav --seconds 8

# 加载已有 WAV 并编码；非 24 kHz 或多声道输入会自动转换
.venv-snac/bin/python tool/snac_audio_lab.py encode original.wav recording.snaclab

# 解码、保存并播放
.venv-snac/bin/python tool/snac_audio_lab.py decode recording.snaclab restored.wav --play

# 单独播放原始音频
.venv-snac/bin/python tool/snac_audio_lab.py play original.wav

# 查看 token 数、文件大小和实际码率
.venv-snac/bin/python tool/snac_audio_lab.py inspect recording.snaclab
```

默认优先使用 CUDA，其次使用 Apple MPS，否则使用 CPU。可以通过
`--device cpu` 强制在 CPU 上测试。录音设备不正确时，可用
`python -m sounddevice` 查看设备，再传入 `--input-device 编号`。

## 不下载模型的快速检查

```bash
python tool/snac_audio_lab.py self-test
```

该命令只验证 12-bit token 打包、容器往返及损坏检测，不需要 PyTorch。
