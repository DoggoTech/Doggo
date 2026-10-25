import 'dart:async';

import 'package:latlong2/latlong.dart';

import '../models/availability.dart';
import '../contact_filter.dart';
import '../models/booking.dart';
import '../models/contact_info.dart';
import '../models/dog.dart';
import '../models/profile.dart';
import '../models/report.dart';
import '../models/review.dart';
import '../models/service_type.dart';
import '../models/sitter_summary.dart';
import '../booking_rules.dart';
import '../pricing.dart';
import '../repositories/repository.dart';

const demoPassword = 'doggo123';

/// Implementación en memoria: sin backend ni persistencia entre recargas.
class DemoRepository implements Repository {
  /// [clock] permite fijar la hora en las pruebas (por defecto, la real).
  DemoRepository({DateTime Function()? clock}) : _now = clock ?? DateTime.now {
    for (final p in _seedProfiles) {
      _users[p.email] = _DemoUser(p, demoPassword);
    }
    // Las solicitudes sin respuesta vencen solas al pasar su plazo.
    Timer.periodic(const Duration(seconds: 15), (_) => _expireOverdue());
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

  final DateTime Function() _now;
  final _users = <String, _DemoUser>{};
  final _dogs = <Dog>[
    const Dog(
      id: 'demo-dog-rocky',
      ownerId: 'demo-owner',
      name: 'Rocky',
      breed: 'Labrador',
      size: DogSize.large,
      notes: 'Muy juguetón. Le dan miedo las motos.',
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
  final _reviews = [..._demoReviews];
  final _reports = <Report>[];

  /// Datos privados (teléfono, dirección): solo los ve el dueño de los datos
  /// y la contraparte de una reserva `accepted`.
  final _private = <String, PrivateData>{
    'demo-owner': const PrivateData(
      phone: '310 987 6543',
      address: 'Calle 85 #15-30, Chicó',
    ),
    'demo-sitter': const PrivateData(
      phone: '300 123 4567',
      address: 'Carrera 7 #60-20, Chapinero',
    ),
  };
  final _bookingChanges = StreamController<void>.broadcast();

  /// Cuidadores aprobados (visibles en el mapa). Mutable: el cuidador edita
  /// sus servicios y horarios.
  final _sitters = [..._demoSitters];

  /// Perfil en preparación de cuidadores que aún no están en el mapa.
  final _pendingSitters = <String, SitterSummary>{};
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
      termsAcceptedAt: _now(),
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
    return List.unmodifiable(_sitters);
  }

  @override
  Future<SitterSummary?> fetchSitter(String id) async {
    await _latency();
    for (final s in _sitters) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<List<Review>> fetchReviews(String sitterId) async {
    await _latency();
    final list = _reviews.where((r) => r.sitterId == sitterId).toList()
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
    String? notes,
  }) async {
    await _latency();
    final me = _requireOwner();
    final dog = _validDog(
      Dog(
        id: 'demo-dog-${_nextId++}',
        ownerId: me.id,
        name: name,
        size: size,
        breed: breed,
        notes: notes,
      ),
    );
    _dogs.add(dog);
    return dog;
  }

  @override
  Future<Dog> updateDog(Dog dog) async {
    await _latency();
    final me = _requireOwner();
    final i = _dogs.indexWhere((d) => d.id == dog.id && d.ownerId == me.id);
    if (i < 0) throw const ValidationFailure('Ese perro no existe.');
    final updated = _validDog(
      Dog(
        id: dog.id,
        ownerId: me.id,
        name: dog.name,
        size: dog.size,
        breed: dog.breed,
        notes: dog.notes,
      ),
    );
    _dogs[i] = updated;
    return updated;
  }

  @override
  Future<void> deleteDog(String dogId) async {
    await _latency();
    final me = _requireOwner();
    if (!_dogs.any((d) => d.id == dogId && d.ownerId == me.id)) {
      throw const ValidationFailure('Ese perro no existe.');
    }
    if (_bookings.any((b) => b.dogId == dogId && b.status.isActive)) {
      throw const ValidationFailure(
        'No puedes borrar un perro con reservas activas.',
      );
    }
    _dogs.removeWhere((d) => d.id == dogId);
  }

  Profile _requireOwner() {
    final me = _current;
    if (me == null || me.role != UserRole.owner) {
      throw const ValidationFailure('Solo los dueños pueden registrar perros.');
    }
    return me;
  }

  /// Normaliza y valida un perro con las mismas reglas que la base.
  Dog _validDog(Dog d) {
    final name = d.name.trim();
    if (name.isEmpty || name.length > 40) {
      throw const ValidationFailure(
        'Escribe el nombre de tu perro (máx. 40 caracteres).',
      );
    }
    final breed = d.breed?.trim();
    final notes = d.notes?.trim();
    if (notes != null && notes.length > 1000) {
      throw const ValidationFailure(
        'Las notas pueden tener hasta 1000 caracteres.',
      );
    }
    if (notes != null && containsContactInfo(notes)) {
      throw const ValidationFailure(contactInfoMessage);
    }
    return Dog(
      id: d.id,
      ownerId: d.ownerId,
      name: name,
      size: d.size,
      breed: (breed == null || breed.isEmpty) ? null : breed,
      notes: (notes == null || notes.isEmpty) ? null : notes,
    );
  }

  @override
  Future<String?> fetchDogNotesForBooking(String bookingId) async {
    await _latency();
    final me = _current;
    if (me == null) return null;
    final b = _bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b == null) return null;
    final isOwner = b.ownerId == me.id;
    final isAcceptedSitter =
        b.sitterId == me.id && b.status == BookingStatus.accepted;
    if (!isOwner && !isAcceptedSitter) return null;
    return _dogs.where((d) => d.id == b.dogId).firstOrNull?.notes;
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
    for (final s in _sitters) {
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
    if (!sitter.availability.allows(startAt)) {
      throw const ValidationFailure(
        'Ese horario está fuera de la disponibilidad del cuidador.',
      );
    }
    final price = sitter.services[service];
    if (price == null) {
      throw const ValidationFailure('Este cuidador no ofrece ese servicio.');
    }
    if (!startAt.isAfter(_now())) {
      throw const ValidationFailure('Elige una fecha y hora en el futuro.');
    }
    if (!startIsBookable(startAt, now: _now())) {
      throw const ValidationFailure(
        'Reserva con al menos 1 hora de anticipación: el cuidador necesita tiempo para responder.',
      );
    }
    if (!endAt.isAfter(startAt)) {
      throw const ValidationFailure(
        'La hora de fin debe ser posterior a la de inicio.',
      );
    }
    final now = _now();
    final booking = Booking(
      id: 'demo-booking-${_nextId++}',
      ownerId: me.id,
      ownerName: me.fullName,
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
    _notifyBookings();
    return booking;
  }

  @override
  Stream<List<Booking>> watchMyBookings() async* {
    _expireOverdue();
    yield _myBookings();
    await for (final _ in _bookingChanges.stream) {
      yield _myBookings();
    }
  }

  List<Booking> _myBookings() {
    final me = _current;
    if (me == null) return const [];
    return _bookings
        .where((b) => b.ownerId == me.id || b.sitterId == me.id)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _notifyBookings() => _bookingChanges.add(null);

  void _expireOverdue() {
    final now = _now();
    var changed = false;
    for (var i = 0; i < _bookings.length; i++) {
      final b = _bookings[i];
      if (b.status == BookingStatus.pending &&
          !now.isBefore(b.responseDeadline)) {
        _bookings[i] = b.copyWith(status: BookingStatus.expired);
        changed = true;
      }
    }
    if (changed) _notifyBookings();
  }

  /// Reserva del cuidador con sesión, o error si no le pertenece.
  int _sitterBookingIndex(String bookingId) {
    final me = _current;
    if (me == null ||
        me.role != UserRole.sitter ||
        me.status != UserStatus.approved) {
      throw const ValidationFailure(
        'Solo un cuidador aprobado puede gestionar solicitudes.',
      );
    }
    final i = _bookings.indexWhere(
      (b) => b.id == bookingId && b.sitterId == me.id,
    );
    if (i < 0) throw const ValidationFailure('Esa reserva no existe.');
    return i;
  }

  @override
  Future<Booking> respondToBooking(
    String bookingId, {
    required bool accept,
  }) async {
    await _latency();
    _expireOverdue();
    final i = _sitterBookingIndex(bookingId);
    final b = _bookings[i];
    if (b.status == BookingStatus.expired) {
      throw const ValidationFailure('El plazo para responder ya venció.');
    }
    if (b.status != BookingStatus.pending) {
      throw const ValidationFailure('Esta solicitud ya fue respondida.');
    }
    final updated = b.copyWith(
      status: accept ? BookingStatus.accepted : BookingStatus.rejected,
    );
    _bookings[i] = updated;
    _notifyBookings();
    return updated;
  }

  @override
  Future<Booking> completeBooking(String bookingId) async {
    await _latency();
    final i = _sitterBookingIndex(bookingId);
    final b = _bookings[i];
    if (b.status != BookingStatus.accepted) {
      throw const ValidationFailure('Solo se completan reservas aceptadas.');
    }
    final updated = b.copyWith(status: BookingStatus.completed);
    _bookings[i] = updated;
    _notifyBookings();
    return updated;
  }

  @override
  Future<Booking> cancelBooking(String bookingId) async {
    await _latency();
    _expireOverdue();
    final me = _current;
    final i = _bookings.indexWhere(
      (b) => b.id == bookingId && b.ownerId == me?.id,
    );
    if (me == null || i < 0) {
      throw const ValidationFailure('Esa reserva no existe.');
    }
    if (!_bookings[i].status.isActive) {
      throw const ValidationFailure('Esta reserva ya no se puede cancelar.');
    }
    final updated = _bookings[i].copyWith(status: BookingStatus.cancelled);
    _bookings[i] = updated;
    _notifyBookings();
    return updated;
  }

  @override
  Future<ContactInfo?> fetchCounterpartContact(String bookingId) async {
    await _latency();
    final me = _current;
    final b = _bookings.where((b) => b.id == bookingId).firstOrNull;
    if (me == null || b == null || b.status != BookingStatus.accepted) {
      return null;
    }
    if (b.ownerId != me.id && b.sitterId != me.id) return null;
    final otherId = b.ownerId == me.id ? b.sitterId : b.ownerId;
    final otherName = b.ownerId == me.id ? b.sitterName : b.ownerName;
    final data = _private[otherId] ?? const PrivateData();
    return ContactInfo(
      name: otherName,
      phone: data.phone,
      address: data.address,
    );
  }

  @override
  Future<PrivateData> fetchMyPrivateData() async {
    await _latency();
    final me = _current;
    if (me == null) return const PrivateData();
    return _private[me.id] ?? const PrivateData();
  }

  @override
  Future<void> saveMyPrivateData(PrivateData data) async {
    await _latency();
    final me = _current;
    if (me == null) throw const ValidationFailure('Inicia sesión primero.');
    final phone = data.phone?.trim();
    final address = data.address?.trim();
    if (phone != null &&
        phone.isNotEmpty &&
        !RegExp(r'^[0-9+() -]{7,20}$').hasMatch(phone)) {
      throw const ValidationFailure(
        'Escribe un teléfono válido (solo números, espacios y +).',
      );
    }
    if (address != null && address.length > 200) {
      throw const ValidationFailure(
        'La dirección puede tener hasta 200 caracteres.',
      );
    }
    _private[me.id] = PrivateData(
      phone: (phone == null || phone.isEmpty) ? null : phone,
      address: (address == null || address.isEmpty) ? null : address,
    );
  }

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) async {
    await _latency();
    final me = _current;
    final i = _bookings.indexWhere(
      (b) => b.id == bookingId && b.ownerId == me?.id,
    );
    if (me == null || i < 0) {
      throw const ValidationFailure('Esa reserva no existe.');
    }
    final b = _bookings[i];
    if (b.status != BookingStatus.completed) {
      throw const ValidationFailure(
        'Solo puedes calificar reservas completadas.',
      );
    }
    if (b.reviewed) {
      throw const ValidationFailure('Ya calificaste esta reserva.');
    }
    if (rating < 1 || rating > 5) {
      throw const ValidationFailure('Elige de 1 a 5 estrellas.');
    }
    final text = comment?.trim();
    if (text != null && text.length > 500) {
      throw const ValidationFailure(
        'La reseña puede tener hasta 500 caracteres.',
      );
    }
    if (text != null && containsContactInfo(text)) {
      throw const ValidationFailure(contactInfoMessage);
    }
    final parts = me.fullName.trim().split(' ');
    final author = parts.length > 1
        ? '${parts.first} ${parts[1][0]}.'
        : parts.first;
    _reviews.add(
      Review(
        id: 'demo-review-${_nextId++}',
        sitterId: b.sitterId,
        authorName: author,
        rating: rating,
        comment: (text == null || text.isEmpty) ? null : text,
        createdAt: _now(),
      ),
    );
    _bookings[i] = b.copyWith(reviewed: true);
    // Recalcula la calificación que muestran el mapa y el perfil.
    final si = _sitters.indexWhere((s) => s.id == b.sitterId);
    if (si >= 0) {
      final s0 = _sitters[si];
      final count = s0.ratingCount + 1;
      final avg = ((s0.ratingAvg ?? 0) * s0.ratingCount + rating) / count;
      _sitters[si] = s0.copyWith(
        ratingAvg: double.parse(avg.toStringAsFixed(1)),
        ratingCount: count,
      );
    }
    _notifyBookings();
  }

  @override
  Future<void> createReport({
    required String reportedUserId,
    required ReportReason reason,
    String? bookingId,
    String? comment,
  }) async {
    await _latency();
    final me = _current;
    if (me == null ||
        !me.role.isSelectable ||
        me.status != UserStatus.approved) {
      throw const ValidationFailure('Tu cuenta no puede enviar reportes.');
    }
    if (reportedUserId == me.id) {
      throw const ValidationFailure('No puedes reportarte a ti mismo.');
    }
    if (bookingId != null &&
        !_bookings.any(
          (b) =>
              b.id == bookingId &&
              ((b.ownerId == me.id && b.sitterId == reportedUserId) ||
                  (b.sitterId == me.id && b.ownerId == reportedUserId)),
        )) {
      throw const ValidationFailure('Esa reserva no es entre ustedes dos.');
    }
    final text = comment?.trim();
    if (text != null && text.length > 1000) {
      throw const ValidationFailure(
        'El comentario puede tener hasta 1000 caracteres.',
      );
    }
    _reports.add(
      Report(
        id: 'demo-report-${_nextId++}',
        reporterId: me.id,
        reporterName: me.fullName,
        reportedUserId: reportedUserId,
        reportedName: _nameOf(reportedUserId),
        bookingId: bookingId,
        reason: reason,
        comment: (text == null || text.isEmpty) ? null : text,
        status: ReportStatus.open,
        createdAt: _now(),
      ),
    );
  }

  String _nameOf(String userId) {
    for (final u in _users.values) {
      if (u.profile.id == userId) return u.profile.fullName;
    }
    for (final s in _sitters) {
      if (s.id == userId) return s.name;
    }
    return 'Usuario';
  }

  @override
  Future<void> saveMyBio(String bio) async {
    await _latency();
    final me = _requireSitter();
    final text = bio.trim();
    if (text.length > 600) {
      throw const ValidationFailure('La bio puede tener hasta 600 caracteres.');
    }
    if (containsContactInfo(text)) {
      throw const ValidationFailure(contactInfoMessage);
    }
    await fetchMySitterProfile();
    _updateMySitter((s) => s.copyWith(bio: text));
    _setCurrent(me.copyWith(bio: text));
  }

  /// El cuidador con sesión (rol sitter, aunque esté en revisión).
  Profile _requireSitter() {
    final me = _current;
    if (me == null ||
        me.role != UserRole.sitter ||
        me.status == UserStatus.suspended) {
      throw const ValidationFailure(
        'Solo los cuidadores tienen servicios y horarios.',
      );
    }
    return me;
  }

  @override
  Future<SitterSummary> fetchMySitterProfile() async {
    await _latency();
    final me = _requireSitter();
    for (final s in _sitters) {
      if (s.id == me.id) return s;
    }
    return _pendingSitters.putIfAbsent(
      me.id,
      () => SitterSummary(
        id: me.id,
        name: me.fullName,
        neighborhood: 'Bogotá',
        bio: me.bio ?? '',
        location: const LatLng(4.6533, -74.0836),
        radiusKm: 5,
        services: const {},
      ),
    );
  }

  void _updateMySitter(SitterSummary Function(SitterSummary) change) {
    final me = _requireSitter();
    final i = _sitters.indexWhere((s) => s.id == me.id);
    if (i >= 0) {
      _sitters[i] = change(_sitters[i]);
    } else {
      _pendingSitters[me.id] = change(_pendingSitters[me.id]!);
    }
  }

  @override
  Future<void> saveMyServices(Map<ServiceType, int> services) async {
    await fetchMySitterProfile();
    if (services.isEmpty) {
      throw const ValidationFailure('Activa al menos un servicio.');
    }
    if (services.values.any((p) => p < 5000 || p > 2000000)) {
      throw const ValidationFailure(
        'Los precios deben estar entre \$5.000 y \$2.000.000.',
      );
    }
    _updateMySitter((s) => s.copyWith(services: Map.unmodifiable(services)));
  }

  @override
  Future<void> saveMyAvailability(WeeklyAvailability availability) async {
    await fetchMySitterProfile();
    if (availability.days.isEmpty) {
      throw const ValidationFailure('Elige al menos un día de atención.');
    }
    for (final w in availability.days.values) {
      if (w.startMinute < 0 ||
          w.endMinute > 1439 ||
          w.endMinute < w.startMinute) {
        throw const ValidationFailure(
          'Revisa los horarios: la hora de fin debe ser posterior al inicio.',
        );
      }
    }
    _updateMySitter((s) => s.copyWith(availability: availability));
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
