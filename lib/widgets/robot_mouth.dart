import 'dart:math';
import 'package:flutter/material.dart';
import '../models/bot_expression.dart';

class RobotMouth extends StatefulWidget {
  final bool isSpeaking;
  final BotExpression expression;
  const RobotMouth({super.key, this.isSpeaking = false, this.expression = BotExpression.idle});

  @override
  State<RobotMouth> createState() => _RobotMouthState();
}

class _RobotMouthState extends State<RobotMouth> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _barHeights = List.filled(15, 0.1);
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(() {
        if (widget.isSpeaking) {
          setState(() {
            for (int i = 0; i < _barHeights.length; i++) {
              _barHeights[i] = 0.2 + _random.nextDouble() * 0.8;
            }
          });
        } else if (_barHeights[0] != 0.1) {
          setState(() {
            for (int i = 0; i < _barHeights.length; i++) {
              _barHeights[i] = 0.1;
            }
          });
        }
      });
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determina o tipo de curvatura baseada no humor
    double curvatureFactor = 1.0; // Padrão: Sorriso
    
    final negativeMoods = [
      BotExpression.sad,
      BotExpression.frustrated,
      BotExpression.crying,
      BotExpression.angry,
      BotExpression.annoyed,
      BotExpression.sweating,
      BotExpression.dizzy
    ];

    if (negativeMoods.contains(widget.expression)) {
      curvatureFactor = -0.8; // Inverte para curvatura triste
    } else if (widget.expression == BotExpression.neutralClosed || 
               widget.expression == BotExpression.scanning) {
      curvatureFactor = 0.0; // Boca reta (neutra)
    }

    return SizedBox(
      height: 60,
      width: 150,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(_barHeights.length, (index) {
          double x = index / (_barHeights.length - 1); // 0.0 a 1.0
          double curveOffset = -20 * pow(x - 0.5, 2) * 4 * curvatureFactor;

          return Positioned(
            key: ValueKey("mouth_bar_$index"), // Key fixa para cada barra
            left: index * (150 / _barHeights.length),
            bottom: 30 - curveOffset, 
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 8,
              height: 40 * _barHeights[index],
              decoration: BoxDecoration(
                color: curvatureFactor < 0 ? Colors.orangeAccent : Colors.yellowAccent,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: curvatureFactor < 0 ? Colors.deepOrange : Colors.yellow.withOpacity(0.5),
                    blurRadius: 5,
                    spreadRadius: 1,
                  )
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
