import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../shared/widgets/pill.dart';
import 'map_state.dart';

const _priceOptions = <int?>[null, 30000, 50000, 100000];
const _distanceOptions = <int?>[null, 3, 5, 8];
const _ratingOptions = <double?>[null, 4.0, 4.5];

Future<void> showFiltersSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const _FiltersSheet(),
  );
}

class _FiltersSheet extends ConsumerWidget {
  const _FiltersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(mapFiltersProvider);
    final notifier = ref.read(mapFiltersProvider.notifier);
    final count = ref.watch(visibleSittersProvider).value?.length;
    final theme = Theme.of(context);

    Widget section(String title, List<Widget> pills) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: pills),
            ],
          ),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Filtros',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            section('Precio máximo', [
              for (final v in _priceOptions)
                Pill(
                  elevated: false,
                  label: v == null ? 'Cualquier precio' : 'Hasta ${formatCop(v)}',
                  selected: filters.maxPrice == v,
                  onTap: () => notifier.setMaxPrice(v),
                ),
            ]),
            section('Distancia máxima', [
              for (final v in _distanceOptions)
                Pill(
                  elevated: false,
                  label: v == null ? 'Cualquier distancia' : 'Hasta $v km',
                  selected: filters.maxDistanceKm == v,
                  onTap: () => notifier.setMaxDistanceKm(v),
                ),
            ]),
            section('Calificación mínima', [
              for (final v in _ratingOptions)
                Pill(
                  elevated: false,
                  label: v == null ? 'Cualquier calificación' : '${formatRating(v)} o más',
                  selected: filters.minRating == v,
                  onTap: () => notifier.setMinRating(v),
                ),
            ]),
            Row(
              children: [
                TextButton(
                  onPressed: filters.advancedCount == 0
                      ? null
                      : () {
                          notifier.setMaxPrice(null);
                          notifier.setMaxDistanceKm(null);
                          notifier.setMinRating(null);
                        },
                  child: const Text('Limpiar'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      count == null
                          ? 'Listo'
                          : count == 1
                              ? 'Ver 1 cuidador'
                              : 'Ver $count cuidadores',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
