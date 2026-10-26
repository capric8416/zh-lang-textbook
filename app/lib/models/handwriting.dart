import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Coordinates and brush widths are relative to each cell, not the screen.
class InkStroke {
  InkStroke(this.color, this.width, this.points);

  factory InkStroke.fromAbsolute({
    required int color,
    required double width,
    required Size cellSize,
    required Iterable<Offset> points,
  }) => InkStroke(color, width / cellSize.height, [
    for (final point in points)
      Offset(point.dx / cellSize.width, point.dy / cellSize.height),
  ]);
  final int color;
  final double width;
  final List<Offset> points;

  Map<String, dynamic> toJson() => {
    'color': color,
    'width': width,
    'points': [
      for (final p in points) [p.dx, p.dy],
    ],
  };
}

class InkCell {
  InkCell(this.grid, this.size, this.strokes);
  final String grid;
  final Size size;
  final List<InkStroke> strokes;

  Map<String, dynamic> toJson() => {
    'grid': grid,
    'width': size.width,
    'height': size.height,
    'strokes': strokes.map((s) => s.toJson()).toList(),
  };
}

class InkDocument {
  InkDocument(this.cells);
  final List<InkCell> cells;

  List<int> encodeCompressed() => gzip.encode(utf8.encode(encode()));

  factory InkDocument.decodeBytes(List<int> bytes) {
    return InkDocument.decode(utf8.decode(gzip.decode(bytes)));
  }

  factory InkDocument.empty() => InkDocument([
    for (var i = 0; i < 4; i++) InkCell('hanzi', const Size(140, 140), []),
    for (final width in [210.0, 280.0, 350.0])
      InkCell('pinyin', Size(width, 100), []),
  ]);

  String encode() => jsonEncode({
    'version': 1,
    'coordinates': 'cell-relative',
    'brushWidthUnit': 'cell-height',
    'layout': 'ordered-wrap',
    'spacing': 12,
    'cells': cells.map((c) => c.toJson()).toList(),
  });

  factory InkDocument.decode(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    if (data['version'] != 1 ||
        data['coordinates'] != 'cell-relative' ||
        data['brushWidthUnit'] != 'cell-height' ||
        data['layout'] != 'ordered-wrap' ||
        data['spacing'] != 12) {
      throw const FormatException('不支持的轨迹格式');
    }
    double number(dynamic v) {
      if (v is! num || !v.isFinite) throw const FormatException('无效坐标或尺寸');
      return v.toDouble();
    }

    return InkDocument([
      for (final c in data['cells'] as List)
        (() {
          final width = number(c['width']);
          final height = number(c['height']);
          if (width <= 0 ||
              height <= 0 ||
              !['hanzi', 'pinyin'].contains(c['grid'])) {
            throw const FormatException('无效书写格');
          }
          return InkCell(c['grid'] as String, Size(width, height), [
            for (final s in c['strokes'] as List)
              (() {
                final brush = number(s['width']);
                final color = s['color'];
                if (brush <= 0 ||
                    color is! int ||
                    color < 0 ||
                    color > 0xffffffff) {
                  throw const FormatException('无效笔刷');
                }
                return InkStroke(color, brush, [
                  for (final p in s['points'] as List)
                    Offset(number(p[0]), number(p[1])),
                ]);
              })(),
          ]);
        })(),
    ]);
  }
}

class InkPainter extends CustomPainter {
  InkPainter(this.cell);
  final InkCell cell;

  @override
  void paint(Canvas canvas, Size size) {
    paintWritingGrid(canvas, size, hanzi: cell.grid == 'hanzi');
    for (final stroke in cell.strokes) {
      if (stroke.points.isEmpty) continue;
      final ink = Paint()
        ..color = Color(stroke.color)
        ..strokeWidth = stroke.width * size.height
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      Offset position(Offset p) =>
          Offset(p.dx * size.width, p.dy * size.height);
      final first = position(stroke.points.first);
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          first,
          ink.strokeWidth / 2,
          ink..style = PaintingStyle.fill,
        );
      } else {
        final path = Path()..moveTo(first.dx, first.dy);
        for (final p in stroke.points.skip(1)) {
          final point = position(p);
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, ink);
      }
    }
  }

  @override
  bool shouldRepaint(covariant InkPainter oldDelegate) => true;
}

/// Shared grid painter for the interactive writing pad and history renderer.
void paintWritingGrid(Canvas canvas, Size size, {required bool hanzi}) {
  final grid = Paint()
    ..color = hanzi ? const Color(0xffe3aeb4) : const Color(0xff78c7a6)
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;
  canvas.drawRect(Offset.zero & size, grid);
  if (hanzi) {
    grid.color = grid.color.withValues(alpha: 0.55);
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      grid,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      grid,
    );
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), grid);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), grid);
  } else {
    for (final fraction in [0.42, 0.72]) {
      canvas.drawLine(
        Offset(0, size.height * fraction),
        Offset(size.width, size.height * fraction),
        grid,
      );
    }
  }
}
