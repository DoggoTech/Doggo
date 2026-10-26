import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/sitter_summary.dart';
import '../bookings/bookings_providers.dart';

/// Lo que le falta a un cuidador para salir en el mapa (además de estar
/// aprobado): las mismas condiciones que usa el repositorio para mostrarlo.
List<String> missingForMap(SitterSummary s) => [
  if (s.services.isEmpty) 'activar al menos un servicio con su precio',
  if (!s.locationConfirmed) 'definir tu zona de servicio',
];

/// Aviso arriba del panel del cuidador cuando todavía no sale en el mapa.
/// Sin él, un cuidador aprobado no sabía por qué los dueños no lo veían.
class MapVisibilityBanner extends ConsumerWidget {
  const MapVisibilityBanner({
    super.key,
    this.where = 'en la pestaña Servicios',
  });

  /// Dónde se completa lo que falta ("en esta página", "en la pestaña…").
  final String where;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sitter = ref.watch(mySitterProfileProvider).value;
    if (sitter == null) return const SizedBox.shrink();
    final missing = missingForMap(sitter);
    if (missing.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_off_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              container: true,
              child: Text(
                'Aún no sales en el mapa. Te falta ${missing.join(' y ')} ($where).',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
