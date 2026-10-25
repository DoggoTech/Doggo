import '../models/profile.dart';

/// Error de autenticación con un mensaje listo para mostrar al usuario.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class AccountSuspendedFailure extends AuthFailure {
  const AccountSuspendedFailure()
      : super('Tu cuenta está suspendida. Contacta a soporte de Doggo.');
}

/// Contrato único de datos de la app. La UI solo habla con esta interfaz;
/// `DemoRepository` (en memoria) y, más adelante, `SupabaseRepository`
/// la implementan para poder cambiar de modo sin tocar las pantallas.
abstract class Repository {
  /// Perfil de la sesión actual, o `null` si no hay sesión.
  Profile? get currentProfile;

  /// Emite el perfil actual al suscribirse y cada cambio de sesión después.
  Stream<Profile?> authChanges();

  Future<Profile> signIn({required String email, required String password});

  /// Solo acepta [UserRole.owner] y [UserRole.sitter]. Los cuidadores nuevos
  /// nacen `pendingReview` y los dueños `approved`.
  Future<Profile> signUp({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
    required bool acceptedTerms,
  });

  Future<void> signOut();

  /// Cambia entre dueño y cuidador. Falla si hay reservas activas.
  Future<Profile> switchRole(UserRole role);
}
