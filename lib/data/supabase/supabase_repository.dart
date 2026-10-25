import 'dart:async';
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../booking_rules.dart';
import '../contact_filter.dart';
import '../models/admin.dart';
import '../models/availability.dart';
import '../models/booking.dart';
import '../models/contact_info.dart';
import '../models/dog.dart';
import '../models/profile.dart';
import '../models/report.dart';
import '../models/review.dart';
import '../models/service_type.dart';
import '../models/sitter_summary.dart';
import '../repositories/repository.dart';

/// Implementación real sobre Supabase. La seguridad la impone la base (RLS,
/// triggers y RPC, ver supabase/schema.sql); aquí se repiten las validaciones
/// de entrada solo para dar el mismo mensaje claro que el modo demo antes de
/// ir a la red, y se traducen los códigos de error de la base a esos mensajes.
class SupabaseRepository implements Repository {
  SupabaseRepository({SupabaseClient? client})
    : _db = client ?? Supabase.instance.client {
    _ready = _restoreSession();
    // Si la sesión se cierra por fuera (token vencido, otra pestaña), la app
    // vuelve al login.
    _db.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut && _current != null) {
        _setCurrent(null);
      }
    });
  }

  final SupabaseClient _db;
  final _controller = StreamController<Profile?>.broadcast();
  late final Future<void> _ready;
  Profile? _current;

  static const _bogota = LatLng(4.6533, -74.0836);

  // ---------------------------------------------------------------------------
  // Sesión
  // ---------------------------------------------------------------------------

  @override
  Profile? get currentProfile => _current;

  @override
  Stream<Profile?> authChanges() async* {
    await _ready;
    yield _current;
    yield* _controller.stream;
  }

  void _setCurrent(Profile? p) {
    _current = p;
    _controller.add(p);
  }

  /// Al abrir la app con una sesión guardada, carga el perfil (y la cierra si
  /// la cuenta fue suspendida mientras tanto).
  Future<void> _restoreSession() async {
    if (_db.auth.currentSession == null) return;
    try {
      final p = await _loadProfile();
      if (p.status == UserStatus.suspended) {
        await _db.auth.signOut();
        return;
      }
      _current = p;
    } catch (_) {
      // Sin red o sesión inválida: se empieza sin sesión.
    }
  }

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw const AuthFailure('Inicia sesión primero.');
    return id;
  }

  Future<Profile> _loadProfile() async {
    final user = _db.auth.currentUser!;
    final row = await _db
        .from('profiles')
        .select(
          'id, role, full_name, avatar_url, bio, status, verified, terms_accepted_at',
        )
        .eq('id', user.id)
        .single();
    return Profile(
      id: row['id'] as String,
      email: user.email ?? '',
      fullName: row['full_name'] as String? ?? '',
      role: _enum(UserRole.values, row['role'] as String),
      status: _enum(UserStatus.values, row['status'] as String),
      verified: row['verified'] as bool? ?? false,
      avatarUrl: row['avatar_url'] as String?,
      bio: row['bio'] as String?,
      termsAcceptedAt: _date(row['terms_accepted_at']),
    );
  }

  Future<Profile> _reloadProfile() async {
    final p = await _loadProfile();
    _setCurrent(p);
    return p;
  }

  @override
  Future<Profile> signIn({required String email, required String password}) =>
      _guard(auth: true, () async {
        try {
          await _db.auth.signInWithPassword(
            email: email.trim().toLowerCase(),
            password: password,
          );
        } on AuthException catch (e) {
          if (e.statusCode == '400' || e.code == 'invalid_credentials') {
            throw const AuthFailure('Correo o contraseña incorrectos.');
          }
          rethrow;
        }
        final p = await _loadProfile();
        if (p.status == UserStatus.suspended) {
          await _db.auth.signOut();
          throw const AccountSuspendedFailure();
        }
        _setCurrent(p);
        return p;
      });

  @override
  Future<Profile> signUp({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
    required bool acceptedTerms,
  }) => _guard(auth: true, () async {
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
    try {
      final res = await _db.auth.signUp(
        email: normalized,
        password: password,
        // El trigger de registro crea el perfil con estos datos.
        data: {
          'role': role.name,
          'full_name': fullName.trim(),
          'accepted_terms': true,
        },
      );
      if (res.session == null) {
        throw const AuthFailure(
          'Revisa tu correo para confirmar la cuenta y luego inicia sesión.',
        );
      }
    } on AuthException catch (e) {
      if (e.code == 'user_already_exists' ||
          e.message.toLowerCase().contains('already registered')) {
        throw const AuthFailure('Ya existe una cuenta con ese correo.');
      }
      rethrow;
    }
    return _reloadProfile();
  });

  @override
  Future<void> signOut() async {
    try {
      await _db.auth.signOut();
    } catch (_) {
      // Aunque falle la red, la sesión local se cierra.
    }
    _setCurrent(null);
  }

  @override
  Future<Profile> switchRole(UserRole role) => _guard(
    auth: true,
    overrides: const {
      'active_bookings':
          'No puedes cambiar de rol mientras tengas reservas activas.',
    },
    () async {
      await _db.rpc('switch_role', params: {'new_role': role.name});
      return _reloadProfile();
    },
  );

  // ---------------------------------------------------------------------------
  // Cuidadores
  // ---------------------------------------------------------------------------

  static const _sitterColumns =
      'id, full_name, avatar_url, bio, approx_lat, approx_lng, radius_km, '
      'neighborhood, status, verified, '
      'sitter_services(service_type, price_cop, active), '
      'sitter_availability(weekday, start_minute, end_minute)';

  Future<Map<String, ({double avg, int count})>> _ratings(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final rows = await _db
        .from('sitter_rating_stats')
        .select()
        .inFilter('sitter_id', ids);
    return {
      for (final r in rows)
        r['sitter_id'] as String: (
          avg: (r['rating_avg'] as num).toDouble(),
          count: r['rating_count'] as int,
        ),
    };
  }

  SitterSummary _sitter(
    Map<String, dynamic> r,
    Map<String, ({double avg, int count})> ratings,
  ) {
    final lat = (r['approx_lat'] as num?)?.toDouble();
    final lng = (r['approx_lng'] as num?)?.toDouble();
    final services = <ServiceType, int>{
      for (final s in (r['sitter_services'] as List? ?? const []))
        if (s['active'] == true)
          _enum(ServiceType.values, s['service_type'] as String):
              s['price_cop'] as int,
    };
    final windows = (r['sitter_availability'] as List? ?? const []);
    final rating = ratings[r['id']];
    return SitterSummary(
      id: r['id'] as String,
      name: r['full_name'] as String? ?? '',
      neighborhood: r['neighborhood'] as String? ?? 'Bogotá',
      bio: r['bio'] as String? ?? '',
      location: lat == null || lng == null ? _bogota : LatLng(lat, lng),
      radiusKm: r['radius_km'] as int? ?? 5,
      services: services,
      avatarUrl: r['avatar_url'] as String?,
      verified: r['verified'] as bool? ?? false,
      ratingAvg: rating?.avg,
      ratingCount: rating?.count ?? 0,
      // Sin filas = sin restricción en la base; la app ofrece 7:00 a 19:00.
      availability: windows.isEmpty
          ? WeeklyAvailability.standard
          : WeeklyAvailability({
              for (final w in windows)
                w['weekday'] as int: DayWindow(
                  w['start_minute'] as int,
                  w['end_minute'] as int,
                ),
            }),
      locationConfirmed: lat != null && lng != null,
    );
  }

  Future<List<SitterSummary>> _sitters(List<Map<String, dynamic>> rows) async {
    final ratings = await _ratings([for (final r in rows) r['id'] as String]);
    return [for (final r in rows) _sitter(r, ratings)];
  }

  /// En el mapa: aprobado, con zona de servicio y al menos un servicio activo.
  static bool _isVisible(SitterSummary s) =>
      s.services.isNotEmpty && s.locationConfirmed;

  @override
  Future<List<SitterSummary>> fetchSitters() => _guard(() async {
    final rows = await _db
        .from('profiles')
        .select(_sitterColumns)
        .eq('role', 'sitter')
        .eq('status', 'approved');
    return (await _sitters(rows)).where(_isVisible).toList();
  });

  @override
  Future<SitterSummary?> fetchSitter(String id) => _guard(() async {
    final rows = await _db
        .from('profiles')
        .select(_sitterColumns)
        .eq('id', id)
        .eq('role', 'sitter')
        .eq('status', 'approved');
    final list = (await _sitters(rows)).where(_isVisible);
    return list.isEmpty ? null : list.first;
  });

  @override
  Future<List<Review>> fetchReviews(String sitterId) => _guard(() async {
    final rows = await _db
        .from('reviews')
        .select('id, sitter_id, author_name, rating, comment, created_at')
        .eq('sitter_id', sitterId)
        .order('created_at', ascending: false);
    return [
      for (final r in rows)
        Review(
          id: r['id'] as String,
          sitterId: r['sitter_id'] as String,
          authorName: r['author_name'] as String? ?? '',
          rating: r['rating'] as int,
          comment: r['comment'] as String?,
          createdAt: _date(r['created_at'])!,
        ),
    ];
  });

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
  Future<SitterSummary> fetchMySitterProfile() => _guard(() async {
    final me = _requireSitter();
    final row = await _db
        .from('profiles')
        .select(_sitterColumns)
        .eq('id', me.id)
        .single();
    return (await _sitters([row])).single;
  });

  @override
  Future<void> saveMyServices(Map<ServiceType, int> services) =>
      _guard(() async {
        final me = _requireSitter();
        if (services.isEmpty) {
          throw const ValidationFailure('Activa al menos un servicio.');
        }
        if (services.values.any((p) => p < 5000 || p > 2000000)) {
          throw const ValidationFailure(
            'Los precios deben estar entre \$5.000 y \$2.000.000.',
          );
        }
        await _db.from('sitter_services').upsert([
          for (final e in services.entries)
            {
              'sitter_id': me.id,
              'service_type': _snake(e.key.name),
              'price_cop': e.value,
              'active': true,
            },
        ], onConflict: 'sitter_id,service_type');
        // Los que ya no ofrece se desactivan (se conserva el precio).
        await _db
            .from('sitter_services')
            .update({'active': false})
            .eq('sitter_id', me.id)
            .not(
              'service_type',
              'in',
              '(${services.keys.map((s) => _snake(s.name)).join(',')})',
            );
      });

  @override
  Future<void> saveMyAvailability(WeeklyAvailability availability) => _guard(
    () async {
      final me = _requireSitter();
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
      await _db.from('sitter_availability').delete().eq('sitter_id', me.id);
      await _db.from('sitter_availability').insert([
        for (final e in availability.days.entries)
          {
            'sitter_id': me.id,
            'weekday': e.key,
            'start_minute': e.value.startMinute,
            'end_minute': e.value.endMinute,
          },
      ]);
    },
  );

  @override
  Future<void> saveMyBio(String bio) => _guard(() async {
    final me = _requireSitter();
    final text = bio.trim();
    if (text.length > 600) {
      throw const ValidationFailure('La bio puede tener hasta 600 caracteres.');
    }
    if (containsContactInfo(text)) {
      throw const ValidationFailure(contactInfoMessage);
    }
    await _db.from('profiles').update({'bio': text}).eq('id', me.id);
    _setCurrent(me.copyWith(bio: text));
  });

  @override
  Future<void> saveMyServiceArea({
    required LatLng exact,
    required String neighborhood,
    required int radiusKm,
  }) => _guard(() async {
    final me = _requireSitter();
    final name = neighborhood.trim();
    if (name.isEmpty || name.length > 60) {
      throw const ValidationFailure('Escribe tu barrio (máx. 60 caracteres).');
    }
    if (containsContactInfo(name)) {
      throw const ValidationFailure(contactInfoMessage);
    }
    if (radiusKm < 1 || radiusKm > 20) {
      throw const ValidationFailure('El radio debe estar entre 1 y 20 km.');
    }
    if (exact.latitude.abs() > 90 || exact.longitude.abs() > 180) {
      throw const ValidationFailure('Esa ubicación no es válida.');
    }
    await _db
        .from('profiles')
        .update({'neighborhood': name, 'radius_km': radiusKm})
        .eq('id', me.id);
    // La exacta queda privada; el trigger publica la aproximada en el mapa.
    await _db
        .from('profile_private')
        .update({'exact_lat': exact.latitude, 'exact_lng': exact.longitude})
        .eq('id', me.id);
  });

  @override
  Future<void> saveMyPhoto(
    Uint8List bytes,
    String mimeType,
  ) => _guard(() async {
    final me = _requireSitter();
    const extensions = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
    };
    final ext = extensions[mimeType];
    if (ext == null) {
      throw const ValidationFailure('La foto debe ser JPG, PNG o WEBP.');
    }
    if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
      throw const ValidationFailure('La foto puede pesar hasta 2 MB.');
    }
    // Cada cuenta escribe solo en su carpeta (política del bucket).
    final path = '${me.id}/avatar.$ext';
    final bucket = _db.storage.from('avatars');
    await bucket.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: true),
    );
    // El parámetro evita que el navegador muestre la foto anterior.
    final url =
        '${bucket.getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
    await _db.from('profiles').update({'avatar_url': url}).eq('id', me.id);
  });

  // ---------------------------------------------------------------------------
  // Perros
  // ---------------------------------------------------------------------------

  Profile _requireOwner() {
    final me = _current;
    if (me == null || me.role != UserRole.owner) {
      throw const ValidationFailure('Solo los dueños pueden registrar perros.');
    }
    return me;
  }

  /// Normaliza y valida un perro con las mismas reglas que la base.
  static ({String name, String? breed, String? notes}) _validDog(
    String name,
    String? breed,
    String? notes,
  ) {
    final n = name.trim();
    if (n.isEmpty || n.length > 40) {
      throw const ValidationFailure(
        'Escribe el nombre de tu perro (máx. 40 caracteres).',
      );
    }
    final b = breed?.trim();
    final t = notes?.trim();
    if (t != null && t.length > 1000) {
      throw const ValidationFailure(
        'Las notas pueden tener hasta 1000 caracteres.',
      );
    }
    if (t != null && containsContactInfo(t)) {
      throw const ValidationFailure(contactInfoMessage);
    }
    return (
      name: n,
      breed: (b == null || b.isEmpty) ? null : b,
      notes: (t == null || t.isEmpty) ? null : t,
    );
  }

  Dog _dog(Map<String, dynamic> r) {
    // dog_notes es 1 a 1: PostgREST lo devuelve como objeto (o lista vacía).
    final notes = r['dog_notes'];
    final text = notes is Map
        ? notes['notes'] as String?
        : notes is List && notes.isNotEmpty
        ? notes.first['notes'] as String?
        : null;
    return Dog(
      id: r['id'] as String,
      ownerId: r['owner_id'] as String,
      name: r['name'] as String,
      size: _enum(DogSize.values, r['size'] as String),
      breed: r['breed'] as String?,
      notes: text,
    );
  }

  static const _dogColumns =
      'id, owner_id, name, breed, size, dog_notes(notes)';

  @override
  Future<List<Dog>> fetchMyDogs() => _guard(() async {
    final me = _current;
    if (me == null) return const <Dog>[];
    final rows = await _db
        .from('dogs')
        .select(_dogColumns)
        .eq('owner_id', me.id)
        .order('name');
    return [for (final r in rows) _dog(r)];
  });

  Future<void> _saveNotes(String dogId, String? notes) async {
    if (notes == null) {
      await _db.from('dog_notes').delete().eq('dog_id', dogId);
    } else {
      await _db.from('dog_notes').upsert({'dog_id': dogId, 'notes': notes});
    }
  }

  @override
  Future<Dog> addDog({
    required String name,
    required DogSize size,
    String? breed,
    String? notes,
  }) => _guard(() async {
    final me = _requireOwner();
    final d = _validDog(name, breed, notes);
    final row = await _db
        .from('dogs')
        .insert({
          'owner_id': me.id,
          'name': d.name,
          'breed': d.breed,
          'size': size.name,
        })
        .select('id')
        .single();
    final id = row['id'] as String;
    if (d.notes != null) await _saveNotes(id, d.notes);
    return Dog(
      id: id,
      ownerId: me.id,
      name: d.name,
      size: size,
      breed: d.breed,
      notes: d.notes,
    );
  });

  @override
  Future<Dog> updateDog(Dog dog) => _guard(() async {
    final me = _requireOwner();
    final d = _validDog(dog.name, dog.breed, dog.notes);
    final rows = await _db
        .from('dogs')
        .update({'name': d.name, 'breed': d.breed, 'size': dog.size.name})
        .eq('id', dog.id)
        .eq('owner_id', me.id)
        .select('id');
    if (rows.isEmpty) throw const ValidationFailure('Ese perro no existe.');
    await _saveNotes(dog.id, d.notes);
    return Dog(
      id: dog.id,
      ownerId: me.id,
      name: d.name,
      size: dog.size,
      breed: d.breed,
      notes: d.notes,
    );
  });

  @override
  Future<void> deleteDog(String dogId) => _guard(() async {
    final me = _requireOwner();
    final rows = await _db
        .from('dogs')
        .delete()
        .eq('id', dogId)
        .eq('owner_id', me.id)
        .select('id');
    if (rows.isEmpty) throw const ValidationFailure('Ese perro no existe.');
  });

  @override
  Future<String?> fetchDogNotesForBooking(String bookingId) => _guard(() async {
    final b = await _db
        .from('bookings')
        .select('dog_id')
        .eq('id', bookingId)
        .maybeSingle();
    final dogId = b?['dog_id'] as String?;
    if (dogId == null) return null;
    // RLS: el dueño, o el cuidador solo con la reserva `accepted`.
    final n = await _db
        .from('dog_notes')
        .select('notes')
        .eq('dog_id', dogId)
        .maybeSingle();
    return n?['notes'] as String?;
  });

  // ---------------------------------------------------------------------------
  // Reservas
  // ---------------------------------------------------------------------------

  static const _bookingColumns =
      '*, owner:profiles!bookings_owner_id_fkey(full_name), '
      'sitter:profiles!bookings_sitter_id_fkey(full_name), '
      'dog:dogs(name), review:reviews(id)';

  Booking _booking(Map<String, dynamic> r) {
    String nameOf(Object? embedded, String fallback) => embedded is Map
        ? (embedded['full_name'] as String? ?? fallback)
        : fallback;
    final dog = r['dog'];
    final review = r['review'];
    return Booking(
      id: r['id'] as String,
      ownerId: r['owner_id'] as String,
      ownerName: nameOf(r['owner'], 'Dueño'),
      sitterId: r['sitter_id'] as String,
      sitterName: nameOf(r['sitter'], 'Cuidador'),
      dogId: r['dog_id'] as String? ?? '',
      dogName: dog is Map ? (dog['name'] as String? ?? 'Perro') : 'Perro',
      service: _enum(ServiceType.values, r['service_type'] as String),
      startAt: _date(r['start_at'])!,
      endAt: _date(r['end_at'])!,
      totalCop: r['total_cop'] as int,
      status: _enum(BookingStatus.values, r['status'] as String),
      createdAt: _date(r['created_at'])!,
      responseDeadline: _date(r['response_deadline'])!,
      reviewed: review is Map || (review is List && review.isNotEmpty),
    );
  }

  Future<List<Booking>> _myBookings() async {
    final rows = await _db
        .from('bookings')
        .select(_bookingColumns)
        .order('created_at', ascending: false);
    final me = _current?.id;
    // Un admin ve además las reservas ligadas a reportes: aquí solo las suyas.
    return [
      for (final r in rows)
        if (r['owner_id'] == me || r['sitter_id'] == me) _booking(r),
    ];
  }

  Future<Booking> _bookingById(String id) async {
    final row = await _db
        .from('bookings')
        .select(_bookingColumns)
        .eq('id', id)
        .maybeSingle();
    if (row == null) throw const ValidationFailure('Esa reserva no existe.');
    return _booking(row);
  }

  @override
  Future<Booking> createBooking({
    required String sitterId,
    required String dogId,
    required ServiceType service,
    required DateTime startAt,
    required DateTime endAt,
  }) => _guard(() async {
    final me = _current;
    if (me == null ||
        me.role != UserRole.owner ||
        me.status != UserStatus.approved) {
      throw const ValidationFailure('Tu cuenta no puede hacer reservas.');
    }
    final now = DateTime.now();
    if (!startAt.isAfter(now)) {
      throw const ValidationFailure('Elige una fecha y hora en el futuro.');
    }
    if (!startIsBookable(startAt, now: now)) {
      throw const ValidationFailure(
        'Reserva con al menos 1 hora de anticipación: el cuidador necesita tiempo para responder.',
      );
    }
    if (!endAt.isAfter(startAt)) {
      throw const ValidationFailure(
        'La hora de fin debe ser posterior a la de inicio.',
      );
    }
    // El total, el estado y el plazo de respuesta los fija la base.
    final row = await _db
        .from('bookings')
        .insert({
          'owner_id': me.id,
          'sitter_id': sitterId,
          'dog_id': dogId,
          'service_type': _snake(service.name),
          'start_at': startAt.toUtc().toIso8601String(),
          'end_at': endAt.toUtc().toIso8601String(),
        })
        .select(_bookingColumns)
        .single();
    return _booking(row);
  });

  @override
  Stream<List<Booking>> watchMyBookings() {
    late final StreamController<List<Booking>> out;
    RealtimeChannel? channel;
    var closed = false;

    Future<void> refresh() async {
      try {
        final list = await _myBookings();
        if (!closed) out.add(list);
      } catch (e) {
        if (!closed) out.addError(_translate(e));
      }
    }

    out = StreamController<List<Booking>>(
      onListen: () {
        final me = _current;
        if (me == null) {
          out.add(const []);
          return;
        }
        refresh();
        // Tiempo real: cualquier cambio en una reserva propia (RLS filtra las
        // ajenas) vuelve a cargar la lista con nombres y estados al día.
        channel = _db
            .channel(
              'bookings-${me.id}-${DateTime.now().microsecondsSinceEpoch}',
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'bookings',
              callback: (_) => refresh(),
            )
            .subscribe((status, _) {
              // Lo que cambió mientras se abría la conexión no llega como
              // evento: al quedar suscrito se recarga una vez.
              if (status == RealtimeSubscribeStatus.subscribed) refresh();
            });
      },
      onCancel: () async {
        closed = true;
        if (channel != null) await _db.removeChannel(channel!);
      },
    );
    return out.stream;
  }

  Future<Booking> _setStatus(String bookingId, BookingStatus status) async {
    final rows = await _db
        .from('bookings')
        .update({'status': status.name})
        .eq('id', bookingId)
        .select('id');
    if (rows.isEmpty) throw const ValidationFailure('Esa reserva no existe.');
    return _bookingById(bookingId);
  }

  void _requireApprovedSitter() {
    final me = _current;
    if (me == null ||
        me.role != UserRole.sitter ||
        me.status != UserStatus.approved) {
      throw const ValidationFailure(
        'Solo un cuidador aprobado puede gestionar solicitudes.',
      );
    }
  }

  @override
  Future<Booking> respondToBooking(String bookingId, {required bool accept}) =>
      _guard(
        overrides: const {
          'invalid_status_transition': 'Esta solicitud ya fue respondida.',
        },
        () async {
          _requireApprovedSitter();
          final b = await _bookingById(bookingId);
          if (b.status == BookingStatus.expired ||
              (b.status == BookingStatus.pending &&
                  !DateTime.now().isBefore(b.responseDeadline))) {
            throw const ValidationFailure('El plazo para responder ya venció.');
          }
          if (b.status != BookingStatus.pending) {
            throw const ValidationFailure('Esta solicitud ya fue respondida.');
          }
          return _setStatus(
            bookingId,
            accept ? BookingStatus.accepted : BookingStatus.rejected,
          );
        },
      );

  @override
  Future<Booking> completeBooking(String bookingId) => _guard(
    overrides: const {
      'invalid_status_transition': 'Solo se completan reservas aceptadas.',
    },
    () async {
      _requireApprovedSitter();
      return _setStatus(bookingId, BookingStatus.completed);
    },
  );

  @override
  Future<Booking> cancelBooking(String bookingId) => _guard(
    overrides: const {
      'invalid_status_transition': 'Esta reserva ya no se puede cancelar.',
    },
    () => _setStatus(bookingId, BookingStatus.cancelled),
  );

  // ---------------------------------------------------------------------------
  // Datos privados y contacto
  // ---------------------------------------------------------------------------

  @override
  Future<ContactInfo?> fetchCounterpartContact(String bookingId) =>
      _guard(() async {
        final me = _current;
        if (me == null) return null;
        final b = await _bookingById(bookingId);
        if (b.status != BookingStatus.accepted) return null;
        final mine = b.ownerId == me.id;
        if (!mine && b.sitterId != me.id) return null;
        // RLS: solo se lee con la reserva `accepted`.
        final data = await _db
            .from('profile_private')
            .select('phone, address')
            .eq('id', mine ? b.sitterId : b.ownerId)
            .maybeSingle();
        return ContactInfo(
          name: mine ? b.sitterName : b.ownerName,
          phone: data?['phone'] as String?,
          address: data?['address'] as String?,
        );
      });

  @override
  Future<PrivateData> fetchMyPrivateData() => _guard(() async {
    final me = _current;
    if (me == null) return const PrivateData();
    final row = await _db
        .from('profile_private')
        .select('phone, address')
        .eq('id', me.id)
        .maybeSingle();
    return PrivateData(
      phone: row?['phone'] as String?,
      address: row?['address'] as String?,
    );
  });

  @override
  Future<void> saveMyPrivateData(PrivateData data) => _guard(() async {
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
    await _db
        .from('profile_private')
        .update({
          'phone': (phone == null || phone.isEmpty) ? null : phone,
          'address': (address == null || address.isEmpty) ? null : address,
        })
        .eq('id', _uid);
  });

  // ---------------------------------------------------------------------------
  // Reseñas y reportes
  // ---------------------------------------------------------------------------

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) => _guard(
    overrides: const {'duplicate key': 'Ya calificaste esta reserva.'},
    () async {
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
      final b = await _bookingById(bookingId);
      if (b.ownerId != _uid) {
        throw const ValidationFailure('Esa reserva no existe.');
      }
      if (b.status != BookingStatus.completed) {
        throw const ValidationFailure(
          'Solo puedes calificar reservas completadas.',
        );
      }
      if (b.reviewed) {
        throw const ValidationFailure('Ya calificaste esta reserva.');
      }
      // Dueño, cuidador y nombre del autor los fija el trigger desde la reserva.
      await _db.from('reviews').insert({
        'booking_id': bookingId,
        'owner_id': b.ownerId,
        'sitter_id': b.sitterId,
        'rating': rating,
        'comment': (text == null || text.isEmpty) ? null : text,
      });
    },
  );

  @override
  Future<void> createReport({
    required String reportedUserId,
    required ReportReason reason,
    String? bookingId,
    String? comment,
  }) => _guard(() async {
    final me = _current;
    if (me == null ||
        !me.role.isSelectable ||
        me.status != UserStatus.approved) {
      throw const ValidationFailure('Tu cuenta no puede enviar reportes.');
    }
    if (reportedUserId == me.id) {
      throw const ValidationFailure('No puedes reportarte a ti mismo.');
    }
    final text = comment?.trim();
    if (text != null && text.length > 1000) {
      throw const ValidationFailure(
        'El comentario puede tener hasta 1000 caracteres.',
      );
    }
    await _db.from('reports').insert({
      'reporter_id': me.id,
      'reported_user_id': reportedUserId,
      'booking_id': bookingId,
      'reason': _snake(reason.name),
      'comment': (text == null || text.isEmpty) ? null : text,
    });
  });

  // ---------------------------------------------------------------------------
  // Administración (cada RPC valida el rol por dentro)
  // ---------------------------------------------------------------------------

  AdminUserRow _userRow(Map<String, dynamic> r) => AdminUserRow(
    id: r['id'] as String,
    name: r['full_name'] as String? ?? '',
    email: r['email'] as String? ?? '',
    role: _enum(UserRole.values, r['role'] as String),
    status: _enum(UserStatus.values, r['status'] as String),
    verified: r['verified'] as bool? ?? false,
  );

  @override
  Future<List<AdminUserRow>> searchUsers({
    String query = '',
    UserRole? role,
    UserStatus? status,
  }) => _guard(() async {
    final rows = await _db.rpc(
      'admin_search_users',
      params: {
        'q': query.trim().isEmpty ? null : query.trim(),
        'p_role': role?.name,
        'p_status': status == null ? null : _snake(status.name),
      },
    );
    return [for (final r in rows as List) _userRow(r)]
      ..sort((a, b) => a.name.compareTo(b.name));
  });

  @override
  Future<List<PendingSitter>> fetchPendingSitters() => _guard(() async {
    final users = await searchUsers(
      role: UserRole.sitter,
      status: UserStatus.pendingReview,
    );
    if (users.isEmpty) return const <PendingSitter>[];
    final rows = await _db.from('profiles').select(_sitterColumns).inFilter(
      'id',
      [for (final u in users) u.id],
    );
    final sitters = {for (final s in await _sitters(rows)) s.id: s};
    return [
      for (final u in users)
        if (sitters[u.id] != null)
          PendingSitter(user: u, sitter: sitters[u.id]!),
    ];
  });

  @override
  Future<void> setSitterApproval(String userId, {required bool approve}) =>
      _guard(
        () => _db.rpc(
          'admin_set_sitter_approval',
          params: {'target': userId, 'approve': approve},
        ),
      );

  @override
  Future<void> setUserSuspended(String userId, bool suspended) => _guard(
    () => _db.rpc(
      'admin_set_user_suspended',
      params: {'target': userId, 'suspend': suspended},
    ),
  );

  @override
  Future<List<Report>> fetchReports() => _guard(() async {
    final rows = await _db
        .from('reports')
        .select(
          '*, reporter:profiles!reports_reporter_id_fkey(full_name), '
          'reported:profiles!reports_reported_user_id_fkey(full_name)',
        )
        .order('created_at', ascending: false);
    String nameOf(Object? p) =>
        p is Map ? (p['full_name'] as String? ?? 'Usuario') : 'Usuario';
    return [
      for (final r in rows)
        Report(
          id: r['id'] as String,
          reporterId: r['reporter_id'] as String,
          reporterName: nameOf(r['reporter']),
          reportedUserId: r['reported_user_id'] as String,
          reportedName: nameOf(r['reported']),
          bookingId: r['booking_id'] as String?,
          reason: _enum(ReportReason.values, r['reason'] as String),
          comment: r['comment'] as String?,
          status: _enum(ReportStatus.values, r['status'] as String),
          createdAt: _date(r['created_at'])!,
        ),
    ];
  });

  @override
  Future<void> resolveReport(
    String reportId,
    ReportStatus resolution, {
    bool suspendReported = false,
  }) => _guard(() async {
    if (resolution == ReportStatus.open) {
      throw const ValidationFailure('Elige revisado o descartado.');
    }
    await _db.rpc(
      'admin_resolve_report',
      params: {
        'report': reportId,
        'resolution': resolution.name,
        'suspend_reported': suspendReported,
      },
    );
  });

  @override
  Future<List<AdminAction>> fetchAdminActions() => _guard(() async {
    final rows = await _db
        .from('admin_actions')
        .select('*, admin:profiles!admin_actions_admin_id_fkey(full_name)')
        .order('created_at', ascending: false)
        .limit(200);
    final targetIds = {
      for (final r in rows)
        if (r['target_user_id'] != null) r['target_user_id'] as String,
    };
    final names = <String, String>{};
    if (targetIds.isNotEmpty) {
      final people = await _db
          .from('profiles')
          .select('id, full_name')
          .inFilter('id', targetIds.toList());
      for (final p in people) {
        names[p['id'] as String] = p['full_name'] as String? ?? '';
      }
    }
    return [
      for (final r in rows)
        AdminAction(
          adminId: r['admin_id'] as String? ?? '',
          adminName: r['admin'] is Map
              ? (r['admin']['full_name'] as String? ?? 'Admin')
              : 'Admin eliminado',
          action: r['action'] as String,
          targetUserId: r['target_user_id'] as String? ?? '',
          // Una cuenta eliminada ya no tiene perfil: su nombre quedó en details.
          targetName:
              names[r['target_user_id']] ??
              (r['details']?['target_name'] as String?) ??
              'Cuenta eliminada',
          details: _actionDetails(
            r['action'] as String,
            (r['details'] as Map?)?.cast<String, dynamic>() ?? const {},
          ),
          createdAt: _date(r['created_at'])!,
        ),
    ];
  });

  /// El mismo texto corto que muestra la demo bajo cada acción.
  static String? _actionDetails(String action, Map<String, dynamic> d) {
    String? roleLabel(Object? r) =>
        r is String ? _enum(UserRole.values, r).label : null;
    switch (action) {
      case 'promote_admin':
        final from = roleLabel(d['from_role']);
        return from == null ? null : 'antes: $from';
      case 'delete_user':
        final role = roleLabel(d['target_role']);
        return role == null ? null : 'era $role';
      case 'resolve_report':
        final res = d['resolution'];
        if (res is! String) return null;
        final label = _enum(ReportStatus.values, res).label;
        return d['suspended'] == true ? '$label · cuenta suspendida' : label;
      case 'suspend_user':
        return d['reason'] as String?;
    }
    return null;
  }

  @override
  Future<void> setAdmin(String userId, {required bool makeAdmin}) => _guard(
    () => _db.rpc(
      'superadmin_set_admin',
      params: {'target': userId, 'make_admin': makeAdmin},
    ),
  );

  @override
  Future<void> deleteUser(String userId) => _guard(
    () => _db.rpc('superadmin_delete_user', params: {'target': userId}),
  );

  // ---------------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------------

  /// Corre una operación y traduce cualquier error de red o de la base a un
  /// mensaje para el usuario. En pantallas de sesión el error es `AuthFailure`.
  Future<T> _guard<T>(
    Future<T> Function() action, {
    Map<String, String> overrides = const {},
    bool auth = false,
  }) async {
    try {
      return await action();
    } on AuthFailure {
      rethrow;
    } on ValidationFailure catch (e) {
      if (auth) throw AuthFailure(e.message);
      rethrow;
    } catch (e) {
      final failure = _translate(e, overrides: overrides);
      if (failure is AccountSuspendedFailure) throw failure;
      throw auth ? AuthFailure(failure.toString()) : failure;
    }
  }

  /// Códigos de error de supabase/schema.sql -> el mensaje de la demo.
  static const _messages = {
    'start_in_past': 'Elige una fecha y hora en el futuro.',
    'start_too_soon': 'Reserva con al menos 1 hora de anticipación: el cuidador necesita tiempo para responder.',
    'owner_not_allowed': 'Tu cuenta no puede hacer reservas.',
    'sitter_not_available': 'Este cuidador no está disponible.',
    'invalid_dog': 'Elige uno de tus perros.',
    'outside_availability':
        'Ese horario está fuera de la disponibilidad del cuidador.',
    'service_not_offered': 'Este cuidador no ofrece ese servicio.',
    'response_deadline_passed': 'El plazo para responder ya venció.',
    'invalid_status_transition': 'Esa reserva ya cambió de estado.',
    'booking_not_completed': 'Solo puedes calificar reservas completadas.',
    'reporter_not_allowed': 'Tu cuenta no puede enviar reportes.',
    'booking_mismatch': 'Esa reserva no es entre ustedes dos.',
    'reports_distinct_users': 'No puedes reportarte a ti mismo.',
    'dog_has_active_bookings':
        'No puedes borrar un perro con reservas activas.',
    'active_bookings': 'Tiene reservas activas: espera a que terminen.',
    'cannot_target_self': 'No puedes modificar tu propia cuenta.',
    'protected_user': 'Esa cuenta está protegida.',
    'user_not_found': 'Ese usuario no existe.',
    'not_a_sitter': 'Ese usuario no es cuidador.',
    'not_pending': 'Ese cuidador ya no está en revisión.',
    'not_an_admin': 'Ese usuario no es administrador.',
    'report_not_open': 'Ese reporte ya fue atendido.',
    'invalid_resolution': 'Elige revisado o descartado.',
    'role_not_switchable': 'Tu rol no se puede cambiar desde ajustes.',
    'forbidden': 'No tienes permiso para hacer esto.',
    'protected_column': 'No tienes permiso para hacer esto.',
    'row-level security': 'No tienes permiso para hacer esto.',
    'check constraint': contactInfoMessage,
  };

  static Exception _translate(
    Object e, {
    Map<String, String> overrides = const {},
  }) {
    if (e is ValidationFailure || e is AuthFailure) return e as Exception;
    final text = switch (e) {
      PostgrestException(:final message, :final details) =>
        '$message ${details ?? ''}',
      AuthException(:final message) => message,
      _ => null,
    };
    if (text == null) {
      return const ValidationFailure(
        'No hay conexión con el servidor. Revisa tu internet e inténtalo de nuevo.',
      );
    }
    if (text.contains('account_suspended')) {
      return const AccountSuspendedFailure();
    }
    // Primero los mensajes propios de la operación, luego los generales.
    for (final table in [overrides, _messages]) {
      for (final entry in table.entries) {
        if (text.contains(entry.key)) return ValidationFailure(entry.value);
      }
    }
    return const ValidationFailure('Algo salió mal. Inténtalo de nuevo.');
  }

  /// `homeVisit` -> `home_visit`: los enums de la base van en snake_case.
  static String _snake(String camel) =>
      camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

  static T _enum<T extends Enum>(List<T> values, String db) =>
      values.firstWhere((v) => _snake(v.name) == db);

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.parse(v).toLocal() : null;
}
