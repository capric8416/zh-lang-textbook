import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/services/numeric_pinyin.dart';

void main() {
  test('带调拼音转换为 Piper 数字声调', () {
    expect(toNumericPinyin('sì dāo'), 'si4 dao1');
    expect(toNumericPinyin('èr yuè chūn fēng'), 'er4 yue4 chun1 feng1');
  });

  test('轻声和 v 规范化', () {
    expect(toNumericPinyin('ma de nǚ lü4 nu:3'), 'ma5 de5 nv3 lv4 nv3');
  });

  test('忽略标点并保留已有数字声调', () {
    expect(toNumericPinyin('si4 dao1。'), 'si4 dao1');
  });

  test('完整保留复韵母、特殊韵母和鼻韵母', () {
    expect(
      toNumericPinyin(
        'ā ó è yī wǔ lǜ '
        'ái méi shuǐ hǎo dòu liù xiě xué '
        'ér ān én yīn lún yún '
        'áng děng tīng qióng',
      ),
      'a1 o2 e4 yi1 wu3 lv4 '
      'ai2 mei2 shui3 hao3 dou4 liu4 xie3 xue2 '
      'er2 an1 en2 yin1 lun2 yun2 '
      'ang2 deng3 ting1 qiong2',
    );
  });

  test('兼容复韵母标调位置规则', () {
    expect(
      toNumericPinyin('lào lóu lèi liú duì tā tè jū qǔ xù'),
      'lao4 lou2 lei4 liu2 dui4 ta1 te4 ju1 qu3 xu4',
    );
  });

  test('ü 和 ün 统一为 v 与 vn', () {
    expect(toNumericPinyin('lǜ nüè nǚ yūn'), 'lv4 nve4 nv3 yun1');
  });
}
