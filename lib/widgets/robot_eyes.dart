// robot_eyes.dart
import 'dart:math';
import 'package:flutter/material.dart';

class RobotEyes extends StatefulWidget {
  final double energy;
  final bool isAlert;
  final double cognitiveLoad;
  final String attentionFocus;

  const RobotEyes({
    super.key,
    this.energy = 1.0,
    this.isAlert = false,
    this.cognitiveLoad = 0.0,
    this.attentionFocus = "",
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
      duration: const Duration(milliseconds: 150),
    );
    _startBlinkLoop();
  }

  void _startBlinkLoop() async {
    while (mounted) {
      await Future.delayed(Duration(seconds: 3 + Random().nextInt(4)));
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
            cognitiveLoad: widget.cognitiveLoad,
            attentionFocus: widget.attentionFocus,
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
  final double cognitiveLoad;
  final String attentionFocus;

  EyePainter({
    required this.blinkProgress,
    required this.energy,
    required this.isAlert,
    required this.cognitiveLoad,
    required this.attentionFocus,

  });

  @override
  void paint(Canvas canvas, Size size) {
    final Random random = Random();

    // --- Efeito de Tremor (Jitter) ---
    // Se a carga cognitiva for > 80%, os olhos tremem levemente
    double jitterX = 0;
    double jitterY = 0;
    if (cognitiveLoad > 0.8) {
      jitterX = (random.nextDouble() - 0.5) * 4.0;
      jitterY = (random.nextDouble() - 0.5) * 4.0;
    }

    // --- Pincéis ---
    final glowPaint = Paint()
      ..color = isAlert ? Colors.redAccent : Colors.cyan.withOpacity(0.3 + (0.4 * energy))
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * energy);

    final baseEyePaint = Paint()
      ..color = isAlert ? Colors.red : Colors.cyanAccent
      ..style = PaintingStyle.fill;

    final pupilPaint = Paint()
      ..color = const Color(0xFF8A2BE2) // Violeta (BlueViolet)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    // --- Geometria do Olho ---
    double eyeWidth = 65;
    // Efeito Sleepy: O olho abre menos se a energia estiver baixa
    double maxOpenHeight = 60 * (0.5 + (0.5 * energy));
    double eyeHeight = maxOpenHeight * (1 - blinkProgress);
    double spacing = 110;

    // --- Movimento da Pupila ---
    // Move a pupila baseado no texto de atenção (gera um deslocamento "orgânico")
    double pupilOffsetX = (attentionFocus.length % 10 - 5) * 2.0;
    double pupilOffsetY = (attentionFocus.hashCode % 6 - 3) * 1.5;

    // Desenha Olho Esquerdo
    _drawCompleteEye(
        canvas,
        size.width / 2 - spacing / 2 + jitterX,
        size.height / 2 + jitterY,
        eyeWidth, eyeHeight, pupilOffsetX, pupilOffsetY,
        glowPaint, baseEyePaint, pupilPaint
    );

    // Desenha Olho Direito
    _drawCompleteEye(
        canvas,
        size.width / 2 + spacing / 2 + jitterX,
        size.height / 2 + jitterY,
        eyeWidth, eyeHeight, pupilOffsetX, pupilOffsetY,
        glowPaint, baseEyePaint, pupilPaint
    );
  }

  void _drawCompleteEye(
      Canvas canvas, double x, double y,
      double w, double h, double pX, double pY,
      Paint glow, Paint base, Paint pupil
      ) {
    if (h < 3) h = 3; // Mantém um "fio" de luz quando pisca

    Rect rect = Rect.fromCenter(center: Offset(x, y), width: w, height: h);

    // 1. Brilho externo (Glow)
    canvas.drawOval(rect.inflate(8 * energy), glow);

    // 2. Base do olho (Ciano/Alerta)
    canvas.drawOval(rect, base);

    // 3. Pupila Violeta (Só aparece se o olho estiver aberto o suficiente)
    if (h > 20) {
      double pupilSize = 18 * energy;
      // A pupila fica dentro do limite do olho
      canvas.drawCircle(Offset(x + pX, y + pY), pupilSize / 2, pupil);

      // Brilho da pupila (reflexo branco minúsculo)
      canvas.drawCircle(Offset(x + pX - 3, y + pY - 3), 2, Paint()..color = Colors.white.withOpacity(0.8));
    }
  }

  @override
  bool shouldRepaint(covariant EyePainter oldDelegate) {
    // Repinta se qualquer estado mudar ou se houver tremor (carga alta)
    return oldDelegate.blinkProgress != blinkProgress ||
        oldDelegate.energy != energy ||
        oldDelegate.isAlert != isAlert ||
        oldDelegate.attentionFocus != attentionFocus ||
        cognitiveLoad > 0.8;
  }
}
