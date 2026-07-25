import 'package:flutter/material.dart';

class StatusPanel extends StatelessWidget {
  final double cognitiveLoad;
  final String homeostaticMode;
  final String attentionFocus;

  const StatusPanel({
    super.key,
    required this.cognitiveLoad,
    required this.homeostaticMode,
    required this.attentionFocus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyan.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusItem("Carga Cognitiva", "${(cognitiveLoad * 100).toStringAsFixed(1)}%", Colors.cyan),
          const SizedBox(height: 8),
          _buildStatusItem("Modo Homeostático", homeostaticMode, _getModeColor(homeostaticMode)),
          const SizedBox(height: 8),
          _buildStatusItem("Foco de Atenção", attentionFocus, Colors.yellowAccent),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, letterSpacing: 1.2),
        ),
        Text(
          value,
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Color _getModeColor(String mode) {
    switch (mode.toLowerCase()) {
      case 'equilibrado': return Colors.greenAccent;
      case 'protetor': return Colors.orangeAccent;
      case 'regenerativo': return Colors.blueAccent;
      default: return Colors.white;
    }
  }
}
