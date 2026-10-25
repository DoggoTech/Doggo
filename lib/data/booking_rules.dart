// Plazos de una solicitud de reserva. Son las MISMAS reglas que impone el
// trigger de `bookings` en supabase/schema.sql.

/// Tiempo que tiene el cuidador para aceptar o rechazar.
const responseWindow = Duration(hours: 2);

/// La respuesta debe llegar al menos este tiempo antes del inicio.
const responseBuffer = Duration(minutes: 30);

/// Anticipación mínima para reservar (deja al menos 30 min para responder).
const minBookingLead = Duration(hours: 1);

/// Hasta cuándo puede responder el cuidador: 2 h desde la solicitud, o
/// 30 min antes del inicio si eso ocurre primero.
DateTime responseDeadline(DateTime requestedAt, DateTime startAt) {
  final byWindow = requestedAt.add(responseWindow);
  final byStart = startAt.subtract(responseBuffer);
  return byWindow.isBefore(byStart) ? byWindow : byStart;
}

/// ¿Se puede pedir una reserva que empieza en [startAt]?
bool startIsBookable(DateTime startAt, {DateTime? now}) =>
    !startAt.isBefore((now ?? DateTime.now()).add(minBookingLead));
