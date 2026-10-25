import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/booking.dart';
import 'bookings_providers.dart';

/// Teléfono y dirección de la contraparte. Solo con la reserva aceptada.
class ContactBox extends ConsumerWidget {
  const ContactBox({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final contact = ref.watch(
      counterpartContactProvider((id: booking.id, status: booking.status)),
    );
    return contact.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const SizedBox.shrink(),
      data: (c) {
        if (c == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Semantics(
            container: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contacto de ${c.name}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text('Teléfono: ${c.phone ?? 'no registrado'}'),
                Text('Dirección: ${c.address ?? 'no registrada'}'),
                const SizedBox(height: 4),
                Text(
                  'No pagues ni coordines pagos por fuera de Doggo.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
