import 'dart:async';

import 'package:latlong2/latlong.dart';

import '../models/booking.dart';
import '../models/dog.dart';
import '../models/profile.dart';
import '../models/review.dart';
import '../models/service_type.dart';
import '../models/sitter_summary.dart';
import '../booking_rules.dart';
import '../pricing.dart';
import '../repositories/repository.dart';

const demoPassword = 'doggo123';

/// Implementación en memoria: sin backend ni persistencia entre recargas.
class DemoRepository implements Repository {
  DemoRepository() {
    for (final p in _seedProfiles) {
      _users[p.email] = _DemoUser(p, demoPassword);
    }
  }

  static final _seedProfiles = [
    Profile(
      id: 'demo-owner',
      email: 'dueno@doggo.app',
      fullName: 'Daniela Dueña',
      role: UserRole.owner,
      status: UserStatus.approved,
      termsAcceptedAt: DateTime(2026, 1, 1),
    ),
    Profile(
      id: 'demo-sitter',
      email: 'cuidador@doggo.app',
      fullName: 'Carlos Cuidador',
      role: UserRole.sitter,
      status: UserStatus.approved,
      verified: true,
      termsAcceptedAt: DateTime(2026, 1, 1),
    ),
    Profile(
      id: 'demo-admin',
      email: 'admin@doggo.app',
      fullName: 'Ana Admin',
      role: UserRole.admin,
      status: UserStatus.approved,
      termsAcceptedAt: DateTime(2026, 1, 1),
    ),
    Profile(
      id: 'demo-superadmin',
      email: 'superadmin@doggo.app',
      fullName: 'Sergio Superadmin',
      role: UserRole.superadmin,
      status: UserStatus.approved,
      termsAcceptedAt: DateTime(2026, 1, 1),
    ),
    Profile(
      id: 'demo-suspended',
      email: 'suspendido@doggo.app',
      fullName: 'Sara Suspendida',
      role: UserRole.owner,
      status: UserStatus.suspended,
      termsAcceptedAt: DateTime(2026, 1, 1),
    ),
  ];

  /// Cuentas precargadas para el botón "Cambiar de rol" del modo demo.
  static const demoAccountByRole = {
    UserRole.owner: 'dueno@doggo.app',
    UserRole.sitter: 'cuidador@doggo.app',
    UserRole.admin: 'admin@doggo.app',
    UserRole.superadmin: 'superadmin@doggo.app',
  };

  final _users = <String, _DemoUser>{};
  final _dogs = <Dog>[
    const Dog(
      id: 'demo-dog-rocky',
      ownerId: 'demo-owner',
      name: 'Rocky',
      breed: 'Labrador',
      size: DogSize.large,
    ),
    const Dog(
      id: 'demo-dog-luna',
      ownerId: 'demo-owner',
      name: 'Luna',
      breed: 'Beagle',
      size: DogSize.medium,
    ),
  ];
  final _bookings = <Booking>[];
  final _controller = StreamController<Profile?>.broadcast();
  Profile? _current;
  var _nextId = 1;

  @override
  Profile? get currentProfile => _current;

  @override
  Stream<Profile?> authChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  void _setCurrent(Profile? p) {
    _current = p;
    if (p != null) _users[p.email] = _users[p.email]!.withProfile(p);
    _controller.add(p);
  }

  @override
  Future<Profile> signIn({
    required String email,
    required String password,
  }) async {
    await _latency();
    final user = _users[email.trim().toLowerCase()];
    if (user == null || user.password != password) {
      throw const AuthFailure('Correo o contraseña incorrectos.');
    }
    if (user.profile.status == UserStatus.suspended) {
      throw const AccountSuspendedFailure();
    }
    _setCurrent(user.profile);
    return user.profile;
  }

  @override
  Future<Profile> signUp({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
    required bool acceptedTerms,
  }) async {
    await _latency();
    final normalized = email.trim().toLowerCase();
    if (!role.isSelectable) {
      throw const AuthFailure('Ese rol no se puede elegir al registrarse.');
    }
    if (!acceptedTerms) {
      throw const AuthFailure(
        'Debes confirmar que eres mayor de 18 años y aceptar los términos.',
      );
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      throw const AuthFailure('Escribe un correo válido.');
    }
    if (password.length < 6) {
      throw const AuthFailure(
        'La contraseña debe tener al menos 6 caracteres.',
      );
    }
    if (fullName.trim().isEmpty) {
      throw const AuthFailure('Escribe tu nombre.');
    }
    if (_users.containsKey(normalized)) {
      throw const AuthFailure('Ya existe una cuenta con ese correo.');
    }
    final profile = Profile(
      id: 'demo-new-${_nextId++}',
      email: normalized,
      fullName: fullName.trim(),
      role: role,
      status: role == UserRole.sitter
          ? UserStatus.pendingReview
          : UserStatus.approved,
      termsAcceptedAt: DateTime.now(),
    );
    _users[normalized] = _DemoUser(profile, password);
    _setCurrent(profile);
    return profile;
  }

