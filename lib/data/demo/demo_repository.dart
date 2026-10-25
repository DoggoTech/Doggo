import 'dart:async';

import '../models/profile.dart';
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
      throw const AuthFailure('La contraseña debe tener al menos 6 caracteres.');
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

  /// Se conecta con las reservas en la fase 5.
  bool _hasActiveBookings(Profile profile) => false;

  Future<void> _latency() =>
      Future<void>.delayed(const Duration(milliseconds: 250));
}

class _DemoUser {
  const _DemoUser(this.profile, this.password);
  final Profile profile;
  final String password;

  _DemoUser withProfile(Profile p) => _DemoUser(p, password);
}
