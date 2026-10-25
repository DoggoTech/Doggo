import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

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
    String? notes,
  });

  Future<Dog> updateDog(Dog dog);

  /// Falla si el perro tiene reservas activas.
  Future<void> deleteDog(String dogId);

  /// Notas del perro de una reserva: solo con la reserva `accepted` (o si es
  /// el dueño). En otro caso devuelve `null`.
  Future<String?> fetchDogNotesForBooking(String bookingId);

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

  /// El dueño cancela una reserva `pending` o `accepted`.
  Future<Booking> cancelBooking(String bookingId);

  /// Teléfono y dirección de la contraparte, SOLO si la reserva está
  /// `accepted`. En otro caso devuelve `null`.
  Future<ContactInfo?> fetchCounterpartContact(String bookingId);

  Future<PrivateData> fetchMyPrivateData();

  Future<void> saveMyPrivateData(PrivateData data);

  /// Reseña del dueño sobre una reserva `completed` (una por reserva).
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  });

  /// Reporta a otro usuario (dueño o cuidador aprobado). Si se pasa
  /// [bookingId], ambos deben participar en esa reserva.
  Future<void> createReport({
    required String reportedUserId,
    required ReportReason reason,
    String? bookingId,
    String? comment,
  });

  /// Bio pública del cuidador (máx. 600, sin teléfonos, correos ni enlaces).
  Future<void> saveMyBio(String bio);

  // ---- Administración (solo admin y superadmin; la base lo valida en las RPC) ----

  /// Cuidadores en `pending_review` con su perfil completo.
  Future<List<PendingSitter>> fetchPendingSitters();

  /// Aprobar (aparece en el mapa con la insignia "Verificado") o rechazar
  /// (queda suspendido).
  Future<void> setSitterApproval(String userId, {required bool approve});

  /// Reportes, del más reciente al más antiguo.
  Future<List<Report>> fetchReports();

  /// Marca un reporte como revisado o descartado; opcionalmente suspende al reportado.
  Future<void> resolveReport(
    String reportId,
    ReportStatus resolution, {
    bool suspendReported = false,
  });

  /// Búsqueda por nombre o correo, con filtros de rol y estado.
  Future<List<AdminUserRow>> searchUsers({
    String query = '',
    UserRole? role,
    UserStatus? status,
  });

  /// Suspender o reactivar. Un admin no puede tocar a otro admin ni al
  /// superadmin; nadie puede modificarse a sí mismo.
  Future<void> setUserSuspended(String userId, bool suspended);

  /// Auditoría: el admin ve sus acciones; el superadmin, todas.
  Future<List<AdminAction>> fetchAdminActions();

  /// Solo el superadmin: nombra admin a un usuario o le quita el rol (vuelve
  /// a dueño). No con reservas activas ni sobre sí mismo.
  Future<void> setAdmin(String userId, {required bool makeAdmin});

  /// Solo el superadmin: elimina la cuenta para siempre. La auditoría la
  /// conserva con su nombre. No con reservas activas.
  Future<void> deleteUser(String userId);

  /// Zona de servicio del cuidador. Guarda la ubicación EXACTA en privado y
  /// publica en el mapa una aproximada (200–300 m de diferencia).
  Future<void> saveMyServiceArea({
    required LatLng exact,
    required String neighborhood,
    required int radiusKm,
  });

  /// Foto de perfil: JPG, PNG o WEBP de hasta 2 MB.
  Future<void> saveMyPhoto(Uint8List bytes, String mimeType);
}
