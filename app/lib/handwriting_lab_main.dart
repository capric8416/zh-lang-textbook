import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'models/handwriting.dart';

void main() => runApp(const MaterialApp(home: HandwritingLab()));

class HandwritingLab extends StatefulWidget {
  const HandwritingLab({super.key});
  @override
  State<HandwritingLab> createState() => _HandwritingLabState();
}

class _HandwritingLabState extends State<HandwritingLab> {
  InkDocument _document = InkDocument.empty();
  InkDocument? _restored;
  final _path = TextEditingController();
  double _width = 4;
  double _scale = 1;
  Color _color = Colors.black;
  String _status = '在格子中直接书写；保存后点击“读取并还原”。';
  bool _busy = false;
  int? _pointer;
  InkStroke? _active;

  @override
  void initState() {
    super.initState();
    _initializePath();
  }

  Future<void> _initializePath() async {
    try {
      final directory = await getApplicationSupportDirectory();
      if (mounted && _path.text.isEmpty) {
        _path.text = '${directory.path}/handwriting-lab.json.gz';
      }
    } catch (error) {
      if (mounted) setState(() => _status = '请手动填写文件路径：$error');
    }
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _fileAction(bool save) async {
    setState(() => _busy = true);
    try {
      if (_path.text.trim().isEmpty) throw const FormatException('请填写文件路径');
      final file = File(_path.text.trim());
      if (save) {
        final originalSize = utf8.encode(_document.encode()).length;
        final content = _document.encodeCompressed();
        await file.parent.create(recursive: true);
        await file.writeAsBytes(content, flush: true);
        if (mounted) {
          setState(
            () => _status =
                '已保存：$originalSize → ${content.length} 字节'
                '（节省 ${(100 * (1 - content.length / originalSize)).toStringAsFixed(1)}%）：${file.path}',
          );
        }
      } else {
        final document = InkDocument.decodeBytes(await file.readAsBytes());
        if (mounted) {
          setState(() {
            _restored = document;
            _status = '已从文件还原 ${document.cells.length} 个格子（下方只读预览）';
          });
        }
      }
    } catch (error) {
      if (mounted) setState(() => _status = '操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _cell(InkCell cell, double scale, bool editable) {
    final size = Size(cell.size.width * scale, cell.size.height * scale);
    Offset relative(Offset p) => Offset(p.dx / size.width, p.dy / size.height);
    return Listener(
      onPointerDown: !editable
          ? null
          : (event) {
              if (_pointer != null) return;
              _pointer = event.pointer;
              setState(() {
                _active = InkStroke(
                  _color.toARGB32(),
                  _width / cell.size.height,
                  [relative(event.localPosition)],
                );
                cell.strokes.add(_active!);
              });
            },
      onPointerMove: !editable
          ? null
          : (event) {
              if (_pointer != event.pointer) return;
              setState(
                () => _active?.points.add(relative(event.localPosition)),
              );
            },
      onPointerUp: (_) {
        _pointer = null;
        _active = null;
      },
      onPointerCancel: (_) {
        _pointer = null;
        _active = null;
      },
      child: GestureDetector(
        onPanStart: editable ? (_) {} : null,
        child: ColoredBox(
          color: Colors.white,
          child: CustomPaint(size: size, painter: InkPainter(cell)),
        ),
      ),
    );
  }

  Widget _sheet(InkDocument document, double scale, bool editable) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final fittedScale = scale.clamp(0.0, constraints.maxWidth / 350);
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final cell in document.cells)
                _cell(cell, fittedScale, editable),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('手写轨迹保存与还原测试')),
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('4 个田字格 + 3 个不同宽度的四线拼音格；此入口不登录、不使用 OCR、不上传。'),
            TextField(
              controller: _path,
              decoration: const InputDecoration(
                labelText: '轨迹 gzip 文件路径（保存会覆盖此文件）',
              ),
            ),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _fileAction(true),
                  child: const Text('保存轨迹文件'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _fileAction(false),
                  child: const Text('读取并还原'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _active = null;
                    _pointer = null;
                    _document = InkDocument.empty();
                  }),
                  child: const Text('清空书写区'),
                ),
              ],
            ),
            SelectableText(_status),
            Row(
              children: [
                Text('笔宽 ${_width.round()}'),
                SizedBox(
                  width: 180,
                  child: Slider(
                    value: _width,
                    min: 1,
                    max: 12,
                    divisions: 11,
                    onChanged: (value) => setState(() => _width = value),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final color in [Colors.black, Colors.blue, Colors.red])
                  ChoiceChip(
                    label: Text(
                      color == Colors.black
                          ? '黑色'
                          : color == Colors.blue
                          ? '蓝色'
                          : '红色',
                    ),
                    selected: _color == color,
                    onSelected: (_) => setState(() => _color = color),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Scroll outside the cells; touch input inside the sheet stays writing.
            _sheet(_document, 1, true),
            const Divider(height: 40),
            Text('文件还原预览 · ${_scale.toStringAsFixed(1)} 倍'),
            Slider(
              value: _scale,
              min: 0.3,
              max: 1.5,
              onChanged: (value) => setState(() => _scale = value),
            ),
            if (_restored != null) _sheet(_restored!, _scale, false),
          ],
        ),
      ),
    ),
  );
}
