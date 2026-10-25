import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Lo que se muestra cuando algo no carga: un mensaje claro (nunca el error
/// técnico) y un botón para reintentar.
class ErrorState extends StatelessWidget {
  const ErrorState(this.message, {super.key, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: AppColors.muted,
            ),
            const SizedBox(height: 12),
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Revisa tu conexión e inténtalo de nuevo.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
