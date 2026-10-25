import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';

/// Pin del mapa: burbuja con el precio y una punta que señala la ubicación.
class SitterPin extends StatelessWidget {
  const SitterPin({
    super.key,
    required this.name,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  static const width = 88.0;
  static const height = 52.0;

  final String name;
  final int price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.text : AppColors.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Cuidador $name, ${formatCop(price)}',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3)),
                ],
              ),
              child: Text(
                formatCop(price),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            CustomPaint(size: const Size(14, 8), painter: _Tip(color)),
          ],
        ),
      ),
    );
  }
}

class _Tip extends CustomPainter {
  _Tip(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Tip old) => old.color != color;
}
