import 'package:doggo/data/contact_filter.dart';
import 'package:flutter_test/flutter_test.dart';

// Mismos casos que la prueba de la base ("se rechazan teléfonos, correos y
// enlaces"): la app y la base deben coincidir.
void main() {
  test('detecta teléfonos, correos y enlaces', () {
    for (final t in [
      'llámame al 300 111 2233',
      'escríbeme a laura@gmail.com',
      'mira https://wa.me/573001112233',
      'visita www.mipagina.com',
      'mi sitio es paseos.co',
      '+57 (300) 111-2233',
    ]) {
      expect(containsContactInfo(t), isTrue, reason: t);
    }
  });

  test('no confunde texto normal con datos de contacto', () {
    for (final t in [
      'Tengo 2 perros, 5 años de experiencia y 10 reseñas.',
      'Paseos de 30 o 60 minutos por el parque 93.',
      'Le dan miedo las motos.',
    ]) {
      expect(containsContactInfo(t), isFalse, reason: t);
    }
  });
}