  @override
  Future<void> signOut() async {
    _setCurrent(null);
  }

  @override
  Future<Profile> switchRole(UserRole role) async {
    await _latency();
    final me = _current;
    if (me == null) throw const AuthFailure('Inicia sesión primero.');
    if (!me.role.isSelectable || !role.isSelectable) {
      throw const AuthFailure('Tu rol no se puede cambiar desde ajustes.');
    }
    if (_hasActiveBookings(me)) {
      throw const AuthFailure(
        'No puedes cambiar de rol mientras tengas reservas activas.',
      );
    }
    final updated = me.copyWith(
      role: role,
      status: role == UserRole.sitter && !me.verified
          ? UserStatus.pendingReview
          : UserStatus.approved,
    );
    _setCurrent(updated);
    return updated;
  }

  @override
  Future<List<SitterSummary>> fetchSitters() async {
    await _latency();
    return List.unmodifiable(_demoSitters);
  }

  @override
  Future<SitterSummary?> fetchSitter(String id) async {
    await _latency();
    for (final s in _demoSitters) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<List<Review>> fetchReviews(String sitterId) async {
    await _latency();
    final list = _demoReviews.where((r) => r.sitterId == sitterId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<List<Dog>> fetchMyDogs() async {
    await _latency();
    final me = _current;
    if (me == null) return const [];
    return _dogs.where((d) => d.ownerId == me.id).toList();
  }

  @override
  Future<Dog> addDog({
    required String name,
    required DogSize size,
    String? breed,
  }) async {
    await _latency();
    final me = _current;
    if (me == null || me.role != UserRole.owner) {
      throw const ValidationFailure('Solo los dueños pueden registrar perros.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 40) {
      throw const ValidationFailure(
        'Escribe el nombre de tu perro (máx. 40 caracteres).',
      );
    }
    final dog = Dog(
      id: 'demo-dog-${_nextId++}',
      ownerId: me.id,
      name: trimmed,
      size: size,
      breed: (breed == null || breed.trim().isEmpty) ? null : breed.trim(),
    );
    _dogs.add(dog);
    return dog;
  }

  @override
  Future<Booking> createBooking({
    required String sitterId,
    required String dogId,
    required ServiceType service,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    await _latency();
    final me = _current;
    if (me == null ||
        me.role != UserRole.owner ||
        me.status != UserStatus.approved) {
      throw const ValidationFailure('Tu cuenta no puede hacer reservas.');
    }
    SitterSummary? sitter;
    for (final s in _demoSitters) {
      if (s.id == sitterId) sitter = s;
    }
    if (sitter == null || sitter.id == me.id) {
      throw const ValidationFailure('Este cuidador no está disponible.');
    }
    Dog? dog;
    for (final d in _dogs) {
      if (d.id == dogId && d.ownerId == me.id) dog = d;
    }
    if (dog == null) throw const ValidationFailure('Elige uno de tus perros.');
    final price = sitter.services[service];
    if (price == null) {
      throw const ValidationFailure('Este cuidador no ofrece ese servicio.');
    }
    if (!startAt.isAfter(DateTime.now())) {
      throw const ValidationFailure('Elige una fecha y hora en el futuro.');
    }
    if (!startIsBookable(startAt)) {
      throw const ValidationFailure(
        'Reserva con al menos 1 hora de anticipación: el cuidador necesita tiempo para responder.',
      );
    }
    if (!endAt.isAfter(startAt)) {
      throw const ValidationFailure(
        'La hora de fin debe ser posterior a la de inicio.',
      );
    }
    final now = DateTime.now();
    final booking = Booking(
      id: 'demo-booking-${_nextId++}',
      ownerId: me.id,
      sitterId: sitter.id,
      sitterName: sitter.name,
      dogId: dog.id,
      dogName: dog.name,
      service: service,
      startAt: startAt,
      endAt: endAt,
      totalCop: bookingTotal(service, price, startAt, endAt),
      status: BookingStatus.pending,
      createdAt: now,
      responseDeadline: responseDeadline(now, startAt),
    );
    _bookings.add(booking);
    return booking;
  }

  bool _hasActiveBookings(Profile profile) => _bookings.any(
    (b) =>
        (b.ownerId == profile.id || b.sitterId == profile.id) &&
        b.status.isActive,
  );

  Future<void> _latency() =>
      Future<void>.delayed(const Duration(milliseconds: 250));
}

class _DemoUser {
  const _DemoUser(this.profile, this.password);
  final Profile profile;
  final String password;

  _DemoUser withProfile(Profile p) => _DemoUser(p, password);
}

/// La cuenta de prueba de cuidador y los 10 aprobados de `supabase/seed.sql` (Bogotá), con la
/// ubicación aproximada ya desplazada. Los dos del seed en revisión no están
/// aquí a propósito: no aparecen en el mapa hasta que un admin los apruebe.
const _demoSitters = <SitterSummary>[
  // La cuenta de prueba cuidador@doggo.app (ver supabase/assign_roles.sql):
  // recibe en vivo las reservas que se hacen en el modo demo.
  SitterSummary(
    id: 'demo-sitter',
    name: 'Carlos Cuidador',
    neighborhood: 'Chapinero',
    bio: 'Cuidador de prueba: paseos y guardería en Chapinero.',
    location: LatLng(4.65480, -74.05935),
    radiusKm: 5,
    verified: true,
    services: {
      ServiceType.walk: 26000,
      ServiceType.daycare: 62000,
      ServiceType.homeVisit: 34000,
    },
  ),
  SitterSummary(
    id: 'a1000000-0000-4000-8000-000000000001',
    name: 'Laura Gómez',
    neighborhood: 'Chapinero',
    bio: 'Veterinaria de profesión. Tu perro tendrá paseos largos y mucho cariño.',
    location: LatLng(4.65026, -74.06209),
    radiusKm: 4,
    verified: true,
    ratingAvg: 4.9,
    ratingCount: 23,
    avatarUrl: 'https://i.pravatar.cc/300?img=47',
    services: {
      ServiceType.walk: 25000,
      ServiceType.homeVisit: 35000,
      ServiceType.daycare: 60000,
    },
  ),
  SitterSummary(
    id: 'a1000000-0000-4000-8000-000000000002',
    name: 'Andrés Rojas',
    neighborhood: 'Usaquén',
    bio: 'Casa con patio grande. Experiencia con razas grandes y cachorros.',
    location: LatLng(4.71100, -74.02836),
    radiusKm: 6,
    verified: true,
    ratingAvg: 4.8,
    ratingCount: 41,
    avatarUrl: 'https://i.pravatar.cc/300?img=12',
    services: {
      ServiceType.walk: 30000,
      ServiceType.boarding: 85000,
      ServiceType.daycare: 70000,
    },
  ),
  SitterSummary(
    id: 'a1000000-0000-4000-8000-000000000003',
    name: 'Camila Herrera',
    neighborhood: 'Cedritos',
    bio: 'Entrenadora canina certificada. Paseos con refuerzo positivo.',
    location: LatLng(4.72073, -74.04103),
    radiusKm: 5,
    verified: true,
    ratingAvg: 4.6,
    ratingCount: 17,
    avatarUrl: 'https://i.pravatar.cc/300?img=32',
    services: {ServiceType.walk: 28000, ServiceType.training: 90000},
  ),
  SitterSummary(
    id: 'a1000000-0000-4000-8000-000000000004',
    name: 'Julián Castro',
    neighborhood: 'Teusaquillo',
    bio: 'Estudiante de zootecnia. Hospedaje familiar cerca del parque.',
    location: LatLng(4.63964, -74.08632),
    radiusKm: 3,
    ratingAvg: 4.2,
    ratingCount: 6,
    avatarUrl: 'https://i.pravatar.cc/300?img=15',
    services: {ServiceType.boarding: 65000, ServiceType.walk: 20000},
  ),
  SitterSummary(
    id: 'a1000000-0000-4000-8000-000000000005',
    name: 'Valentina Ruiz',
    neighborhood: 'Suba',
    bio: 'Amante de los perros pequeños. Visitas a domicilio y guardería.',
    location: LatLng(4.74080, -74.09208),
    radiusKm: 5,
    ratingAvg: 4.5,
    ratingCount: 12,
    avatarUrl: 'https://i.pravatar.cc/300?img=45',
    services: {
      ServiceType.homeVisit: 30000,
      ServiceType.daycare: 55000,
      ServiceType.walk: 22000,
    },
  ),
  SitterSummary(
    id: 'a1000000-0000-4000-8000-000000000006',
    name: 'Mateo Vargas',
    neighborhood: 'Kennedy',
    bio: 'Tengo dos labradores y mucho espacio. Hospedaje nocturno.',
    location: LatLng(4.63055, -74.15009),
    radiusKm: 4,
    verified: true,
    ratingAvg: 4.0,
    ratingCount: 8,
    avatarUrl: 'https://i.pravatar.cc/300?img=53',
    services: {ServiceType.boarding: 60000, ServiceType.walk: 18000},
  ),
  SitterSummary(
    id: 'a1000000-0000-4000-8000-000000000007',
    name: 'Daniela Moreno',
    neighborhood: 'El Chicó',
    bio: 'Peluquera canina con 8 años de experiencia.',
    location: LatLng(4.67084, -74.05020),
    radiusKm: 6,
    verified: true,
    ratingAvg: 5.0,
    ratingCount: 31,
    avatarUrl: 'https://i.pravatar.cc/300?img=25',
    services: {ServiceType.grooming: 120000, ServiceType.walk: 35000},
  ),
  SitterSummary(
    id: 'a1000000-0000-4000-8000-000000000008',
    name: 'Sebastián Ortiz',
    neighborhood: 'Fontibón',
    bio: 'Corredor y ciclista: ideal para perros con mucha energía.',
    location: LatLng(4.66845, -74.14328),
    radiusKm: 8,
    ratingAvg: 3.8,
    ratingCount: 5,
    avatarUrl: 'https://i.pravatar.cc/300?img=59',
    services: {ServiceType.walk: 24000, ServiceType.training: 80000},
  ),
  SitterSummary(
    id: 'a1000000-0000-4000-8000-000000000009',
    name: 'Isabela Mejía',
    neighborhood: 'Engativá',
    bio: 'Cuido perros senior y con necesidades especiales.',
    location: LatLng(4.69750, -74.11086),
    radiusKm: 4,
    ratingAvg: 4.7,
    ratingCount: 14,
    avatarUrl: 'https://i.pravatar.cc/300?img=44',
    services: {ServiceType.homeVisit: 32000, ServiceType.boarding: 75000},
  ),
  SitterSummary(
    id: 'a1000000-0000-4000-8000-000000000010',
    name: 'Felipe Cárdenas',
    neighborhood: 'La Candelaria',
    bio: 'Apartamento en el centro. Paseos y guardería de día.',
    location: LatLng(4.59586, -74.07507),
    radiusKm: 3,
    avatarUrl: 'https://i.pravatar.cc/300?img=68',
    services: {ServiceType.walk: 21000, ServiceType.daycare: 50000},
  ),
];

final _now = DateTime.now();

/// Algunas reseñas por cuidador (las cifras de `ratingCount` incluyen más).
final _demoReviews = <Review>[
  Review(
    id: 'r1',
    sitterId: 'a1000000-0000-4000-8000-000000000001',
    authorName: 'Marcela D.',
    rating: 5,
    comment: 'Rocky volvió feliz y cansado. Muy puntual y cariñosa.',
    createdAt: _now.subtract(const Duration(days: 3)),
  ),
  Review(
    id: 'r2',
    sitterId: 'a1000000-0000-4000-8000-000000000001',
    authorName: 'Juan P.',
    rating: 5,
    comment: 'Nos mandaba fotos durante todo el paseo.',
    createdAt: _now.subtract(const Duration(days: 12)),
  ),
  Review(
    id: 'r3',
    sitterId: 'a1000000-0000-4000-8000-000000000001',
    authorName: 'Sofía R.',
    rating: 4,
    comment: 'Muy buena, llegó 10 minutos tarde.',
    createdAt: _now.subtract(const Duration(days: 30)),
  ),
  Review(
    id: 'r4',
    sitterId: 'a1000000-0000-4000-8000-000000000002',
    authorName: 'Marcela D.',
    rating: 5,
    comment: 'Excelente trato y mucha comunicación.',
    createdAt: _now.subtract(const Duration(days: 5)),
  ),
  Review(
    id: 'r5',
    sitterId: 'a1000000-0000-4000-8000-000000000002',
    authorName: 'Andrea L.',
    rating: 4,
    comment: 'El patio es enorme, a mi perro le encantó.',
    createdAt: _now.subtract(const Duration(days: 20)),
  ),
  Review(
    id: 'r6',
    sitterId: 'a1000000-0000-4000-8000-000000000003',
    authorName: 'Marcela D.',
    rating: 4,
    comment: 'Muy profesional, repetiremos.',
    createdAt: _now.subtract(const Duration(days: 8)),
  ),
  Review(
    id: 'r7',
    sitterId: 'a1000000-0000-4000-8000-000000000006',
    authorName: 'Camilo T.',
    rating: 4,
    comment: 'Todo bien, un poco de retraso al llegar.',
    createdAt: _now.subtract(const Duration(days: 15)),
  ),
  Review(
    id: 'r8',
    sitterId: 'a1000000-0000-4000-8000-000000000007',
    authorName: 'Marcela D.',
    rating: 5,
    comment: 'Dejó a Rocky precioso. Súper recomendada.',
    createdAt: _now.subtract(const Duration(days: 2)),
  ),
];
