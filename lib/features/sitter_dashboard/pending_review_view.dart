import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Pantalla del cuidador nuevo mientras un admin no lo aprueba.
class PendingReviewView extends StatelessWidget {
  const PendingReviewView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget step(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        const Icon(
          Icons.hourglass_top_rounded,
          size: 72,
          color: AppColors.primary,
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          container: true,
          child: Text(
            'Tu perfil está en revisión',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Un administrador de Doggo revisará tu perfil. Mientras tanto no apareces '
          'en el mapa ni puedes recibir reservas.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            boxShadow: AppTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mientras tanto',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              step(
                Icons.sell_rounded,
                'Activa tus servicios y pon tus precios en la pestaña Servicios.',
              ),
              step(
                Icons.calendar_month_rounded,
                'Define en qué días y horas atiendes.',
              ),
              step(
                Icons.verified_user_rounded,
                'Un admin revisará tu documento y selfie; al aprobarte sales con la insignia "Verificado".',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
