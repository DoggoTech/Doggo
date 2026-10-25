import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/sitter_summary.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../bookings/bookings_providers.dart';
import '../map/map_state.dart';

/// Zona de servicio: ubicación (tocando el mapa o con el GPS), barrio y radio.
class ServiceAreaCard extends ConsumerStatefulWidget {
  const ServiceAreaCard({super.key, required this.sitter});

  final SitterSummary sitter;

  @override
  ConsumerState<ServiceAreaCard> createState() => _ServiceAreaCardState();
}

class _ServiceAreaCardState extends ConsumerState<ServiceAreaCard> {
  final _map = MapController();
  late LatLng? _point = widget.sitter.locationConfirmed
      ? widget.sitter.location
      : null;
  late final _neighborhood = TextEditingController(
    text: widget.sitter.locationConfirmed ? widget.sitter.neighborhood : '',
  );
  late int _radius = widget.sitter.radiusKm.clamp(1, 20);
  String? _error;
  bool _locating = false;

  @override
  void dispose() {
    _map.dispose();
    _neighborhood.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception();
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final point = LatLng(p.latitude, p.longitude);
      setState(() => _point = point);
      _map.move(point, 15);
    } catch (_) {
      setState(
        () => _error =
            'No pudimos obtener tu ubicación. Toca el mapa para marcarla.',
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_point == null) {
      setState(
        () =>
            _error = 'Marca tu ubicación en el mapa o usa tu ubicación actual.',
      );
      return;
    }
    try {
      await ref
          .read(repositoryProvider)
          .saveMyServiceArea(
            exact: _point!,
            neighborhood: _neighborhood.text,
            radiusKm: _radius,
          );
      ref.invalidate(mySitterProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Zona guardada')));
      }
    } on ValidationFailure catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            child: Text(
              'Toca el mapa para marcar dónde atiendes. En el mapa público se mostrará una ubicación '
              'aproximada (a 200–300 m) para proteger tu dirección.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 220,
              child: Semantics(
                container: true,
                label: 'Mapa para marcar tu zona',
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _point ?? bogotaCenter,
                    initialZoom: _point == null ? 11.5 : 14,
                    backgroundColor: const Color(0xFFEFE6D8),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    onTap: (_, point) => setState(() => _point = point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'app.doggo',
                    ),
                    if (_point != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _point!,
                            width: 40,
                            height: 40,
                            alignment: Alignment.topCenter,
                            child: Semantics(
                              label: 'Tu zona marcada',
                              child: const Icon(
                                Icons.location_pin,
                                size: 40,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SimpleAttributionWidget(
                      source: Text('OpenStreetMap contributors'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _locating ? null : _useMyLocation,
            icon: const Icon(Icons.my_location_rounded),
            label: Text(_locating ? 'Buscando…' : 'Usar mi ubicación actual'),
          ),
          const SizedBox(height: 12),
          // Nodo propio: si no, el campo absorbe al resto de la tarjeta en el
          // árbol de accesibilidad y su área cubre también el mapa.
          Semantics(
            container: true,
            child: TextField(
              controller: _neighborhood,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Barrio'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  container: true,
                  child: Text(
                    'Radio de servicio',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ),
              _Step(
                label: 'Menos radio',
                icon: Icons.remove_rounded,
                onPressed: _radius > 1 ? () => setState(() => _radius--) : null,
              ),
              Semantics(
                container: true,
                label: 'Radio: $_radius km',
                excludeSemantics: true,
                child: SizedBox(
                  width: 64,
                  child: Text(
                    '$_radius km',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              _Step(
                label: 'Más radio',
                icon: Icons.add_rounded,
                onPressed: _radius < 20
                    ? () => setState(() => _radius++)
                    : null,
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _save, child: const Text('Guardar zona')),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onPressed != null,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: IconButton.filledTonal(onPressed: onPressed, icon: Icon(icon)),
  );
}
