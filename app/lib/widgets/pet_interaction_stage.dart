import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pet.dart';
import 'pet_avatar.dart';

/// The interaction cues exposed by the standalone animation gallery.
///
/// Each cue is a deliberately different, looping character performance rather
/// than a static avatar with a one-off position change.
enum PetInteractionCue {
  invite,
  think,
  correct,
  incorrect,
  complete,
  repeat,
  tailWag,
  flowerGift,
  studyTogether,
  lamp,
  bookcase,
  flowerPot,
  lessonCelebration,
  unitCelebration,
}

String petAnimationAsset(
  PetInteractionCue cue, {
  PetSpecies species = PetSpecies.dog,
}) {
  final animation = switch (cue) {
    PetInteractionCue.invite => 'invite',
    PetInteractionCue.think => 'think',
    PetInteractionCue.correct ||
    PetInteractionCue.lessonCelebration ||
    PetInteractionCue.unitCelebration => 'celebrate',
    PetInteractionCue.incorrect => 'encourage',
    PetInteractionCue.complete || PetInteractionCue.flowerGift => 'gift',
    PetInteractionCue.repeat ||
    PetInteractionCue.lamp ||
    PetInteractionCue.bookcase ||
    PetInteractionCue.flowerPot => 'idle',
    PetInteractionCue.tailWag => 'happy',
    PetInteractionCue.studyTogether => 'study',
  };
  final animalDirectory = species == PetSpecies.cat
      ? 'cat/san_hua'
      : 'dog/huang_gou_bai_mian';
  return 'assets/images/$animalDirectory/$animation.webp';
}

/// Animated dog asset with the existing vector avatar retained for cats.
class PetAnimatedCharacter extends StatelessWidget {
  const PetAnimatedCharacter({
    super.key,
    required this.profile,
    required this.cue,
    required this.size,
  });

  final PetProfile profile;
  final PetInteractionCue cue;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        petAnimationAsset(cue, species: profile.species),
        key: ValueKey('pet-live-animation-${cue.name}'),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// A continuously animated pet scene used by the interaction preview app.
class PetInteractionStage extends StatefulWidget {
  const PetInteractionStage({
    super.key,
    required this.cue,
    required this.profile,
  });

  final PetInteractionCue cue;
  final PetProfile profile;

