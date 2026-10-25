import 'package:doggo/data/demo/demo_repository.dart';
import 'package:doggo/data/models/availability.dart';
import 'package:doggo/data/models/booking.dart';
import 'package:doggo/data/models/dog.dart';
import 'package:doggo/data/models/profile.dart';
import 'package:doggo/data/models/service_type.dart';
import 'package:doggo/data/pricing.dart';
import 'package:doggo/data/repositories/repository.dart';
import 'package:flutter_test/flutter_test.dart';

const laura = 'a1000000-0000-4000-8000-000000000001';
const andres = 'a1000000-0000-4000-8000-000000000002';
const rocky = 'demo-dog-rocky';

void main() {
  late DemoRepository repo;
  final tomorrow9 = () {
    final t = DateTime.now().add(const Duration(days: 1));
    return DateTime(t.year, t.month, t.day, 9);
  }();

  setUp(() async {
    repo = DemoRepository();
    await repo.signIn(email: 'dueno@doggo.app', password: demoPassword);
  });

  Future<Booking> book({
    String sitter = laura,
    String dog = rocky,
    ServiceType service = ServiceType.walk,
    DateTime? start,
    DateTime? end,
  }) {
    final s = start ?? tomorrow9;
    return repo.createBooking(
      sitterId: sitter,
      dogId: dog,
      service: service,
      startAt: s,
      endAt: end ?? s.add(const Duration(hours: 1)),
    );
  }

  group('precio (misma regla que el trigger de la base)', () {
    test('paseo, visita, baño y entrenamiento: una unidad', () {
      for (final s in [ServiceType.walk, ServiceType.homeVisit, ServiceType.grooming, ServiceType.training]) {
        expect(bookingUnits(s, tomorrow9, tomorrow9.add(const Duration(hours: 5))), 1);
      }
    });

    test('guardería: por día, redondeando hacia arriba', () {
      expect(bookingUnits(ServiceType.daycare, tomorrow9, bookingEnd(ServiceType.daycare, tomorrow9)), 1);
      expect(bookingUnits(ServiceType.daycare, tomorrow9, bookingEnd(ServiceType.daycare, tomorrow9, amount: 3)), 3);
    });

    test('hospedaje: por noche', () {
      expect(bookingUnits(ServiceType.boarding, tomorrow9, bookingEnd(ServiceType.boarding, tomorrow9, amount: 4)), 4);
    });
  });

  group('crear reserva', () {
    test('nace pending y el total lo calcula el repositorio', () async {
      final b = await book();
      expect(b.status, BookingStatus.pending);
      expect(b.totalCop, 25000);
      expect(b.sitterName, 'Laura Gómez');
      expect(b.dogName, 'Rocky');
    });

    test('hospedaje de 3 noches con Andrés: 3 × \$85.000', () async {
      final b = await book(
        sitter: andres,
        service: ServiceType.boarding,
        end: bookingEnd(ServiceType.boarding, tomorrow9, amount: 3),
      );
      expect(b.totalCop, 255000);
    });

    test('fecha en el pasado: rechazada', () async {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      expect(() => book(start: past), throwsA(isA<ValidationFailure>()));
    });

    test('el cuidador tiene 2 h para responder, o hasta 30 min antes del inicio', () async {
      final b = await book();
      expect(b.responseDeadline.difference(b.createdAt), const Duration(hours: 2));

      // Reloj fijo a las 8:00 para que "dentro de 90 min" caiga en horario.
      final eight = tomorrow9.subtract(const Duration(hours: 1));
      final fixed = DemoRepository(clock: () => eight);
      await fixed.signIn(email: 'dueno@doggo.app', password: demoPassword);
      final soon = eight.add(const Duration(minutes: 90));
      final near = await fixed.createBooking(
        sitterId: laura,
        dogId: rocky,
        service: ServiceType.walk,
        startAt: soon,
        endAt: soon.add(const Duration(hours: 1)),
      );
      expect(near.responseDeadline, soon.subtract(const Duration(minutes: 30)));
    });

    test('menos de 1 hora de anticipación: rechazada', () async {
      final eight = tomorrow9.subtract(const Duration(hours: 1));
      final fixed = DemoRepository(clock: () => eight);
      await fixed.signIn(email: 'dueno@doggo.app', password: demoPassword);
      final soon = eight.add(const Duration(minutes: 40)); // 8:40, en horario
      expect(
        () => fixed.createBooking(
          sitterId: laura,
          dogId: rocky,
          service: ServiceType.walk,
          startAt: soon,
          endAt: soon.add(const Duration(hours: 1)),
        ),
        throwsA(isA<ValidationFailure>().having((e) => e.message, 'message', contains('1 hora de anticipación'))),
      );
    });

    test('fin antes del inicio: rechazada', () async {
      expect(
        () => book(end: tomorrow9.subtract(const Duration(minutes: 1))),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('servicio que el cuidador no ofrece: rechazada', () async {
      expect(() => book(service: ServiceType.grooming), throwsA(isA<ValidationFailure>()));
    });

    test('cuidador en revisión o inexistente: rechazada', () async {
      expect(() => book(sitter: 'a1000000-0000-4000-8000-000000000011'), throwsA(isA<ValidationFailure>()));
    });

    test('perro de otro dueño: rechazada', () async {
      await repo.signOut();
      await repo.signUp(
        email: 'otro@test.com',
        password: 'secreto1',
        fullName: 'Otro Dueño',
        role: UserRole.owner,
        acceptedTerms: true,
      );
      expect(() => book(dog: rocky), throwsA(isA<ValidationFailure>()));
    });

    test('un cuidador no puede reservar', () async {
      await repo.signOut();
      await repo.signIn(email: 'cuidador@doggo.app', password: demoPassword);
      expect(() => book(), throwsA(isA<ValidationFailure>()));
    });
  });

  group('perros', () {
    test('el dueño demo tiene a Rocky y Luna', () async {
      final dogs = await repo.fetchMyDogs();
      expect(dogs.map((d) => d.name), ['Rocky', 'Luna']);
    });

    test('un dueño nuevo agrega su perro y puede reservar con él', () async {
      await repo.signOut();
      await repo.signUp(
        email: 'nuevo@test.com',
        password: 'secreto1',
        fullName: 'Nuevo',
        role: UserRole.owner,
        acceptedTerms: true,
      );
      expect(await repo.fetchMyDogs(), isEmpty);
      final dog = await repo.addDog(name: 'Toby', size: DogSize.small);
      final b = await book(dog: dog.id);
      expect(b.dogName, 'Toby');
    });

    test('nombre vacío: rechazado', () async {
      expect(() => repo.addDog(name: '  ', size: DogSize.small), throwsA(isA<ValidationFailure>()));
    });
  });

  test('con una reserva activa no se puede cambiar de rol', () async {
    await book();
    expect(() => repo.switchRole(UserRole.sitter), throwsA(isA<AuthFailure>()));
  });

  group('panel del cuidador', () {
    const carlos = 'demo-sitter';
    late DateTime now;
    late DemoRepository clocked;

    setUp(() async {
      now = DateTime.now();
      clocked = DemoRepository(clock: () => now);
      await clocked.signIn(email: 'dueno@doggo.app', password: demoPassword);
    });

    Future<Booking> bookCarlos({DateTime? start}) {
      final s = start ?? tomorrow9;
      return clocked.createBooking(
        sitterId: carlos,
        dogId: rocky,
        service: ServiceType.walk,
        startAt: s,
        endAt: s.add(const Duration(hours: 1)),
      );
    }

    Future<void> asCarlos() async {
      await clocked.signOut();
      await clocked.signIn(email: 'cuidador@doggo.app', password: demoPassword);
    }

    test('la solicitud le llega en vivo al cuidador y puede aceptarla', () async {
      final b = await bookCarlos();
      expect(b.ownerName, 'Daniela Dueña');
      await asCarlos();
      final first = await clocked.watchMyBookings().first;
      expect(first.single.status, BookingStatus.pending);

      final updates = clocked.watchMyBookings().skip(1).first;
      await clocked.respondToBooking(b.id, accept: true);
      expect((await updates).single.status, BookingStatus.accepted);

      final done = await clocked.completeBooking(b.id);
      expect(done.status, BookingStatus.completed);
    });

    test('rechazar', () async {
      final b = await bookCarlos();
      await asCarlos();
      final r = await clocked.respondToBooking(b.id, accept: false);
      expect(r.status, BookingStatus.rejected);
      expect(() => clocked.respondToBooking(b.id, accept: true), throwsA(isA<ValidationFailure>()));
    });

    test('pasado el plazo de 2 h la solicitud vence y no se puede aceptar', () async {
      final b = await bookCarlos();
      await asCarlos();
      now = now.add(const Duration(hours: 2, minutes: 1));
      final list = await clocked.watchMyBookings().first;
      expect(list.single.status, BookingStatus.expired);
      expect(() => clocked.respondToBooking(b.id, accept: true), throwsA(isA<ValidationFailure>()));
    });

    test('no se completa una reserva sin aceptar', () async {
      final b = await bookCarlos();
      await asCarlos();
      expect(() => clocked.completeBooking(b.id), throwsA(isA<ValidationFailure>()));
    });

    test('otro cuidador no puede responder solicitudes ajenas', () async {
      final b = await bookCarlos();
      await clocked.signOut();
      await clocked.signUp(
        email: 'otro.cuidador@test.com',
        password: 'secreto1',
        fullName: 'Otro',
        role: UserRole.sitter,
        acceptedTerms: true,
      );
      expect(() => clocked.respondToBooking(b.id, accept: true), throwsA(isA<ValidationFailure>()));
    });

    test('el cuidador edita servicios y precios, y se ven en el mapa', () async {
      await asCarlos();
      await clocked.saveMyServices({ServiceType.walk: 30000, ServiceType.training: 70000});
      final s = await clocked.fetchSitter(carlos);
      expect(s!.services, {ServiceType.walk: 30000, ServiceType.training: 70000});
    });

    test('precios fuera de rango o sin servicios: rechazado', () async {
      await asCarlos();
      expect(() => clocked.saveMyServices({ServiceType.walk: 100}), throwsA(isA<ValidationFailure>()));
      expect(() => clocked.saveMyServices({}), throwsA(isA<ValidationFailure>()));
    });

    test('la reserva debe caer dentro del horario del cuidador', () async {
      await asCarlos();
      await clocked.saveMyAvailability(
        WeeklyAvailability.standard.withDay(tomorrow9.weekday, const DayWindow(600, 720)), // 10:00–12:00
      );
      await clocked.signOut();
      await clocked.signIn(email: 'dueno@doggo.app', password: demoPassword);
      expect(() => bookCarlos(start: tomorrow9), throwsA(isA<ValidationFailure>())); // 9:00
      final ok = await bookCarlos(start: tomorrow9.add(const Duration(hours: 2))); // 11:00
      expect(ok.status, BookingStatus.pending);
    });

    test('un cuidador en revisión prepara sus servicios aunque no esté en el mapa', () async {
      await clocked.signOut();
      await clocked.signUp(
        email: 'nuevo.cuidador@test.com',
        password: 'secreto1',
        fullName: 'Nuevo Cuidador',
        role: UserRole.sitter,
        acceptedTerms: true,
      );
      final mine = await clocked.fetchMySitterProfile();
      expect(mine.services, isEmpty);
      await clocked.saveMyServices({ServiceType.walk: 20000});
      expect((await clocked.fetchMySitterProfile()).services, {ServiceType.walk: 20000});
      expect((await clocked.fetchSitters()).any((s) => s.name == 'Nuevo Cuidador'), isFalse);
    });
  });

  test('el cuidador de prueba aparece en el mapa demo', () async {
    final s = await repo.fetchSitter('demo-sitter');
    expect(s?.name, 'Carlos Cuidador');
  });
}
