import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

// Ubicación pública de un cuidador: la exacta desplazada entre 200 y 300 m.
// Igual que el trigger `sync_approx_location` de la base, el desplazamiento es
// fijo por usuario (no aleatorio en cada guardado): si cambiara cada vez, se
// podría promediar y recuperar la ubicación exacta.

const _earthRadiusM = 6371000.0;

/// Hash FNV-1a de 32 bits: estable entre ejecuciones y plataformas.
int _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

LatLng approximateLocation(String userId, LatLng exact) {
  final bearing = (_fnv1a(userId) % 360) * math.pi / 180;
  final distance = 200 + _fnv1a('$userId:d') % 101; // 200–300 m
  final dLat = distance * math.cos(bearing) / _earthRadiusM;
  final dLng =
      distance *
      math.sin(bearing) /
      (_earthRadiusM * math.cos(exact.latitude * math.pi / 180));
  return LatLng(
    exact.latitude + dLat * 180 / math.pi,
    exact.longitude + dLng * 180 / math.pi,
  );
}
