import 'package:doggo/data/models/sitter_summary.dart';
import 'package:doggo/features/map/sitter_cluster.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

SitterSummary _at(String id, double x, double y) => SitterSummary(
  id: id,
  name: id,
  neighborhood: '',
  bio: '',
  // En la prueba, la "ubicación" ya son píxeles de pantalla.
  location: LatLng(y, x),
  radiusKm: 3,
  services: const {},
);

Offset _screen(LatLng p) => Offset(p.longitude, p.latitude);

List<List<String>> _ids(List<List<SitterSummary>> groups) => [
  for (final g in groups) [for (final s in g) s.id],
];

void main() {
  test('los pines que se tapan forman un grupo; los lejanos quedan solos', () {
    final groups = groupOverlapping([
      _at('a', 0, 0),
      _at('b', 40, 10),
      _at('c', 300, 0),
      _at('d', 60, -20),
    ], _screen);
    expect(_ids(groups), [
      ['a', 'b', 'd'],
      ['c'],
    ]);
  });

  test('pines lado a lado sin tocarse no se agrupan', () {
    final groups = groupOverlapping([
      _at('a', 0, 0),
      _at('b', 90, 0),
      _at('c', 0, 50),
    ], _screen);
    expect(groups, hasLength(3));
  });

  test('el seleccionado nunca se agrupa', () {
    final groups = groupOverlapping(
      [_at('a', 0, 0), _at('b', 10, 0), _at('c', 20, 0)],
      _screen,
      keepApart: 'b',
    );
    expect(_ids(groups), [
      ['a', 'c'],
      ['b'],
    ]);
  });

  test('cada cuidador aparece en exactamente un grupo', () {
    final sitters = [
      for (var i = 0; i < 30; i++) _at('s$i', (i * 37) % 200, (i * 23) % 120),
    ];
    final ids = _ids(groupOverlapping(sitters, _screen)).expand((g) => g);
    expect(ids.toList()..sort(), [for (final s in sitters) s.id]..sort());
  });
}
