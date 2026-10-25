import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Botón en forma de píldora (chips de filtro). Expone semántica de botón con
/// estado seleccionado, para lectores de pantalla y pruebas.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.icon,
    this.elevated = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final IconData? icon;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.text;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.primary : Colors.white,
        elevation: elevated ? 3 : 0,
        shadowColor: const Color(0x332B1D12),
        shape: StadiumBorder(
          side: elevated
              ? BorderSide.none
              : BorderSide(color: selected ? AppColors.primary : const Color(0x332B1D12)),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
