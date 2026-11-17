import 'package:doggo/data/demo/demo_repository.dart';
import 'package:doggo/data/models/booking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sin solicitudes de ejemplo, Carlos empieza sin reservas', () async {
    final r = DemoRepository();
    await r.signIn(email: 'cuidador@doggo.app', password: demoPassword);
    expect(await r.watchMyBookings().first, isEmpty);
  });

  group('con solicitudes de ejemplo', () {
    late DemoRepository r;
    setUp(() async {
      r = DemoRepository(sampleBookings: true);
      await r.signIn(email: 'cuidador@doggo.app', password: demoPassword);
    });

    test(
      'Carlos ve 3 pendientes vigentes, 1 aceptada y 1 completada',
      () async {
        final list = await r.watchMyBookings().first;
        final pending = list.where((b) => b.status == BookingStatus.pending);
        expect(pending, hasLength(3));
        for (final b in pending) {
          expect(b.responseDeadline.isAfter(DateTime.now()), isTrue);
          expect(b.totalCop, greaterThan(0));
        }
        expect(
          list.where((b) => b.status == BookingStatus.accepted),
          hasLength(1),
        );
        expect(
          list.where((b) => b.status == BookingStatus.completed),
          hasLength(1),
        );
      },
    );

    test('puede aceptar una y ver el contacto y las notas del perro', () async {
      final list = await r.watchMyBookings().first;
      final toby = list.firstWhere((b) => b.dogName == 'Toby');
      await r.respondToBooking(toby.id, accept: true);
      final contact = await r.fetchCounterpartContact(toby.id);
      expect(contact?.name, 'Valentina Ruiz');
      expect(contact?.phone, isNotNull);
      expect(await r.fetchDogNotesForBooking(toby.id), contains('correa'));
    });

    test('la cuenta del dueño de prueba sigue sin reservas', () async {
      await r.signIn(email: 'dueno@doggo.app', password: demoPassword);
      expect(await r.watchMyBookings().first, isEmpty);
    });
  });
}
