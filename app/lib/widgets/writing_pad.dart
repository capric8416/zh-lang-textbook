import 'dart:math' as math;

import 'package:flutter/material.dart';

enum WritingTool { pen, eraser }

enum WritingGrid { hanzi, pinyin }

class WritingPad extends StatefulWidget {
  const WritingPad({super.key, required this.grid, required this.slotLengths});

  final WritingGrid grid;
  final List<int> slotLengths;

  @override
  State<WritingPad> createState() => WritingPadState();
}

class WritingPadState extends State<WritingPad> {
  late List<List<_Stroke>> _slots;
  WritingTool _tool = WritingTool.pen;

  bool get hasWriting => _slots.any((slot) => slot.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _slots = _emptySlots(widget.slotLengths.length);
  }

  @override
  void didUpdateWidget(covariant WritingPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.grid != widget.grid ||
        oldWidget.slotLengths.join(',') != widget.slotLengths.join(',')) {
      _slots = _emptySlots(widget.slotLengths.length);
    }
  }

  List<List<_Stroke>> _emptySlots(int count) =>
      List.generate(math.max(1, count), (_) => <_Stroke>[]);

  void clear() =>
      setState(() => _slots = _emptySlots(widget.slotLengths.length));

  Size _slotSize(int index) {
    if (widget.grid == WritingGrid.hanzi) return const Size(72, 72);
    final letters = index < widget.slotLengths.length
        ? widget.slotLengths[index]
        : 1;
    return Size(math.max(72, 24 + letters * 24).toDouble(), 64);
  }

  Future<void> _openSlot(int index) async {
    final sourceSize = _slotSize(index);
    final result = await showDialog<List<_Stroke>>(
      context: context,
      builder: (context) => _WritingDialog(
        grid: widget.grid,
        tool: _tool,
        strokes: _slots[index],
        sourceSize: sourceSize,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _slots[index] = result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isHanzi = widget.grid == WritingGrid.hanzi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SegmentedButton<WritingTool>(
              segments: const [
                ButtonSegment(value: WritingTool.pen, icon: Icon(Icons.edit)),
                ButtonSegment(
                  value: WritingTool.eraser,
                  icon: Icon(Icons.cleaning_services_outlined),
                ),
              ],
              selected: {_tool},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _tool = value.first),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: hasWriting ? clear : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('清空'),
            ),
            const Spacer(),
            Text('双击格子放大书写', style: TextStyle(color: colors.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: isHanzi ? 6 : 10,
          runSpacing: isHanzi ? 6 : 10,
          children: [
            for (var index = 0; index < _slots.length; index++)
              _WritingCell(
                size: _slotSize(index),
                grid: widget.grid,
                tool: _tool,
                strokes: _slots[index],
                onChanged: (strokes) => setState(() => _slots[index] = strokes),
                onDoubleTap: () => _openSlot(index),
              ),
          ],
        ),
      ],
    );
  }
}

class _WritingDialog extends StatefulWidget {
  const _WritingDialog({
    required this.grid,
    required this.tool,
    required this.strokes,
    required this.sourceSize,
  });

  final WritingGrid grid;
  final WritingTool tool;
  final List<_Stroke> strokes;
  final Size sourceSize;

  @override
  State<_WritingDialog> createState() => _WritingDialogState();
}

class _WritingDialogState extends State<_WritingDialog> {
  late final Size _canvasSize;
  late List<_Stroke> _strokes;
  late WritingTool _tool = widget.tool;

  @override
  void initState() {
    super.initState();
    _canvasSize = widget.grid == WritingGrid.hanzi
        ? const Size(260, 260)
        : Size(
            widget.sourceSize.width *
                math.min(3.0, 560.0 / widget.sourceSize.width),
            widget.sourceSize.height *
                math.min(3.0, 560.0 / widget.sourceSize.width),
          );
    _strokes = _scaleStrokes(widget.strokes, widget.sourceSize, _canvasSize);
  }

