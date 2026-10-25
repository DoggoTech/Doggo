// Detección básica de datos de contacto en textos libres (bio, notas,
// reseñas). Es la MISMA regla que `private.contains_contact_info` en
// supabase/schema.sql: la base la impone igual aunque se salte la app.

final _email = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');
final _link = RegExp(r'(https?://|www\.)', caseSensitive: false);
final _domain = RegExp(
  r'\b[A-Za-z0-9-]+\.(com|co|net|org|io|app|me|ly)\b',
  caseSensitive: false,
);
final _phone = RegExp(r'\d([\s.()-]*\d){6,}');

bool containsContactInfo(String text) =>
    _email.hasMatch(text) ||
    _link.hasMatch(text) ||
    _domain.hasMatch(text) ||
    _phone.hasMatch(text);

const contactInfoMessage =
    'Por tu seguridad, no compartas teléfonos, correos ni enlaces aquí. Coordina todo dentro de Doggo.';
