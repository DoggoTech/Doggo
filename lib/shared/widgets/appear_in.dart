import 'package:flutter/material.dart';

/// Aparece con un fundido y un leve desplazamiento hacia arriba la primera vez
/// que se construye (p. ej. una solicitud que llega en vivo). Respeta la
/// opción del sistema de reducir movimiento.
class AppearIn extends StatelessWidget {
  const AppearIn({super.key, required this.child});

  final Widget child;

  static const duration = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}
