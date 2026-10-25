import 'package:doggo/data/demo/demo_repository.dart';
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

      final soon = DateTime.now().add(const Duration(minutes: 90));
      final near = await book(start: soon);
      expect(near.responseDeadline, soon.subtract(const Duration(minutes: 30)));
    });

    test('menos de 1 hora de anticipación: rechazada', () async {
      final soon = DateTime.now().add(const Duration(minutes: 40));
      expect(() => book(start: soon), throwsA(isA<ValidationFailure>()));
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

  test('el cuidador de prueba aparece en el mapa demo', () async {
    final s = await repo.fetchSitter('demo-sitter');
    expect(s?.name, 'Carlos Cuidador');
  });
}
