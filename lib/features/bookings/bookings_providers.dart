import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/booking.dart';
import '../../data/models/contact_info.dart';
import '../../data/models/sitter_summary.dart';
import '../../data/providers.dart';

/// Reservas del usuario con sesión, en vivo. Se reinicia al cambiar de cuenta.
final myBookingsProvider = StreamProvider.autoDispose<List<Booking>>((ref) {
  ref.watch(authStateProvider.select((a) => a.value?.id));
  return ref.watch(repositoryProvider).watchMyBookings();
});

/// Servicios y horario del cuidador con sesión (también en revisión).
final mySitterProfileProvider = FutureProvider.autoDispose<SitterSummary>((
  ref,
) {
  ref.watch(authStateProvider.select((a) => a.value?.id));
  return ref.watch(repositoryProvider).fetchMySitterProfile();
});

/// Clave para datos que dependen del estado de la reserva (se vuelven a pedir
/// cuando cambia, p. ej. al aceptarse).
typedef BookingKey = ({String id, BookingStatus status});

/// Contacto de la contraparte (solo existe con la reserva aceptada).
final counterpartContactProvider = FutureProvider.autoDispose
    .family<ContactInfo?, BookingKey>(
      (ref, key) =>
          ref.watch(repositoryProvider).fetchCounterpartContact(key.id),
    );

/// Notas del perro de una reserva (el cuidador solo las recibe si está aceptada).
final dogNotesProvider = FutureProvider.autoDispose.family<String?, BookingKey>(
  (ref, key) => ref.watch(repositoryProvider).fetchDogNotesForBooking(key.id),
);

final myPrivateDataProvider = FutureProvider.autoDispose<PrivateData>((ref) {
  ref.watch(authStateProvider.select((a) => a.value?.id));
  return ref.watch(repositoryProvider).fetchMyPrivateData();
});
