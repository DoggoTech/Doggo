import 'package:doggo/data/models/service_type.dart';
import 'package:doggo/data/models/sitter_summary.dart';
import 'package:doggo/features/sitter_dashboard/map_visibility_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

SitterSummary _sitter({required bool services, required bool zone}) =>
    SitterSummary(
      id: 's',
      name: 'Santi',
      neighborhood: 'San Patricio',
      bio: '',
      location: const LatLng(4.69, -74.04),
      radiusKm: 5,
      services: services ? const {ServiceType.walk: 20000} : const {},
      locationConfirmed: zone,
    );

void main() {
  test('sin servicios ni zona le faltan las dos cosas', () {
    expect(missingForMap(_sitter(services: false, zone: false)), [
      'activar al menos un servicio con su precio',
      'definir tu zona de servicio',
    ]);
  });

  test('el caso real: aprobado y con zona, pero sin servicios', () {
    expect(missingForMap(_sitter(services: false, zone: true)), [
      'activar al menos un servicio con su precio',
    ]);
  });

  test('con servicios y zona no le falta nada', () {
    expect(missingForMap(_sitter(services: true, zone: true)), isEmpty);
  });
}
