# Piper 汉字/拼音输入对照程序

这两个程序直接调用项目静态编译的 Piper，绕过 Flutter、音频缓存、重复播放和动态语速：

- `piper_hanzi_linux` 将 UTF-8 汉字原样送入 Piper 的汉字 phonemizer。
- `piper_pinyin_linux` 将数字声调拼音原样送入 Piper 的直接拼音解析器。

两者默认使用相同的 `length_scale=1.0` 和模型配置中的 `noise_scale`、`noise_w`。

## 构建

先确保 Linux 静态语音依赖已经生成，然后执行：

```bash
cd app/native/speech/examples/linux
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
./download_g2pw.sh
```

## 生成对照音频

在当前目录执行：

```bash
model=../../../../assets/speech/piper-zh_CN-xiao_ya-medium/model.onnx

./build/piper_hanzi_linux \
  --model "$model" \
  --g2pw-dir build/g2pw \
  --output build/hanzi.wav \
  --text '忙趁东风放纸鸢。'

./build/piper_pinyin_linux \
  --model "$model" \
  --output build/pinyin.wav \
  --text 'mang2 chen4 dong1 feng1 fang4 zhi3 yuan1'
```

也可以不传 `--text`，从标准输入读取：

```bash
printf '%s\n' '忙趁东风放纸鸢。' | ./build/piper_hanzi_linux \
  --model "$model" --g2pw-dir build/g2pw --output build/hanzi.wav
```

汉字程序使用的是 Piper 当前实现的轻量 G2PW 字典路径，多音字可能选择词典中的第一个读音；该程序主要用于比较两条输入链路的节奏和韵律，不用于验证多音字准确率。

项目会在构建 Piper 时应用 `patches/piper-pinyin-whitespace.patch`：纯拼音中的空格只用于切分音节，不再转成停顿 phone。拼音示例暂不带句末标点，因此除该空格处理外仍与 Flutter 当前输入一致。
