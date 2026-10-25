import 'package:doggo/data/location_privacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const distance = Distance(roundResult: false);
  const exact = LatLng(4.6486, -74.0628);

  test('la ubicación pública queda a 200–300 m de la exacta', () {
    for (var i = 0; i < 200; i++) {
      final approx = approximateLocation('usuario-$i', exact);
      final m = distance.as(LengthUnit.Meter, exact, approx);
      expect(m, inInclusiveRange(195, 305), reason: 'usuario-$i: $m m');
    }
  });

  test('es estable: guardar de nuevo no cambia la ubicación pública', () {
    expect(
      approximateLocation('carlos', exact),
      approximateLocation('carlos', exact),
    );
  });

  test('cada usuario se desplaza en una dirección distinta', () {
    expect(
      approximateLocation('a', exact),
      isNot(approximateLocation('b', exact)),
    );
  });
}
