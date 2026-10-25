import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/service_type.dart';
import '../../data/models/sitter_summary.dart';
import '../../shared/widgets/pill.dart';
import 'filters_sheet.dart';
import 'map_state.dart';
import 'sitter_list.dart';
import 'sitter_pin.dart';

/// Ancho del contenido desde el cual la lista pasa de bottom sheet a panel lateral.
const _widePanelBreakpoint = 720.0;
const _sheetMin = 0.30;

/// Pantalla principal del dueño: mapa con pines de precio + lista de cuidadores.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapController();
  final _sheet = DraggableScrollableController();

  @override
  void dispose() {
    _map.dispose();
    _sheet.dispose();
    super.dispose();
  }

  void _focus(SitterSummary s) {
    ref.read(selectedSitterIdProvider.notifier).select(s.id);
    _map.move(s.location, math.max(_map.camera.zoom, 13));
    if (_sheet.isAttached) {
      _sheet.animateTo(
        _sheetMin,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  /// Botón "Mi ubicación", en tres estados:
  /// apagado → empieza a seguirte; siguiéndote → deja de seguir;
  /// siguiéndote pero moviste el mapa → vuelve a centrarse en ti.
  Future<void> _onLocationButton() async {
    final location = ref.read(locationProvider);
    final following = ref.read(followingProvider);
    final notifier = ref.read(locationProvider.notifier);

    if (location.tracking && following) {
      notifier.stop();
      ref.read(followingProvider.notifier).set(false);
      return;
    }
    if (location.tracking && location.point != null) {
      ref.read(followingProvider.notifier).set(true);
      _map.move(location.point!, math.max(_map.camera.zoom, 15));
      return;
    }

    final ok = await notifier.start();
    if (!mounted) return;
    if (ok) {
      ref.read(followingProvider.notifier).set(true);
      _map.move(ref.read(locationProvider).point!, 15);
    } else {
      _map.move(bogotaCenter, 11.5);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No pudimos obtener tu ubicación. Te mostramos Bogotá.'),
          ),
        );
    }
  }

  /// El mapa se mueve con el usuario mientras no lo haya arrastrado.
  void _onLocationChanged(LocationState? previous, LocationState next) {
    if (next.point == null || !next.tracking) return;
    if (previous?.point == next.point) return;
    if (!ref.read(followingProvider)) return;
    _map.move(next.point!, _map.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(locationProvider, _onLocationChanged);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _widePanelBreakpoint;
        if (wide) {
          return Row(
            children: [
              Expanded(child: _MapArea(map: _map, onFocus: _focus, onLocate: _onLocationButton)),
              Container(
                width: 400,
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  border: Border(left: BorderSide(color: Color(0x1A2B1D12))),
                ),
                child: SitterList(onFocus: _focus),
              ),
            ],
          );
        }
        return Stack(
          children: [
            // El mapa termina donde empieza la hoja: así los pines y la
            // atribución de OpenStreetMap nunca quedan tapados.
            Positioned.fill(
              bottom: constraints.maxHeight * _sheetMin,
              child: _MapArea(map: _map, onFocus: _focus, onLocate: _onLocationButton),
            ),
            DraggableScrollableSheet(
              controller: _sheet,
              initialChildSize: _sheetMin,
              minChildSize: _sheetMin,
              maxChildSize: 0.92,
              snap: true,
              snapSizes: const [_sheetMin, 0.6, 0.92],
              builder: (context, scrollController) => DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(color: Color(0x332B1D12), blurRadius: 20, offset: Offset(0, -4)),
                  ],
                ),
                child: SitterList(
                  controller: scrollController,
                  showHandle: true,
                  onFocus: _focus,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MapArea extends ConsumerWidget {
  const _MapArea({required this.map, required this.onFocus, required this.onLocate});

  final MapController map;
  final void Function(SitterSummary) onFocus;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(visibleSittersProvider).value ?? const <SitterView>[];
    final filters = ref.watch(mapFiltersProvider);
    final selectedId = ref.watch(selectedSitterIdProvider);
    final userLocation = ref.watch(userLocationProvider);

    SitterView? selected;
    for (final v in visible) {
      if (v.sitter.id == selectedId) selected = v;
    }

    // El seleccionado va al final para quedar encima de los demás pines.
    final ordered = [
      ...visible.where((v) => v.sitter.id != selectedId),
      ...visible.where((v) => v.sitter.id == selectedId),
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: map,
            options: MapOptions(
              // Encuadra la zona donde están los cuidadores de Bogotá.
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds(const LatLng(4.585, -74.16), const LatLng(4.745, -74.03)),
                padding: const EdgeInsets.fromLTRB(40, 100, 40, 60),
              ),
              minZoom: 9,
              maxZoom: 18,
              backgroundColor: const Color(0xFFEFE6D8),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: (_, _) => ref.read(selectedSitterIdProvider.notifier).select(null),
              onPositionChanged: (_, hasGesture) {
                // Arrastrar o hacer zoom con el dedo/mouse deja de seguirte.
                if (hasGesture && ref.read(followingProvider)) {
                  ref.read(followingProvider.notifier).set(false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.doggo',
              ),
              MarkerLayer(
                alignment: Alignment.topCenter,
                markers: [
                  if (userLocation != null)
                    Marker(
                      point: userLocation,
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      child: Semantics(
                        label: 'Tu ubicación',
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2F80ED),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(color: Color(0x55000000), blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                    ),
                  for (final v in ordered)
                    Marker(
                      point: v.sitter.location,
                      width: SitterPin.width,
                      height: SitterPin.height,
                      child: SitterPin(
                        name: v.sitter.name,
                        price: v.sitter.pinPrice(filters.service),
                        selected: v.sitter.id == selectedId,
                        onTap: () => onFocus(v.sitter),
                      ),
                    ),
                ],
              ),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
                backgroundColor: Color(0xCCFFFFFF),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  _FilterBar(filters: filters),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: selected == null
                        ? const SizedBox.shrink()
                        : _SelectedCard(
                            key: ValueKey(selected.sitter.id),
                            view: selected,
                            service: filters.service,
                            onClose: () =>
                                ref.read(selectedSitterIdProvider.notifier).select(null),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 28,
          child: _LocationButton(onPressed: onLocate),
        ),
      ],
    );
  }
}

class _LocationButton extends ConsumerWidget {
  const _LocationButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracking = ref.watch(locationProvider).tracking;
    final following = ref.watch(followingProvider);

    final String label;
    final IconData icon;
    final Color background;
    final Color foreground;
    if (tracking && following) {
      label = 'Dejar de seguir mi ubicación';
      icon = Icons.my_location_rounded;
      background = AppColors.primary;
      foreground = Colors.white;
    } else if (tracking) {
      label = 'Volver a mi ubicación';
      icon = Icons.my_location_rounded;
      background = Colors.white;
      foreground = AppColors.primary;
    } else {
      label = 'Mi ubicación';
      icon = Icons.location_searching_rounded;
      background = Colors.white;
      foreground = AppColors.primary;
    }

    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: Material(
        color: background,
        elevation: 4,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Icon(icon, color: foreground),
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filters});

  final MapFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(mapFiltersProvider.notifier);
    final advanced = filters.advancedCount;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Pill(
            icon: Icons.tune_rounded,
            label: advanced == 0 ? 'Filtros' : 'Filtros ($advanced)',
            selected: advanced > 0,
            onTap: () => showFiltersSheet(context),
          ),
          const SizedBox(width: 8),
          Pill(
            label: 'Todos',
            selected: filters.service == null,
            onTap: () => notifier.setService(null),
          ),
          for (final type in ServiceType.values) ...[
            const SizedBox(width: 8),
            Pill(
              label: type.label,
              selected: filters.service == type,
              onTap: () => notifier.setService(filters.service == type ? null : type),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectedCard extends StatelessWidget {
  const _SelectedCard({
    super.key,
    required this.view,
    required this.service,
    required this.onClose,
  });

  final SitterView view;
  final ServiceType? service;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = view.sitter;
    final theme = Theme.of(context);
    final shown = s.pinService(service);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          SitterAvatar(sitter: s, radius: 24),
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
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (s.verified) ...[
                      const SizedBox(width: 4),
                      const VerifiedBadge(size: 16),
                    ],
                  ],
                ),
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
                formatCop(s.pinPrice(service)),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900, color: AppColors.primary),
              ),
              Text(shown.unit, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
            ],
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
