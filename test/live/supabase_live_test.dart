// Prueba contra el proyecto REAL de Supabase con las cuentas de prueba.
// Solo corre con las claves:
//   flutter test test/live --dart-define-from-file=env.json
// Deja en la base reservas canceladas de dueno@ y cuidador@ (son de prueba).
@Tags(['live'])
library;

import 'dart:async';

import 'package:doggo/core/config.dart';
import 'package:doggo/data/models/booking.dart';
import 'package:doggo/data/models/dog.dart';
import 'package:doggo/data/models/profile.dart';
import 'package:doggo/data/models/service_type.dart';
import 'package:doggo/data/repositories/repository.dart';
import 'package:doggo/data/supabase/supabase_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cada "aparato" tiene su propio cliente y su propia sesión.
SupabaseRepository device() => SupabaseRepository(
  client: SupabaseClient(
    supabaseUrl,
    supabaseAnonKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  ),
);

void main() {
  if (!supabaseConfigured) {
    test('sin claves de Supabase', () {}, skip: 'Falta env.json');
    return;
  }

  late SupabaseRepository owner;
  late SupabaseRepository sitter;

  setUpAll(() async {
    owner = device();
    sitter = device();
    await owner.signIn(email: 'dueno@doggo.app', password: 'doggo123');
    await sitter.signIn(email: 'cuidador@doggo.app', password: 'doggo123');
  });

  tearDownAll(() async {
    await owner.signOut();
    await sitter.signOut();
  });

  test('sesiones y roles', () {
    expect(owner.currentProfile!.role, UserRole.owner);
    expect(owner.currentProfile!.fullName, 'Daniela Dueña');
    expect(sitter.currentProfile!.role, UserRole.sitter);
    expect(sitter.currentProfile!.status, UserStatus.approved);
  });

  test('contraseña incorrecta', () async {
    expect(
      () => device().signIn(email: 'dueno@doggo.app', password: 'mala'),
      throwsA(
        isA<AuthFailure>().having(
          (e) => e.message,
          'mensaje',
          'Correo o contraseña incorrectos.',
        ),
      ),
    );
  });

  test(
    'el mapa: 11 cuidadores con barrio, precio, horario y calificación',
    () async {
      final sitters = await owner.fetchSitters();
      expect(sitters, hasLength(11));
      final carlos = sitters.firstWhere((s) => s.name == 'Carlos Cuidador');
      expect(carlos.neighborhood, 'Chapinero');
      expect(carlos.services[ServiceType.walk], 26000);
      expect(carlos.verified, isTrue);
      final laura = sitters.firstWhere((s) => s.name == 'Laura Gómez');
      expect(laura.ratingCount, greaterThan(0));
      final reviews = await owner.fetchReviews(laura.id);
      expect(reviews.first.authorName, 'Marcela D.');
      // Natalia está en revisión: no sale.
      expect(sitters.any((s) => s.name == 'Natalia Peña'), isFalse);
    },
  );

  test('flujo completo: reserva en vivo, aceptar, contacto, cancelar', () async {
    final carlos = (await owner.fetchSitters()).firstWhere(
      (s) => s.name == 'Carlos Cuidador',
    );
    final dog = await owner.addDog(
      name: 'Prueba en vivo',
      size: DogSize.small,
      notes: 'Le gusta la pelota',
    );
    expect((await owner.fetchMyDogs()).map((d) => d.id), contains(dog.id));

    // El cuidador escucha sus reservas en vivo.
    final sitterSees = StreamIterator(sitter.watchMyBookings());
    expect(await sitterSees.moveNext(), isTrue);
    // Deja que la conexión en vivo termine de abrirse (y descarta la recarga
    // que hace al quedar suscrita): lo que llegue después es tiempo real.
    await Future<void>.delayed(const Duration(seconds: 3));
    await sitterSees.moveNext().timeout(
      const Duration(seconds: 3),
      onTimeout: () => true,
    );

    final t = DateTime.now().add(const Duration(days: 2));
    final start = DateTime(t.year, t.month, t.day, 10);
    final stopwatch = Stopwatch()..start();
    final created = await owner.createBooking(
      sitterId: carlos.id,
      dogId: dog.id,
      service: ServiceType.walk,
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
    );
    expect(created.status, BookingStatus.pending);
    expect(created.totalCop, 26000);
    expect(created.dogName, 'Prueba en vivo');

    Booking? arrived;
    while (arrived == null) {
      expect(
        await sitterSees.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      arrived = sitterSees.current.where((b) => b.id == created.id).firstOrNull;
    }
    stopwatch.stop();
    // ignore: avoid_print
    print(
      'La solicitud le llegó al cuidador en ${stopwatch.elapsedMilliseconds} ms',
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(arrived.ownerName, 'Daniela Dueña');
    expect(arrived.dogName, 'Prueba en vivo');

    // Antes de aceptar: ni contacto ni notas del perro.
    expect(await sitter.fetchCounterpartContact(created.id), isNull);
    expect(await sitter.fetchDogNotesForBooking(created.id), isNull);

    final ownerSees = StreamIterator(owner.watchMyBookings());
    expect(await ownerSees.moveNext(), isTrue);
    await Future<void>.delayed(const Duration(seconds: 3));
    await ownerSees.moveNext().timeout(
      const Duration(seconds: 3),
      onTimeout: () => true,
    );
    await sitter.respondToBooking(created.id, accept: true);
    BookingStatus? status;
    final acceptWatch = Stopwatch()..start();
    while (status != BookingStatus.accepted) {
      expect(
        await ownerSees.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      status = ownerSees.current.firstWhere((b) => b.id == created.id).status;
    }

    // ignore: avoid_print
    print(
      'El dueño vio la aceptación en ${acceptWatch.elapsedMilliseconds} ms',
    );
    expect(acceptWatch.elapsed, lessThan(const Duration(seconds: 2)));

    // Con la reserva aceptada: contacto en ambos sentidos y notas del perro.
    final ownerContact = await owner.fetchCounterpartContact(created.id);
    expect(ownerContact!.name, 'Carlos Cuidador');
    final sitterContact = await sitter.fetchCounterpartContact(created.id);
    expect(sitterContact!.name, 'Daniela Dueña');
    expect(
      await sitter.fetchDogNotesForBooking(created.id),
      'Le gusta la pelota',
    );

    // Responder dos veces no se puede.
    expect(
      () => sitter.respondToBooking(created.id, accept: false),
      throwsA(isA<ValidationFailure>()),
    );

    final cancelled = await owner.cancelBooking(created.id);
    expect(cancelled.status, BookingStatus.cancelled);
    await sitterSees.cancel();
    await ownerSees.cancel();

    await owner.deleteDog(dog.id);
    expect((await owner.fetchMyDogs()).any((d) => d.id == dog.id), isFalse);
  });

  test('reglas de la base llegan como mensajes claros', () async {
    final carlos = (await owner.fetchSitters()).firstWhere(
      (s) => s.name == 'Carlos Cuidador',
    );
    final dogs = await owner.fetchMyDogs();
    final dog = dogs.isNotEmpty
        ? dogs.first
        : await owner.addDog(name: 'Firulais', size: DogSize.medium);
    // Servicio que Carlos no ofrece.
    final t = DateTime.now().add(const Duration(days: 3));
    final start = DateTime(t.year, t.month, t.day, 10);
    await expectLater(
      owner.createBooking(
        sitterId: carlos.id,
        dogId: dog.id,
        service: ServiceType.boarding,
        startAt: start,
        endAt: start.add(const Duration(days: 1)),
      ),
      throwsA(
        isA<ValidationFailure>().having(
          (e) => e.message,
          'mensaje',
          'Este cuidador no ofrece ese servicio.',
        ),
      ),
    );
    // Un dueño no puede usar el panel de admin.
    await expectLater(
      owner.fetchPendingSitters(),
      throwsA(isA<ValidationFailure>()),
    );
    if (dogs.isEmpty) await owner.deleteDog(dog.id);
  });

  test('el cuidador edita su perfil (y se restaura)', () async {
    final before = await sitter.fetchMySitterProfile();
    await sitter.saveMyBio('Bio temporal de la prueba en vivo.');
    expect(
      (await sitter.fetchMySitterProfile()).bio,
      'Bio temporal de la prueba en vivo.',
    );
    await expectLater(
      sitter.saveMyBio('Escríbeme a carlos@gmail.com'),
      throwsA(isA<ValidationFailure>()),
    );
    await sitter.saveMyBio(before.bio);
  });
}
