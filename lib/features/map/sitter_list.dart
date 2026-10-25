import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/service_type.dart';
import '../../data/models/sitter_summary.dart';
import 'map_state.dart';

/// Avatar con la foto del cuidador; si no carga, su inicial.
class SitterAvatar extends StatelessWidget {
  const SitterAvatar({super.key, required this.sitter, this.radius = 26});

  final SitterSummary sitter;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = Text(
      sitter.name.isEmpty ? '?' : sitter.name[0],
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        fontSize: radius * 0.8,
      ),
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary,
      child: sitter.avatarUrl == null
          ? initial
          : ClipOval(
              child: Image.network(
                sitter.avatarUrl!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => initial,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : initial,
              ),
            ),
    );
  }
}

class RatingText extends StatelessWidget {
  const RatingText(this.sitter, {super.key});

  final SitterSummary sitter;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
        );
    if (sitter.ratingAvg == null) {
      return Text('Nuevo', style: style?.copyWith(color: AppColors.success));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 16, color: AppColors.primary),
        const SizedBox(width: 2),
        Text('${formatRating(sitter.ratingAvg!)} (${sitter.ratingCount})', style: style),
      ],
    );
  }
}

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Verificado',
        child: Icon(Icons.verified_rounded, size: size, color: AppColors.success),
      );
}

/// Lista de cuidadores con encabezado, estados de carga/vacío/error.
/// El mismo widget sirve para el bottom sheet (celular) y el panel (escritorio).
class SitterList extends ConsumerWidget {
  const SitterList({
    super.key,
    required this.onFocus,
    this.controller,
    this.showHandle = false,
  });

  final void Function(SitterSummary) onFocus;
  final ScrollController? controller;
  final bool showHandle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(visibleSittersProvider);
    final filters = ref.watch(mapFiltersProvider);
    final selectedId = ref.watch(selectedSitterIdProvider);
    final location = ref.watch(locationProvider);
    final theme = Theme.of(context);

    Widget header(int? count) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHandle)
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0x332B1D12),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              Semantics(
                header: true,
                child: Text(
                  count == null
                      ? 'Cuidadores cerca'
                      : count == 1
                          ? '1 cuidador cerca'
                          : '$count cuidadores cerca',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                location.tracking
                    ? 'Distancia desde tu ubicación (en vivo)'
                    : location.point != null
                        ? 'Distancia desde tu ubicación'
                        : 'Distancia desde el centro de Bogotá',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        );

    return visible.when(
      loading: () => ListView(
        controller: controller,
        children: [
          header(null),
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
      error: (e, _) => ListView(
        controller: controller,
        children: [
          header(null),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const Text('No pudimos cargar los cuidadores.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(sittersProvider),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ],
      ),
      data: (views) {
        if (views.isEmpty) {
          return ListView(
            controller: controller,
            children: [
              header(0),
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const Icon(Icons.search_off_rounded, size: 48, color: AppColors.muted),
                    const SizedBox(height: 12),
                    Text(
                      'No hay cuidadores con esos filtros.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (!filters.isEmpty) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref.read(mapFiltersProvider.notifier).clear(),
                        child: const Text('Limpiar filtros'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        }
        return ListView.builder(
          controller: controller,
          itemCount: views.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return header(views.length);
            final v = views[i - 1];
            return _SitterTile(
              view: v,
              service: filters.service,
              selected: v.sitter.id == selectedId,
              onTap: () => onFocus(v.sitter),
            );
          },
        );
      },
    );
  }
}

class _SitterTile extends StatelessWidget {
  const _SitterTile({
    required this.view,
    required this.service,
    required this.selected,
    required this.onTap,
  });

  final SitterView view;
  final ServiceType? service;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = view.sitter;
    final theme = Theme.of(context);
    final shown = s.pinService(service);
    final price = s.pinPrice(service);
    return Semantics(
      button: true,
      selected: selected,
      onTap: onTap,
      label: '${s.name}, ${s.neighborhood}, a ${formatKm(view.distanceKm)}, '
          '${formatCop(price)} ${shown.unit}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              SitterAvatar(sitter: s),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.name,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (s.verified) ...[
                          const SizedBox(width: 4),
                          const VerifiedBadge(size: 16),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    RatingText(s),
                    Text(
                      '${s.neighborhood} · a ${formatKm(view.distanceKm)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCop(price),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    shown.unit,
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
