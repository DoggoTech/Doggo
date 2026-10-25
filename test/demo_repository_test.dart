import 'package:doggo/data/demo/demo_repository.dart';
import 'package:doggo/data/models/availability.dart';
import 'package:doggo/data/models/booking.dart';
import 'package:doggo/data/models/contact_info.dart';
import 'package:doggo/data/models/dog.dart';
import 'package:doggo/data/models/profile.dart';
import 'package:doggo/data/models/report.dart';
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

  group('dueño: reservas, contacto, perros y reseñas', () {
    late DemoRepository r;
    setUp(() async {
      r = DemoRepository();
      await r.signIn(email: 'dueno@doggo.app', password: demoPassword);
    });

    Future<Booking> bookCarlos() => r.createBooking(
          sitterId: 'demo-sitter',
          dogId: rocky,
          service: ServiceType.walk,
          startAt: tomorrow9,
          endAt: tomorrow9.add(const Duration(hours: 1)),
        );

    Future<void> as(String email) async {
      await r.signOut();
      await r.signIn(email: email, password: demoPassword);
    }

    test('el contacto solo se ve con la reserva aceptada, y en ambos sentidos', () async {
      final b = await bookCarlos();
      expect(await r.fetchCounterpartContact(b.id), isNull);
      await as('cuidador@doggo.app');
      expect(await r.fetchCounterpartContact(b.id), isNull);
      await r.respondToBooking(b.id, accept: true);
      final ownerContact = await r.fetchCounterpartContact(b.id);
      expect(ownerContact!.name, 'Daniela Dueña');
      expect(ownerContact.phone, isNotNull);
      await as('dueno@doggo.app');
      final sitterContact = await r.fetchCounterpartContact(b.id);
      expect(sitterContact!.name, 'Carlos Cuidador');
      expect(sitterContact.address, contains('Chapinero'));
    });

    test('las notas del perro: el cuidador solo las ve con la reserva aceptada', () async {
      final b = await bookCarlos();
      await as('cuidador@doggo.app');
      expect(await r.fetchDogNotesForBooking(b.id), isNull);
      await r.respondToBooking(b.id, accept: true);
      expect(await r.fetchDogNotesForBooking(b.id), contains('motos'));
    });

    test('cancelar una reserva pendiente o aceptada, no una completada', () async {
      final b = await bookCarlos();
      expect((await r.cancelBooking(b.id)).status, BookingStatus.cancelled);
      expect(() => r.cancelBooking(b.id), throwsA(isA<ValidationFailure>()));
    });

    test('reseña: solo completadas, una vez, y actualiza la calificación', () async {
      final b = await bookCarlos();
      expect(() => r.createReview(bookingId: b.id, rating: 5), throwsA(isA<ValidationFailure>()));
      await as('cuidador@doggo.app');
      await r.respondToBooking(b.id, accept: true);
      await r.completeBooking(b.id);
      await as('dueno@doggo.app');
      await r.createReview(bookingId: b.id, rating: 5, comment: 'Excelente');
      expect(() => r.createReview(bookingId: b.id, rating: 4), throwsA(isA<ValidationFailure>()));
      final carlos = await r.fetchSitter('demo-sitter');
      expect(carlos!.ratingCount, 1);
      expect(carlos.ratingAvg, 5.0);
      final reviews = await r.fetchReviews('demo-sitter');
      expect(reviews.single.comment, 'Excelente');
    });

    test('reseña con teléfono: rechazada', () async {
      final b = await bookCarlos();
      await as('cuidador@doggo.app');
      await r.respondToBooking(b.id, accept: true);
      await r.completeBooking(b.id);
      await as('dueno@doggo.app');
      expect(
        () => r.createReview(bookingId: b.id, rating: 5, comment: 'llámame al 300 111 2233'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('perros: editar, notas sin datos de contacto y borrar', () async {
      final max = await r.addDog(name: 'Max', size: DogSize.giant, notes: 'Toma pastilla a las 8');
      final edited = await r.updateDog(Dog(id: max.id, ownerId: max.ownerId, name: 'Max II', size: DogSize.large));
      expect(edited.name, 'Max II');
      expect(
        () => r.updateDog(Dog(id: max.id, ownerId: max.ownerId, name: 'Max', size: DogSize.large, notes: 'mi cel 3001112233')),
        throwsA(isA<ValidationFailure>()),
      );
      await r.deleteDog(max.id);
      expect((await r.fetchMyDogs()).map((d) => d.name), ['Rocky', 'Luna']);
    });

    test('no se borra un perro con reservas activas', () async {
      await bookCarlos();
      expect(() => r.deleteDog(rocky), throwsA(isA<ValidationFailure>()));
    });

    test('mis datos de contacto: se guardan y se validan', () async {
      await r.saveMyPrivateData(const PrivateData(phone: '+57 311 222 3344', address: 'Calle 1'));
      expect((await r.fetchMyPrivateData()).phone, '+57 311 222 3344');
      expect(() => r.saveMyPrivateData(const PrivateData(phone: 'llámame')), throwsA(isA<ValidationFailure>()));
    });
  });

  group('seguridad: reportes y bio', () {
    late DemoRepository r;
    setUp(() async {
      r = DemoRepository();
      await r.signIn(email: 'dueno@doggo.app', password: demoPassword);
    });

    test('un dueño reporta a un cuidador', () async {
      await r.createReport(reportedUserId: laura, reason: ReportReason.fakeProfile, comment: 'Fotos falsas');
    });

    test('no se puede reportar a uno mismo', () async {
      expect(
        () => r.createReport(reportedUserId: 'demo-owner', reason: ReportReason.other),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('con reserva asociada, ambos deben participar en ella', () async {
      final b = await r.createBooking(
        sitterId: 'demo-sitter',
        dogId: rocky,
        service: ServiceType.walk,
        startAt: tomorrow9,
        endAt: tomorrow9.add(const Duration(hours: 1)),
      );
      await r.createReport(reportedUserId: 'demo-sitter', bookingId: b.id, reason: ReportReason.offPlatformPayment);
      expect(
        () => r.createReport(reportedUserId: laura, bookingId: b.id, reason: ReportReason.other),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('un admin no puede reportar', () async {
      await r.signOut();
      await r.signIn(email: 'admin@doggo.app', password: demoPassword);
      expect(
        () => r.createReport(reportedUserId: laura, reason: ReportReason.other),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('el cuidador edita su bio; con teléfono se rechaza', () async {
      await r.signOut();
      await r.signIn(email: 'cuidador@doggo.app', password: demoPassword);
      await r.saveMyBio('Paseos largos por el parque.');
      expect((await r.fetchSitter('demo-sitter'))!.bio, 'Paseos largos por el parque.');
      expect(() => r.saveMyBio('Escríbeme al 300 111 2233'), throwsA(isA<ValidationFailure>()));
    });
  });

  group('administración', () {
    const natalia = 'a1000000-0000-4000-8000-000000000011';
    late DemoRepository r;

    Future<void> as(String email) async {
      await r.signOut();
      await r.signIn(email: email, password: demoPassword);
    }

    setUp(() async {
      r = DemoRepository();
      await r.signIn(email: 'admin@doggo.app', password: demoPassword);
    });

    test('ve los 2 cuidadores en revisión del seed', () async {
      final pending = await r.fetchPendingSitters();
      expect(pending.map((p) => p.user.name), containsAll(['Natalia Peña', 'Ricardo Salazar']));
      expect(pending.first.sitter.services, isNotEmpty);
    });

    test('aprobar a un cuidador lo pone en el mapa y queda auditado', () async {
      expect((await r.fetchSitters()).any((s) => s.id == natalia), isFalse);
      await r.setSitterApproval(natalia, approve: true);
      expect((await r.fetchSitters()).any((s) => s.id == natalia), isTrue);
      expect((await r.fetchPendingSitters()).any((p) => p.user.id == natalia), isFalse);
      expect((await r.fetchAdminActions()).single.action, 'approve_sitter');
    });

    test('rechazar lo deja suspendido y fuera del mapa', () async {
      await r.setSitterApproval(natalia, approve: false);
      final row = (await r.searchUsers(query: 'natalia')).single;
      expect(row.status, UserStatus.suspended);
      expect((await r.fetchSitters()).any((s) => s.id == natalia), isFalse);
    });

    test('la insignia Verificado se ve en el mapa', () async {
      await r.setVerified(laura, false);
      expect((await r.fetchSitter(laura))!.verified, isFalse);
      await r.setVerified(laura, true);
      expect((await r.fetchSitter(laura))!.verified, isTrue);
    });

    test('un usuario suspendido desaparece del mapa y no puede entrar', () async {
      await r.setUserSuspended('demo-sitter', true);
      expect((await r.fetchSitters()).any((s) => s.id == 'demo-sitter'), isFalse);
      await r.signOut();
      expect(
        () => r.signIn(email: 'cuidador@doggo.app', password: demoPassword),
        throwsA(isA<AccountSuspendedFailure>()),
      );
    });

    test('reactivar devuelve al usuario al mapa', () async {
      await r.setUserSuspended('demo-sitter', true);
      await r.setUserSuspended('demo-sitter', false);
      expect((await r.fetchSitters()).any((s) => s.id == 'demo-sitter'), isTrue);
    });

    test('un reporte se atiende y puede suspender al reportado', () async {
      await as('dueno@doggo.app');
      await r.createReport(reportedUserId: laura, reason: ReportReason.fakeProfile);
      await as('admin@doggo.app');
      final report = (await r.fetchReports()).single;
      expect(report.reportedName, 'Laura Gómez');
      expect(report.reporterName, 'Daniela Dueña');
      await r.resolveReport(report.id, ReportStatus.reviewed, suspendReported: true);
      expect((await r.fetchReports()).single.status, ReportStatus.reviewed);
      expect((await r.fetchSitters()).any((s) => s.id == laura), isFalse);
      expect(() => r.resolveReport(report.id, ReportStatus.dismissed), throwsA(isA<ValidationFailure>()));
    });

    test('búsqueda por nombre o correo con filtros', () async {
      expect((await r.searchUsers(query: 'seed.camila')).single.name, 'Camila Herrera');
      final admins = await r.searchUsers(role: UserRole.admin);
      expect(admins.single.email, 'admin@doggo.app');
      final pending = await r.searchUsers(status: UserStatus.pendingReview);
      expect(pending, hasLength(2));
    });

    test('un admin no puede suspender a otro admin, al superadmin ni a sí mismo', () async {
      expect(() => r.setUserSuspended('demo-superadmin', true), throwsA(isA<ValidationFailure>()));
      expect(() => r.setUserSuspended('demo-admin', true), throwsA(isA<ValidationFailure>()));
    });

    test('el superadmin sí puede suspender a un admin, pero no a sí mismo', () async {
      await as('superadmin@doggo.app');
      await r.setUserSuspended('demo-admin', true);
      expect((await r.searchUsers(query: 'admin@')).firstWhere((u) => u.id == 'demo-admin').status, UserStatus.suspended);
      expect(() => r.setUserSuspended('demo-superadmin', true), throwsA(isA<ValidationFailure>()));
    });

    test('auditoría: el admin ve lo suyo, el superadmin todo', () async {
      await r.setVerified(laura, true);
      await as('superadmin@doggo.app');
      await r.setUserSuspended('demo-owner', true);
      expect(await r.fetchAdminActions(), hasLength(2));
      await as('admin@doggo.app');
      expect((await r.fetchAdminActions()).single.action, 'verify_sitter');
    });

    test('un dueño no puede usar el panel', () async {
      await as('dueno@doggo.app');
      expect(() => r.fetchPendingSitters(), throwsA(isA<ValidationFailure>()));
      expect(() => r.setUserSuspended(laura, true), throwsA(isA<ValidationFailure>()));
    });

    test('las cuentas de ejemplo no permiten iniciar sesión', () async {
      await r.signOut();
      expect(
        () => r.signIn(email: 'seed.laura@doggo.test', password: demoPassword),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  test('el cuidador de prueba aparece en el mapa demo', () async {
    final s = await repo.fetchSitter('demo-sitter');
    expect(s?.name, 'Carlos Cuidador');
  });
}
