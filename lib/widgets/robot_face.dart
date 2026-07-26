import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/bot_expression.dart';

class RobotFace extends StatelessWidget {
  final BotExpression expression;
  final double energy;

  const RobotFace({
    super.key,
    required this.expression,
    this.energy = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        );
      },
      child: CustomPaint(
        key: ValueKey(expression),
        size: const Size(300, 150),
        painter: ExpressionPainter(
          expression: expression,
          energy: energy,
        ),
      ),
    );
  }
}

class ExpressionPainter extends CustomPainter {
  final BotExpression expression;
  final double energy;

  ExpressionPainter({required this.expression, required this.energy});

  @override
  void paint(Canvas canvas, Size size) {
    final double spacing = 110;
    final Offset leftEyeCenter = Offset(size.width / 2 - spacing / 2, size.height / 2);
    final Offset rightEyeCenter = Offset(size.width / 2 + spacing / 2, size.height / 2);

    final cyanPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.8)
      ..style = PaintingStyle.fill;
    
    final glowPaint = Paint()
      ..color = Colors.cyan.withOpacity(0.3 * energy)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * energy);

    switch (expression) {
      case BotExpression.inLove:
        _drawHeart(canvas, leftEyeCenter, Colors.redAccent);
        _drawHeart(canvas, rightEyeCenter, Colors.redAccent, hasPinkGlow: true);
        break;
      case BotExpression.excited:
        _drawStar(canvas, leftEyeCenter, Colors.cyanAccent);
        _drawStar(canvas, rightEyeCenter, Colors.cyanAccent);
        break;
      case BotExpression.neutralClosed:
        _drawRect(canvas, leftEyeCenter, 60, 15, cyanPaint, glowPaint);
        _drawRect(canvas, rightEyeCenter, 60, 15, cyanPaint, glowPaint);
        break;
      case BotExpression.dizzy:
        _drawCircle(canvas, leftEyeCenter, 25, cyanPaint, glowPaint, hasShock: true);
        _drawCircle(canvas, rightEyeCenter, 25, cyanPaint, glowPaint);
        break;
      case BotExpression.greedy:
        _drawYen(canvas, leftEyeCenter);
        _drawYen(canvas, rightEyeCenter);
        break;
      case BotExpression.sleeping:
        _drawArc(canvas, leftEyeCenter, 50, 30, false, cyanPaint, glowPaint, hasBubbles: true);
        _drawArc(canvas, rightEyeCenter, 50, 30, false, cyanPaint, glowPaint);
        break;
      case BotExpression.puzzledLeft:
        _drawRect(canvas, leftEyeCenter, 60, 15, cyanPaint, glowPaint);
        _drawRect(canvas, rightEyeCenter, 60, 15, cyanPaint, glowPaint, hasQuestionMark: true);
        break;
      case BotExpression.sad:
        _drawSlantedRect(canvas, leftEyeCenter, 20, 50, -0.2, cyanPaint, glowPaint);
        _drawSlantedRect(canvas, rightEyeCenter, 20, 50, 0.2, cyanPaint, glowPaint);
        break;
      case BotExpression.happy:
        _drawArc(canvas, leftEyeCenter, 50, 40, true, cyanPaint, glowPaint);
        _drawArc(canvas, rightEyeCenter, 50, 40, true, cyanPaint, glowPaint);
        break;
      case BotExpression.suspicious:
        _drawRect(canvas, leftEyeCenter, 60, 10, cyanPaint, glowPaint);
        _drawRect(canvas, rightEyeCenter, 60, 10, cyanPaint, glowPaint);
        break;
      case BotExpression.winking:
        _drawRect(canvas, leftEyeCenter, 15, 40, cyanPaint, glowPaint);
        _drawChevron(canvas, rightEyeCenter, 40, true);
        break;
      case BotExpression.hypnotized:
        _drawSpiral(canvas, leftEyeCenter, 30, cyanPaint);
        _drawSpiral(canvas, rightEyeCenter, 30, cyanPaint);
        break;
      case BotExpression.frustrated:
        _drawChevron(canvas, leftEyeCenter, 40, false);
        _drawChevron(canvas, rightEyeCenter, 40, true);
        break;
      case BotExpression.crying:
        _drawCrying(canvas, leftEyeCenter, cyanPaint, glowPaint);
        _drawCrying(canvas, rightEyeCenter, cyanPaint, glowPaint);
        break;
      case BotExpression.sweating:
        _drawRect(canvas, leftEyeCenter, 60, 15, cyanPaint, glowPaint, hasSweat: true);
        _drawRect(canvas, rightEyeCenter, 60, 15, cyanPaint, glowPaint);
        break;
      case BotExpression.annoyed:
        _drawRect(canvas, leftEyeCenter, 60, 25, cyanPaint, glowPaint);
        _drawRect(canvas, rightEyeCenter, 60, 25, cyanPaint, glowPaint, hasStressBars: true);
        break;
      case BotExpression.angry:
        _drawAngry(canvas, leftEyeCenter, 50, cyanPaint, glowPaint);
        _drawAngry(canvas, rightEyeCenter, 50, cyanPaint, glowPaint);
        break;
      case BotExpression.blushing:
        _drawArc(canvas, leftEyeCenter, 50, 30, true, cyanPaint, glowPaint, hasBlush: true);
        _drawArc(canvas, rightEyeCenter, 50, 30, true, cyanPaint, glowPaint, hasBlush: true);
        break;
      case BotExpression.masked:
        _drawRect(canvas, leftEyeCenter, 15, 50, cyanPaint, glowPaint);
        _drawRect(canvas, rightEyeCenter, 15, 50, cyanPaint, glowPaint);
        break;
      case BotExpression.scanning:
        _drawRect(canvas, leftEyeCenter, 20, 80, cyanPaint, glowPaint);
        _drawRect(canvas, rightEyeCenter, 20, 80, cyanPaint, glowPaint);
        break;
      case BotExpression.pleased:
        _drawArc(canvas, leftEyeCenter, 60, 35, true, cyanPaint, glowPaint);
        _drawArc(canvas, rightEyeCenter, 60, 35, true, cyanPaint, glowPaint);
        break;
      case BotExpression.lookingDown:
        _drawRect(canvas, leftEyeCenter.translate(0, 30), 25, 50, cyanPaint, glowPaint);
        _drawRect(canvas, rightEyeCenter.translate(0, 30), 25, 50, cyanPaint, glowPaint);
        break;
      case BotExpression.lookingUp:
        _drawRect(canvas, leftEyeCenter.translate(0, -30), 25, 50, cyanPaint, glowPaint);
        _drawRect(canvas, rightEyeCenter.translate(0, -30), 25, 50, cyanPaint, glowPaint);
        break;
      case BotExpression.idle:
      default:
        _drawRect(canvas, leftEyeCenter, 30, 60, cyanPaint, glowPaint);
        _drawRect(canvas, rightEyeCenter, 30, 60, cyanPaint, glowPaint);
        break;
    }
  }

  void _drawRect(Canvas canvas, Offset center, double w, double h, Paint p, Paint glow, {bool hasQuestionMark = false, bool hasSweat = false, bool hasStressBars = false}) {
    Rect rect = Rect.fromCenter(center: center, width: w, height: h);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), glow);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), p);
    
    if (hasQuestionMark) {
      _drawText(canvas, center.translate(0, -30), "?", 24, Colors.cyanAccent);
    }
    if (hasSweat) {
      _drawSweat(canvas, center.translate(w/2, h/2));
    }
    if (hasStressBars) {
      for (int i=0; i<3; i++) {
        canvas.drawRect(Rect.fromLTWH(center.dx - 15 + i*15, center.dy - 30, 5, 10), Paint()..color = i == 1 ? Colors.red : Colors.cyanAccent);
      }
    }
  }

  void _drawSlantedRect(Canvas canvas, Offset center, double w, double h, double angle, Paint p, Paint glow) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    _drawRect(canvas, Offset.zero, w, h, p, glow);
    canvas.restore();
  }

  void _drawCircle(Canvas canvas, Offset center, double radius, Paint p, Paint glow, {bool hasShock = false}) {
    canvas.drawCircle(center, radius + 10, glow);
    canvas.drawCircle(center, radius, p);
    if (hasShock) {
      _drawStar(canvas, center.translate(-15, -20), Colors.yellow, size: 10);
    }
  }

  void _drawArc(Canvas canvas, Offset center, double w, double h, bool invert, Paint p, Paint glow, {bool hasBubbles = false, bool hasBlush = false}) {
    Rect rect = Rect.fromCenter(center: center, width: w, height: h);
    final path = Path();
    if (invert) {
      path.addArc(rect, math.pi, math.pi);
    } else {
      path.addArc(rect, 0, math.pi);
    }
    
    Paint strokePaint = Paint()
      ..color = p.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, glow..style = PaintingStyle.stroke..strokeWidth = 15);
    canvas.drawPath(path, strokePaint);

    if (hasBubbles) {
      canvas.drawCircle(center.translate(20, 20), 5, Paint()..color = Colors.cyan.withOpacity(0.3));
    }
    if (hasBlush) {
      canvas.drawCircle(center.translate(0, 25), 10, Paint()..color = Colors.redAccent.withOpacity(0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }
  }

  void _drawHeart(Canvas canvas, Offset center, Color color, {bool hasPinkGlow = false}) {
    final path = Path();
    double s = 30;
    path.moveTo(center.dx, center.dy + s);
    path.quadraticBezierTo(center.dx - s, center.dy - s/2, center.dx, center.dy - s/3);
    path.quadraticBezierTo(center.dx + s, center.dy - s/2, center.dx, center.dy + s);

    if (hasPinkGlow) {
      canvas.drawPath(path, Paint()..color = Colors.pinkAccent.withOpacity(0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawStar(Canvas canvas, Offset center, Color color, {double size = 25}) {
    final path = Path();
    for (int i = 0; i < 4; i++) {
      double angle = i * math.pi / 2;
      path.moveTo(center.dx + math.cos(angle) * size, center.dy + math.sin(angle) * size);
      path.lineTo(center.dx + math.cos(angle + math.pi/4) * size/3, center.dy + math.sin(angle + math.pi/4) * size/3);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawChevron(Canvas canvas, Offset center, double size, bool left) {
    final path = Path();
    if (left) {
      path.moveTo(center.dx + size/2, center.dy - size/2);
      path.lineTo(center.dx - size/2, center.dy);
      path.lineTo(center.dx + size/2, center.dy + size/2);
    } else {
      path.moveTo(center.dx - size/2, center.dy - size/2);
      path.lineTo(center.dx + size/2, center.dy);
      path.lineTo(center.dx - size/2, center.dy + size/2);
    }
    canvas.drawPath(path, Paint()..color = Colors.cyanAccent..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round);
  }

  void _drawYen(Canvas canvas, Offset center) {
    _drawText(canvas, center, "¥", 40, Colors.cyanAccent);
    _drawStar(canvas, center.translate(25, -15), Colors.yellowAccent, size: 8);
  }

  void _drawSpiral(Canvas canvas, Offset center, double maxRadius, Paint p) {
    final path = Path();
    for (double i = 0; i < 10; i += 0.1) {
      double r = (i / 10) * maxRadius;
      double x = center.dx + r * math.cos(i * 3);
      double y = center.dy + r * math.sin(i * 3);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = p.color..style = PaintingStyle.stroke..strokeWidth = 4);
  }

  void _drawCrying(Canvas canvas, Offset center, Paint p, Paint glow) {
    _drawRect(canvas, center.translate(0, -20), 50, 15, p, glow);
    for (int i=0; i<3; i++) {
      canvas.drawLine(center.translate(-15 + i*15, -10), center.translate(-15 + i*15, 40), Paint()..color = Colors.blueAccent.withOpacity(0.6)..strokeWidth = 4);
    }
  }

  void _drawAngry(Canvas canvas, Offset center, double size, Paint p, Paint glow) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(center.dx - size, center.dy - size, size * 2, size * 2));
    canvas.drawCircle(center, size, p);
    final cutPath = Path()
      ..moveTo(center.dx - size, center.dy - size)
      ..lineTo(center.dx + size, center.dy - size/2)
      ..lineTo(center.dx + size, center.dy - size)
      ..close();
    canvas.drawPath(cutPath, Paint()..color = const Color(0xFF00050A));
    canvas.restore();
  }

  void _drawSweat(Canvas canvas, Offset pos) {
    final path = Path()
      ..moveTo(pos.dx, pos.dy)
      ..quadraticBezierTo(pos.dx + 10, pos.dy + 15, pos.dx, pos.dy + 25)
      ..quadraticBezierTo(pos.dx - 10, pos.dy + 15, pos.dx, pos.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.blueAccent);
  }

  void _drawText(Canvas canvas, Offset center, String text, double size, Color color) {
    TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout()..paint(canvas, center.translate(-size/3, -size/2));
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
