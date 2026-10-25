import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/service_type.dart';
import '../../data/models/sitter_summary.dart';
import 'sitter_pin.dart';

/// Desde este zoom ya no se agrupa: los pines se ven sueltos aunque se rocen.
const noClusterZoom = 17.0;

/// Agrupa los cuidadores cuyos pines se taparían en pantalla. [toScreen]
/// proyecta cada ubicación a píxeles; [keepApart] (el seleccionado) nunca se
/// agrupa. Cada grupo toma como ancla al primero y suma a los que caen a
/// menos de [dx] × [dy] píxeles de él.
List<List<SitterSummary>> groupOverlapping(
  List<SitterSummary> sitters,
  Offset Function(LatLng) toScreen, {
  String? keepApart,
  double dx = 76,
  double dy = 36,
}) {
  final points = {for (final s in sitters) s.id: toScreen(s.location)};
  final used = <String>{};
  final groups = <List<SitterSummary>>[];
  for (final anchor in sitters) {
    if (used.contains(anchor.id)) continue;
    used.add(anchor.id);
    final group = [anchor];
    if (anchor.id != keepApart) {
      final a = points[anchor.id]!;
      for (final other in sitters) {
        if (used.contains(other.id) || other.id == keepApart) continue;
        final b = points[other.id]!;
        if ((a.dx - b.dx).abs() < dx && (a.dy - b.dy).abs() < dy) {
          group.add(other);
          used.add(other.id);
        }
      }
    }
    groups.add(group);
  }
  return groups;
}

/// Pines de cuidadores. Se agrupan los que se tapan; tocar un grupo acerca el
/// mapa hasta separarlos. Debe ir dentro de `FlutterMap` (lee su cámara).
class SitterMarkerLayer extends StatelessWidget {
  const SitterMarkerLayer({
    super.key,
    required this.sitters,
    required this.selectedId,
    required this.service,
    required this.onFocus,
    required this.onZoomTo,
  });

  final List<SitterSummary> sitters;
  final String? selectedId;
  final ServiceType? service;
  final void Function(SitterSummary) onFocus;
  final void Function(List<SitterSummary>) onZoomTo;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final groups = camera.zoom >= noClusterZoom
        ? [
            for (final s in sitters) [s],
          ]
        : groupOverlapping(
            sitters,
            camera.latLngToScreenOffset,
            keepApart: selectedId,
          );
    // El seleccionado va al final para quedar encima de los demás pines.
    groups.sort(
      (a, b) =>
          (a.first.id == selectedId ? 1 : 0) -
          (b.first.id == selectedId ? 1 : 0),
    );
    return MarkerLayer(
      alignment: Alignment.topCenter,
      markers: [
        for (final g in groups)
          if (g.length == 1)
            Marker(
              point: g.single.location,
              width: SitterPin.width,
              height: SitterPin.height,
              child: SitterPin(
                name: g.single.name,
                price: g.single.pinPrice(service),
                selected: g.single.id == selectedId,
                onTap: () => onFocus(g.single),
              ),
            )
          else
            Marker(
              point: _center(g),
              width: SitterClusterPin.width,
              height: SitterClusterPin.height,
              child: SitterClusterPin(
                sitters: g,
                service: service,
                onTap: () => onZoomTo(g),
                onFocus: onFocus,
              ),
            ),
      ],
    );
  }

  static LatLng _center(List<SitterSummary> g) => LatLng(
    g.map((s) => s.location.latitude).reduce((a, b) => a + b) / g.length,
    g.map((s) => s.location.longitude).reduce((a, b) => a + b) / g.length,
  );
}

/// Grupo de pines: el precio más bajo del grupo y cuántos cuidadores hay.
class SitterClusterPin extends StatelessWidget {
  const SitterClusterPin({
    super.key,
    required this.sitters,
    required this.service,
    required this.onTap,
    required this.onFocus,
  });

  static const width = 104.0;
  static const height = 60.0;

  final List<SitterSummary> sitters;
  final ServiceType? service;
  final VoidCallback onTap;
  final void Function(SitterSummary) onFocus;

  @override
  Widget build(BuildContext context) {
    final from = sitters
        .map((s) => s.pinPrice(service))
        .reduce((a, b) => a < b ? a : b);
    return Stack(
      children: [
        Semantics(
          container: true,
          button: true,
          label:
              '${sitters.length} cuidadores en esta zona, desde ${formatCop(from)}. Acercar',
          onTap: onTap,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  SitterPin(
                    name: '',
                    price: from,
                    selected: false,
                    onTap: onTap,
                    excludeFromSemantics: true,
                  ),
                  Positioned(
                    top: -8,
                    right: -2,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 24),
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.text,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        '${sitters.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Con lector de pantalla cada cuidador del grupo sigue siendo un pin
        // propio: no hace falta acercar el mapa para llegar a él.
        for (final s in sitters)
          Positioned.fill(
            child: Semantics(
              container: true,
              button: true,
              label: 'Cuidador ${s.name}, ${formatCop(s.pinPrice(service))}',
              onTap: () => onFocus(s),
              excludeSemantics: true,
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}
