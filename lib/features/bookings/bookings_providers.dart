import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/booking.dart';
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
