import 'dart:math';
import 'package:flutter/material.dart';

class RobotEyes extends StatefulWidget {
  final double energy;
  final bool isAlert;

  const RobotEyes({
    super.key,
    this.energy = 1.0,
    this.isAlert = false,
  });

  @override
  State<RobotEyes> createState() => _RobotEyesState();
}

class _RobotEyesState extends State<RobotEyes> with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _startBlinkLoop();
  }

  void _startBlinkLoop() async {
    while (mounted) {
      await Future.delayed(Duration(seconds: 2 + Random().nextInt(5)));
      if (mounted) {
        await _blinkController.forward();
        await _blinkController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blinkController,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(300, 150),
          painter: EyePainter(
            blinkProgress: _blinkController.value,
            energy: widget.energy,
            isAlert: widget.isAlert,
          ),
        );
      },
    );
  }
}

class EyePainter extends CustomPainter {
  final double blinkProgress;
  final double energy;
  final bool isAlert;

  EyePainter({
    required this.blinkProgress,
    required this.energy,
    required this.isAlert,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cyanPaint = Paint()
      ..color = isAlert ? Colors.redAccent : Colors.cyan.withOpacity(0.5 + (0.5 * energy))
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * energy);

    final eyeColor = isAlert ? Colors.red : Colors.cyanAccent;
    final whitePaint = Paint()
      ..color = eyeColor
      ..style = PaintingStyle.fill;

    double eyeWidth = 60;
    double eyeHeight = 60 * (1 - blinkProgress);
    double spacing = 100;

    // Left Eye
    _drawEye(canvas, size.width / 2 - spacing / 2, size.height / 2, eyeWidth, eyeHeight, cyanPaint, whitePaint);
    
    // Right Eye
    _drawEye(canvas, size.width / 2 + spacing / 2, size.height / 2, eyeWidth, eyeHeight, cyanPaint, whitePaint);
  }

  void _drawEye(Canvas canvas, double x, double y, double width, double height, Paint glow, Paint eye) {
    if (height < 2) height = 2; // Keep a tiny sliver visible when "closed"
    
    Rect rect = Rect.fromCenter(center: Offset(x, y), width: width, height: height);
    canvas.drawOval(rect.inflate(10 * energy), glow);
    canvas.drawOval(rect, eye);
  }

  @override
  bool shouldRepaint(covariant EyePainter oldDelegate) {
    return oldDelegate.blinkProgress != blinkProgress || 
           oldDelegate.energy != energy || 
           oldDelegate.isAlert != isAlert;
  }
}
