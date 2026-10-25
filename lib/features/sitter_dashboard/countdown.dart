import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';

/// "Responde en 1 h 42 min", actualizado cada pocos segundos.
class ResponseCountdown extends StatefulWidget {
  const ResponseCountdown({super.key, required this.deadline});

  final DateTime deadline;

  @override
  State<ResponseCountdown> createState() => _ResponseCountdownState();
}

class _ResponseCountdownState extends State<ResponseCountdown> {
  late final Timer _timer = Timer.periodic(
    const Duration(seconds: 10),
    (_) => setState(() {}),
  );

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.deadline.difference(DateTime.now());
    final urgent = left < const Duration(minutes: 30);
    final text = left.isNegative
        ? 'El plazo para responder venció'
        : 'Responde en ${formatRemaining(left)}';
    return Semantics(
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 18,
            color: urgent ? AppColors.error : AppColors.primary,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: urgent ? AppColors.error : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