  @override
  State<PetInteractionStage> createState() => _PetInteractionStageState();
}

class _PetInteractionStageState extends State<PetInteractionStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant PetInteractionStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cue != widget.cue) {
      _controller
        ..reset()
        ..repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: '${_label(widget.cue)}动画',
      image: true,
      child: AspectRatio(
        aspectRatio: 1.4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 18)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _PetInteractionPainter(
                      cue: widget.cue,
                      progress: reducedMotion ? 0.25 : _controller.value,
                      appearance: PetAppearance.fromBreed(widget.profile.breed),
                      decoration: petDecoration(
                        widget.profile.selectedDecoration,
                      ),
                      foreground: false,
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) => Align(
                      alignment: Alignment(-0.12, 0.12),
                      child: SizedBox.square(
                        dimension: constraints.maxHeight * 0.92,
                        child: PetAnimatedCharacter(
                          profile: widget.profile,
                          cue: widget.cue,
                          size: constraints.maxHeight * 0.92,
                        ),
                      ),
                    ),
                  ),
                  CustomPaint(
                    painter: _PetInteractionPainter(
                      cue: widget.cue,
                      progress: reducedMotion ? 0.25 : _controller.value,
                      appearance: PetAppearance.fromBreed(widget.profile.breed),
                      decoration: petDecoration(
                        widget.profile.selectedDecoration,
                      ),
                      foreground: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _label(PetInteractionCue cue) => switch (cue) {
    PetInteractionCue.invite => '挥爪邀请',
    PetInteractionCue.think => '安静思考',
    PetInteractionCue.correct => '答对庆祝',
    PetInteractionCue.incorrect => '温柔鼓励',
    PetInteractionCue.complete => '完成送花',
    PetInteractionCue.repeat => '书桌等你',
    PetInteractionCue.tailWag => '即时摇尾巴',
    PetInteractionCue.flowerGift => '即时送小花',
    PetInteractionCue.studyTogether => '趴桌陪读',
    PetInteractionCue.lamp => '点亮小台灯',
    PetInteractionCue.bookcase => '装满小书柜',
    PetInteractionCue.flowerPot => '花儿开放',
    PetInteractionCue.lessonCelebration => '课文通关庆祝',
    PetInteractionCue.unitCelebration => '单元礼花',
  };
}

class _PetInteractionPainter extends CustomPainter {
  const _PetInteractionPainter({
    required this.cue,
    required this.progress,
    required this.appearance,
    required this.decoration,
    required this.foreground,
  });

  final PetInteractionCue cue;
  final double progress;
  final PetAppearance appearance;
  final PetDecoration decoration;
  final bool foreground;

  double get _wave => math.sin(progress * math.pi * 2);
  double get _bounce => math.sin(progress * math.pi * 4);
  bool get _celebrating => switch (cue) {
    PetInteractionCue.correct ||
    PetInteractionCue.complete ||
    PetInteractionCue.tailWag ||
    PetInteractionCue.flowerGift ||
    PetInteractionCue.lessonCelebration ||
    PetInteractionCue.unitCelebration => true,
    _ => false,
  };

  @override
  void paint(Canvas canvas, Size size) {
    const design = Size(360, 250);
    final scale = math.min(
      size.width / design.width,
      size.height / design.height,
    );
    canvas
      ..translate(
        (size.width - design.width * scale) / 2,
        (size.height - design.height * scale) / 2,
      )
      ..scale(scale);

    if (foreground) {
      _paintParticles(canvas);
      _paintCaption(canvas);
    } else {
      _paintBackground(canvas);
      _paintSceneProp(canvas);
    }
  }

  void _paintBackground(Canvas canvas) {
    final (top, bottom, floor) = switch (cue) {
      PetInteractionCue.lamp ||
      PetInteractionCue.bookcase ||
      PetInteractionCue.repeat ||
      PetInteractionCue.studyTogether => (
        const Color(0xfffff1c9),
        const Color(0xffffdb9c),
        const Color(0xffc8895b),
      ),
      PetInteractionCue.flowerPot || PetInteractionCue.flowerGift => (
        const Color(0xffcceeff),
        const Color(0xffeef9d8),
        const Color(0xff8ecb79),
      ),
      PetInteractionCue.unitCelebration => (
        const Color(0xff5b4bb7),
        const Color(0xffc57de8),
        const Color(0xff3e307b),
      ),
      _ => (
        const Color(0xffffe8df),
        const Color(0xfffff8e9),
        const Color(0xffe0ae82),
      ),
    };
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 360, 250),
      Paint()
        ..shader = LinearGradient(
          colors: [top, bottom],
        ).createShader(const Rect.fromLTWH(0, 0, 360, 250)),
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 184, 360, 66),
      Paint()..color = floor,
    );
    for (var index = 0; index < 7; index++) {
      final x = index * 68.0 + 18;
      canvas.drawCircle(
        Offset(x, 34 + (index % 2) * 22),
        20,
        Paint()..color = Colors.white.withValues(alpha: 0.15),
      );
    }
  }

  void _paintSceneProp(Canvas canvas) {
    switch (cue) {
      case PetInteractionCue.lamp:
        final glow = 0.35 + 0.25 * (_wave + 1) / 2;
        canvas.drawCircle(
          Offset(272, 73),
          55 + 8 * _wave,
          Paint()..color = const Color(0xffffdf64).withValues(alpha: glow),
        );
        final pole = Paint()
          ..color = const Color(0xff795548)
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(272, 95), const Offset(272, 155), pole);
        canvas.drawLine(const Offset(245, 156), const Offset(298, 156), pole);
        canvas.drawPath(
          Path()
            ..addArc(const Rect.fromLTWH(242, 59, 60, 42), math.pi, math.pi),
          Paint()..color = const Color(0xffffc857),
        );
      case PetInteractionCue.bookcase:
        final paint = Paint()..color = const Color(0xff845d45);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(254, 48, 74, 126),
            Radius.circular(9),
          ),
          paint,
        );
        for (var shelf = 0; shelf < 3; shelf++) {
          final y = 78.0 + shelf * 31;
          canvas.drawRect(
            Rect.fromLTWH(260, y, 62, 4),
            Paint()..color = const Color(0xffffdb9c),
          );
          for (var book = 0; book < 4; book++) {
            final bob = math.sin(progress * math.pi * 2 + book) * 3;
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(263 + book * 14, y - 17 + bob, 10, 17),
                const Radius.circular(2),
              ),
              Paint()
                ..color = [
                  const Color(0xffe85d75),
                  const Color(0xff3d9be9),
                  const Color(0xffffc857),
                  const Color(0xff72a65a),
                ][book],
            );
          }
        }
      case PetInteractionCue.flowerPot:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(257, 145, 63, 33),
            Radius.circular(7),
          ),
          Paint()..color = const Color(0xffc56b45),
        );
        canvas.drawLine(
          const Offset(288, 146),
          Offset(288, 105 + 4 * _wave),
          Paint()
            ..color = const Color(0xff4d9c5a)
            ..strokeWidth = 6,
        );
        for (var leaf = 0; leaf < 2; leaf++) {
          final angle = leaf == 0 ? -0.7 : 0.7;
          canvas.save();
          canvas.translate(288, 124);
          canvas.rotate(angle + _wave * .12);
          canvas.drawOval(
            const Rect.fromLTWH(0, -5, 27, 11),
            Paint()..color = const Color(0xff65b96c),
          );
          canvas.restore();
        }
        final bloom = 14 + 4 * (_wave + 1) / 2;
        for (var petal = 0; petal < 6; petal++) {
          final angle = petal * math.pi / 3;
          canvas.drawCircle(
            Offset(
              288 + math.cos(angle) * bloom * .65,
              99 + math.sin(angle) * bloom * .65,
            ),
            bloom * .55,
            Paint()..color = const Color(0xffff7aa2),
          );
        }
        canvas.drawCircle(
          const Offset(288, 99),
          7,
          Paint()..color = const Color(0xffffcf4d),
        );
      case PetInteractionCue.studyTogether:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(222, 144, 112, 16),
            Radius.circular(5),
          ),
          Paint()..color = const Color(0xffa56947),
        );
        canvas.drawRect(
          const Rect.fromLTWH(236, 158, 10, 30),
          Paint()..color = const Color(0xff7d4c37),
        );
        canvas.drawRect(
          const Rect.fromLTWH(310, 158, 10, 30),
          Paint()..color = const Color(0xff7d4c37),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(260, 125, 43, 20),
            Radius.circular(3),
          ),
          Paint()..color = Colors.white,
        );
      default:
        break;
    }
  }

  void _paintParticles(Canvas canvas) {
    if (!(_celebrating ||
        cue == PetInteractionCue.lamp ||
        cue == PetInteractionCue.flowerPot)) {
      return;
    }
    final count = cue == PetInteractionCue.unitCelebration ? 30 : 12;
    for (var index = 0; index < count; index++) {
      final phase = (progress + index * .137) % 1;
      final x =
          (index * 83 % 340) + 10.0 + math.sin(phase * math.pi * 2 + index) * 9;
      final y = cue == PetInteractionCue.unitCelebration
          ? phase * 240 - 10
          : 45 + (index % 5) * 23 - phase * 17;
      final color = [
        const Color(0xffff5d73),
        const Color(0xffffc857),
        const Color(0xff4ecdc4),
        const Color(0xff8d78e8),
      ][index % 4];
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(phase * math.pi * 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 7, height: 12),
          const Radius.circular(2),
        ),
        Paint()..color = color,
      );
      canvas.restore();
    }
  }

  // Retained as reference geometry for future overlays; never called because
  // the character itself now comes from the transparent WebP assets.
  void paintLegacyDog(Canvas canvas) {
    var x = 150.0;
    var y = 158.0;
    var bodyScale = 1.0;
    var headTilt = 0.0;
    var tailWag = 0.0;
    var raisedPaw = false;
    var flower = false;
    var sitting = false;
    switch (cue) {
      case PetInteractionCue.invite:
        y += _wave * 3;
        tailWag = _bounce * .75;
        raisedPaw = true;
      case PetInteractionCue.think:
        y += _wave * 2;
        headTilt = -.16 + _wave * .05;
        tailWag = _wave * .12;
      case PetInteractionCue.correct:
        y -= math.max(0, _bounce) * 32;
        bodyScale = 1 + math.max(0, _bounce) * .08;
        tailWag = _wave * 1.05;
      case PetInteractionCue.incorrect:
        y += math.max(0, _bounce) * 5;
        headTilt = _wave * .16;
        tailWag = _wave * .24;
      case PetInteractionCue.complete:
        x = 128 + progress * 42;
        y -= math.max(0, _bounce) * 15;
        tailWag = _wave * .9;
        flower = true;
      case PetInteractionCue.repeat:
        x += _wave * 15;
        y += _bounce.abs() * 3;
        tailWag = _wave * .45;
      case PetInteractionCue.tailWag:
        tailWag = _wave * 1.25;
        y += _wave * 2;
      case PetInteractionCue.flowerGift:
        x = 134 + progress * 28;
        tailWag = _wave * .72;
        flower = true;
      case PetInteractionCue.studyTogether:
        x = 164;
        y = 166;
        sitting = true;
        headTilt = -.08;
        tailWag = _wave * .22;
      case PetInteractionCue.lamp:
      case PetInteractionCue.bookcase:
      case PetInteractionCue.flowerPot:
        x = 138;
        tailWag = _wave * .55;
      case PetInteractionCue.lessonCelebration:
        x = 106 + progress * 74;
        y -= math.max(0, _bounce) * 22;
        tailWag = _wave * .9;
      case PetInteractionCue.unitCelebration:
        y -= math.max(0, _bounce) * 18;
        bodyScale = 1.08;
        tailWag = _wave * 1.1;
    }

    canvas.save();
    canvas.translate(x, y);
    canvas.scale(bodyScale);
    final coat = Paint()..color = appearance.coat;
    final marking = Paint()..color = appearance.marking;
    final dark = Paint()
      ..color = const Color(0xff3d2b1f)
      ..strokeCap = StrokeCap.round;
    final muzzle = Paint()..color = appearance.muzzle;

    final tailAngle = -0.72 + tailWag;
    canvas.save();
    canvas.translate(-39, -7);
    canvas.rotate(tailAngle);
    canvas.drawLine(
      const Offset(0, 0),
      const Offset(-40, -4),
      marking..strokeWidth = 15,
    );
    canvas.drawCircle(const Offset(-42, -4), 8, marking);
    canvas.restore();

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, sitting ? -1 : -8),
        width: 86,
        height: sitting ? 54 : 61,
      ),
      coat,
    );
    final legLift =
        (cue == PetInteractionCue.repeat || cue == PetInteractionCue.complete)
        ? _bounce * 8
        : 0.0;
    paintLegacyLeg(canvas, const Offset(-25, 17), legLift, marking);
    paintLegacyLeg(canvas, const Offset(25, 17), -legLift, marking);
    if (raisedPaw) {
      canvas.save();
      canvas.translate(33, 2);
      canvas.rotate(-.72 + _wave * .22);
      canvas.drawLine(
        Offset.zero,
        const Offset(10, -33),
        coat
          ..strokeWidth = 16
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(const Offset(11, -34), 9, muzzle);
      canvas.restore();
    }

    canvas.save();
    canvas.translate(3, -54);
    canvas.rotate(headTilt);
    paintLegacyEar(
      canvas,
      const Offset(-23, -7),
      -.34 + appearance.earDrop * .09,
      marking,
    );
    paintLegacyEar(
      canvas,
      const Offset(23, -7),
      .34 - appearance.earDrop * .09,
      marking,
    );
    canvas.drawCircle(Offset.zero, 42, coat);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 14), width: 54, height: 34),
      muzzle,
    );
    final blink = progress > .78 && progress < .86;
    paintLegacyEye(
      canvas,
      const Offset(-15, -4),
      dark,
      blink,
      cue == PetInteractionCue.correct ||
          cue == PetInteractionCue.unitCelebration,
    );
    paintLegacyEye(
      canvas,
      const Offset(15, -4),
      dark,
      blink,
      cue == PetInteractionCue.correct ||
          cue == PetInteractionCue.unitCelebration,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 11), width: 12, height: 8),
      dark,
    );
    canvas.drawArc(
      const Rect.fromLTWH(-9, 14, 18, 14),
      .2,
      math.pi - .4,
      false,
      dark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    if (decoration.color != 0) {
      canvas.drawArc(
        const Rect.fromLTWH(-28, 25, 56, 22),
        0,
        math.pi,
        false,
        Paint()
          ..color = Color(decoration.color)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6,
      );
    }
    if (flower) paintLegacyFlower(canvas, const Offset(23, 14));
    canvas.restore();
    canvas.restore();
  }

  void paintLegacyLeg(Canvas canvas, Offset origin, double lift, Paint paint) {
    canvas.drawLine(
      origin,
      Offset(origin.dx, origin.dy + 27 + lift),
      paint
        ..strokeWidth = 17
        ..strokeCap = StrokeCap.round,
    );
  }

  void paintLegacyEar(Canvas canvas, Offset origin, double angle, Paint paint) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(angle);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 25, height: 48),
      paint,
    );
    canvas.restore();
  }

  void paintLegacyEye(
    Canvas canvas,
    Offset origin,
    Paint dark,
    bool blink,
    bool star,
  ) {
    if (blink) {
      canvas.drawLine(
        Offset(origin.dx - 7, origin.dy),
        Offset(origin.dx + 7, origin.dy),
        dark..strokeWidth = 2.7,
      );
      return;
    }
    if (star) {
      final path = Path();
      for (var index = 0; index < 10; index++) {
        final angle = -math.pi / 2 + index * math.pi / 5;
        final radius = index.isEven ? 7.0 : 3.0;
        final point =
            origin + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path..close(), dark);
      return;
    }
    canvas.drawCircle(origin, 5.5, dark);
    canvas.drawCircle(
      Offset(origin.dx - 1.7, origin.dy - 1.7),
      1.5,
      Paint()..color = Colors.white,
    );
  }

  void paintLegacyFlower(Canvas canvas, Offset center) {
    final petals = Paint()..color = const Color(0xffff6b9c);
    for (var index = 0; index < 5; index++) {
      final angle = index * math.pi * 2 / 5;
      canvas.drawCircle(
        center + Offset(math.cos(angle) * 5, math.sin(angle) * 5),
        5,
        petals,
      );
    }
    canvas.drawCircle(center, 3.5, Paint()..color = const Color(0xffffd166));
    canvas.drawLine(
      Offset(center.dx + 4, center.dy + 4),
      Offset(center.dx + 13, center.dy + 19),
      Paint()
        ..color = const Color(0xff4d9c5a)
        ..strokeWidth = 2.5,
    );
  }

  void _paintCaption(Canvas canvas) {
    final text = switch (cue) {
      PetInteractionCue.invite => '一起学三题吧！',
      PetInteractionCue.think => '慢慢想，不着急',
      PetInteractionCue.correct => '答对啦！',
      PetInteractionCue.incorrect => '再试一次，你可以的',
      PetInteractionCue.complete => '送你一朵小花！',
      PetInteractionCue.repeat => '我在书桌旁等你',
      PetInteractionCue.tailWag => '摇摇尾巴，真开心！',
      PetInteractionCue.flowerGift => '小花送给认真朗读的你',
      PetInteractionCue.studyTogether => '陪你一起读一读',
      PetInteractionCue.lamp => '台灯亮起来啦！',
      PetInteractionCue.bookcase => '又收好一本书',
      PetInteractionCue.flowerPot => '小花开啦！',
      PetInteractionCue.lessonCelebration => '课文目标完成！',
      PetInteractionCue.unitCelebration => '单元通关，礼花绽放！',
    };
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: Color(0xff4d3329),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 300);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: const Offset(180, 27),
        width: painter.width + 28,
        height: 34,
      ),
      const Radius.circular(17),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = Colors.white.withValues(alpha: .86),
    );
    painter.paint(canvas, Offset(180 - painter.width / 2, 18));
  }

  @override
  bool shouldRepaint(covariant _PetInteractionPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.cue != cue ||
      oldDelegate.foreground != foreground ||
      oldDelegate.appearance != appearance ||
      oldDelegate.decoration != decoration;
}
