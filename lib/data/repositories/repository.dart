import '../models/availability.dart';
import '../models/booking.dart';
import '../models/dog.dart';
import '../models/profile.dart';
import '../models/review.dart';
import '../models/service_type.dart';
import '../models/sitter_summary.dart';

/// Error de autenticación con un mensaje listo para mostrar al usuario.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Datos rechazados por una regla de negocio (las mismas que impone la base).
class ValidationFailure implements Exception {
  const ValidationFailure(this.message);
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

  /// Cuidadores visibles en el mapa: solo `approved` (ni en revisión ni
  /// suspendidos), con ubicación aproximada y al menos un servicio activo.
  Future<List<SitterSummary>> fetchSitters();

  /// Un cuidador visible (aprobado), o `null` si no existe o no está disponible.
  Future<SitterSummary?> fetchSitter(String id);

  /// Reseñas de un cuidador, de la más reciente a la más antigua.
  Future<List<Review>> fetchReviews(String sitterId);

  /// Perros del dueño con sesión.
  Future<List<Dog>> fetchMyDogs();

  Future<Dog> addDog({
    required String name,
    required DogSize size,
    String? breed,
  });

  /// Crea una reserva `pending`. Valida como el trigger de la base: fecha
  /// futura, fin posterior al inicio, dueño y cuidador aprobados, perro propio
  /// y servicio ofrecido. El total lo calcula el repositorio, no la pantalla.
  Future<Booking> createBooking({
    required String sitterId,
    required String dogId,
    required ServiceType service,
    required DateTime startAt,
    required DateTime endAt,
  });

  /// Reservas del usuario con sesión (como dueño o como cuidador), en vivo:
  /// emite la lista actual y cada cambio (nuevas, aceptadas, vencidas…).
  Stream<List<Booking>> watchMyBookings();

  /// El cuidador acepta o rechaza una solicitud `pending` dentro del plazo.
  Future<Booking> respondToBooking(String bookingId, {required bool accept});

  /// El cuidador marca como completada una reserva `accepted`.
  Future<Booking> completeBooking(String bookingId);

  /// Perfil del cuidador con sesión, aunque esté en revisión (para editarlo).
  Future<SitterSummary> fetchMySitterProfile();

  /// Servicios activos y su precio en COP (entre $5.000 y $2.000.000).
  Future<void> saveMyServices(Map<ServiceType, int> services);

  Future<void> saveMyAvailability(WeeklyAvailability availability);
}