  List<_Stroke> _scaleStrokes(List<_Stroke> strokes, Size from, Size to) => [
    for (final stroke in strokes)
      _Stroke([
        for (final point in stroke.points)
          Offset(
            point.dx * to.width / from.width,
            point.dy * to.height / from.height,
          ),
      ]),
  ];

  @override
  Widget build(BuildContext context) {
    final isHanzi = widget.grid == WritingGrid.hanzi;
    return AlertDialog(
      title: Text(isHanzi ? '田字格书写' : '拼音格书写'),
      content: SizedBox(
        width: isHanzi ? 300 : _canvasSize.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<WritingTool>(
              segments: const [
                ButtonSegment(value: WritingTool.pen, icon: Icon(Icons.edit)),
                ButtonSegment(
                  value: WritingTool.eraser,
                  icon: Icon(Icons.cleaning_services_outlined),
                ),
              ],
              selected: {_tool},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _tool = value.first),
            ),
            const SizedBox(height: 16),
            _WritingCell(
              size: _canvasSize,
              grid: widget.grid,
              tool: _tool,
              strokes: _strokes,
              onChanged: (value) => setState(() => _strokes = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _scaleStrokes(_strokes, _canvasSize, widget.sourceSize),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _WritingCell extends StatefulWidget {
  const _WritingCell({
    required this.size,
    required this.grid,
    required this.tool,
    required this.strokes,
    required this.onChanged,
    this.onDoubleTap,
  });

  final Size size;
  final WritingGrid grid;
  final WritingTool tool;
  final List<_Stroke> strokes;
  final ValueChanged<List<_Stroke>> onChanged;
  final VoidCallback? onDoubleTap;

  @override
  State<_WritingCell> createState() => _WritingCellState();
}

class _WritingCellState extends State<_WritingCell> {
  _Stroke? _activeStroke;

  void _start(Offset point) {
    if (widget.tool == WritingTool.eraser) return _erase(point);
    final next = [
      ...widget.strokes,
      _Stroke([point]),
    ];
    _activeStroke = next.last;
    widget.onChanged(next);
  }

  void _update(Offset point) {
    if (widget.tool == WritingTool.eraser) return _erase(point);
    final active = _activeStroke;
    if (active == null) return;
    active.points.add(point);
    widget.onChanged([...widget.strokes]);
  }

  void _erase(Offset point) {
    const radius = 16.0;
    widget.onChanged([
      for (final stroke in widget.strokes)
        if (!stroke.points.any((item) => (item - point).distance <= radius))
          stroke,
    ]);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size.width,
    height: widget.size.height,
    child: ClipRect(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _start(details.localPosition),
        onPanUpdate: (details) => _update(details.localPosition),
        onPanEnd: (_) => _activeStroke = null,
        onDoubleTap: widget.onDoubleTap,
        child: CustomPaint(
          painter: _WritingPainter(
            widget.grid,
            widget.strokes,
            Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    ),
  );
}

class _Stroke {
  _Stroke(this.points);
  final List<Offset> points;
}

class _WritingPainter extends CustomPainter {
  const _WritingPainter(this.grid, this.strokes, this.inkColor);

  final WritingGrid grid;
  final List<_Stroke> strokes;
  final Color inkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid == WritingGrid.hanzi
          ? const Color(0xffe3aeb4)
          : const Color(0xff78c7a6)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, gridPaint);
    if (grid == WritingGrid.hanzi) {
      gridPaint.color = gridPaint.color.withValues(alpha: 0.55);
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        gridPaint,
      );
      canvas.drawLine(Offset.zero, Offset(size.width, size.height), gridPaint);
      canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), gridPaint);
    } else {
      canvas.drawLine(
        Offset(0, size.height * 0.42),
        Offset(size.width, size.height * 0.42),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, size.height * 0.72),
        Offset(size.width, size.height * 0.72),
        gridPaint,
      );
    }
    final ink = Paint()
      ..color = inkColor
      ..strokeWidth = math.max(2.2, math.min(size.width, size.height) / 38)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final stroke in strokes) {
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points.first,
          ink.strokeWidth / 2,
          ink..style = PaintingStyle.fill,
        );
        ink.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(covariant _WritingPainter oldDelegate) => true;
}
