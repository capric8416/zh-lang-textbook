import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pet.dart';

class PetAppearance {
  const PetAppearance({
    required this.coat,
    required this.muzzle,
    required this.marking,
    required this.earDrop,
  });

  factory PetAppearance.fromBreed(String id) {
    final breed = petBreed(id);
    return PetAppearance(
      coat: Color(breed.coat),
      muzzle: const Color(0xffffe0b2),
      marking: Color(breed.marking),
      earDrop: breed.earDrop,
    );
  }

  static const defaultDog = PetAppearance(
    coat: Color(0xffd89955),
    muzzle: Color(0xffffe0b2),
    marking: Color(0xff8d552f),
    earDrop: 0.85,
  );

  final Color coat;
  final Color muzzle;
  final Color marking;
  final double earDrop;
}

Color petAuraColor(PetExpression expression) => switch (expression) {
  PetExpression.happy => const Color(0xffffc857),
  PetExpression.wink => const Color(0xff55b8ff),
  PetExpression.starry => const Color(0xffa779ff),
  PetExpression.radiant => const Color(0xffff6fae),
};

class PetAvatar extends StatelessWidget {
  const PetAvatar({
    super.key,
    this.size = 96,
    this.expression = PetExpression.happy,
    this.appearance = PetAppearance.defaultDog,
    this.decoration = const PetDecoration(
      id: 'none',
      name: '清爽',
      unlockStage: 0,
    ),
    this.showAura = true,
  });

  final double size;
  final PetExpression expression;
  final PetAppearance appearance;
  final bool showAura;
  final PetDecoration decoration;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '宠物成长伙伴',
    image: true,
    child: CustomPaint(
      key: const ValueKey('pet-avatar'),
      size: Size.square(size),
      painter: _DogPainter(
        expression: expression,
        appearance: appearance,
        auraColor: showAura ? petAuraColor(expression) : Colors.transparent,
        decoration: decoration,
      ),
    ),
  );
}

class _DogPainter extends CustomPainter {
  const _DogPainter({
    required this.expression,
    required this.appearance,
    required this.auraColor,
    required this.decoration,
  });

  final PetExpression expression;
  final PetAppearance appearance;
  final Color auraColor;
  final PetDecoration decoration;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 100;
    canvas.save();
    canvas.scale(scale, scale);

    if (auraColor.a > 0) {
      canvas.drawCircle(
        const Offset(50, 51),
        43,
        Paint()
          ..color = auraColor.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }

    final coat = Paint()..color = appearance.coat;
    final marking = Paint()..color = appearance.marking;
    final muzzle = Paint()..color = appearance.muzzle;
    final dark = Paint()
      ..color = const Color(0xff3d2b1f)
      ..strokeCap = StrokeCap.round;
    if (decoration.background != 0) {
      canvas.drawCircle(
        const Offset(50, 51),
        44,
        Paint()..color = Color(decoration.background),
      );
    }

    final earDrop = appearance.earDrop * 12;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(24, 38 + earDrop / 4),
        width: 22,
        height: 35 + earDrop,
      ),
      marking,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(76, 38 + earDrop / 4),
        width: 22,
        height: 35 + earDrop,
      ),
      marking,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 49), width: 62, height: 66),
      coat,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 61), width: 41, height: 31),
      muzzle,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(42, 28), width: 22, height: 17),
      muzzle..color = appearance.muzzle.withValues(alpha: 0.78),
    );

    _paintEyes(canvas, dark);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 54), width: 10, height: 7),
      dark,
    );
    canvas.drawArc(
      const Rect.fromLTWH(43, 56, 14, 11),
      0.15,
      math.pi - 0.3,
      false,
      dark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.3,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 69), width: 8, height: 6),
      Paint()..color = const Color(0xffff7597),
    );
    if (decoration.color != 0) {
      final accent = Paint()..color = Color(decoration.color);
      canvas.drawArc(
        const Rect.fromLTWH(29, 65, 42, 18),
        0,
        math.pi,
        false,
        accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
    }

    canvas.restore();
  }

  void _paintEyes(Canvas canvas, Paint dark) {
    switch (expression) {
      case PetExpression.happy:
        _happyEye(canvas, const Offset(38, 44), dark);
        _happyEye(canvas, const Offset(62, 44), dark);
      case PetExpression.wink:
        _happyEye(canvas, const Offset(38, 44), dark);
        canvas.drawLine(
          const Offset(58, 44),
          const Offset(66, 43),
          dark..strokeWidth = 2.8,
        );
      case PetExpression.starry:
        _star(canvas, const Offset(38, 43), 5, dark);
        _star(canvas, const Offset(62, 43), 5, dark);
      case PetExpression.radiant:
        _heart(canvas, const Offset(38, 43), dark);
        _heart(canvas, const Offset(62, 43), dark);
    }
  }

  void _happyEye(Canvas canvas, Offset center, Paint paint) {
    canvas.drawArc(
      Rect.fromCenter(center: center, width: 10, height: 8),
      math.pi,
      math.pi,
      false,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8,
    );
  }

  void _star(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (var index = 0; index < 10; index++) {
      final angle = -math.pi / 2 + index * math.pi / 5;
      final distance = index.isEven ? radius : radius * 0.42;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * distance;
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
  }

  void _heart(Canvas canvas, Offset center, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy + 5)
      ..cubicTo(
        center.dx - 9,
        center.dy,
        center.dx - 5,
        center.dy - 7,
        center.dx,
        center.dy - 2,
      )
      ..cubicTo(
        center.dx + 5,
        center.dy - 7,
        center.dx + 9,
        center.dy,
        center.dx,
        center.dy + 5,
      )
      ..close();
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_DogPainter oldDelegate) =>
      expression != oldDelegate.expression ||
      appearance != oldDelegate.appearance ||
      decoration != oldDelegate.decoration ||
      auraColor != oldDelegate.auraColor;
}
