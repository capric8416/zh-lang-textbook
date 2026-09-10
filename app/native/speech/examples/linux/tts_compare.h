#pragma once

enum class InputMode { Hanzi, Pinyin };

int run_tts_compare(int argc, char **argv, InputMode mode);
