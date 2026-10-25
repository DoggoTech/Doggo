import 'service_type.dart';

enum BookingStatus {
  pending('Pendiente'),
  accepted('Aceptada'),
  rejected('Rechazada'),
  cancelled('Cancelada'),
  completed('Completada'),

  /// El cuidador no respondió dentro del plazo.
  expired('Vencida');

  const BookingStatus(this.label);
  final String label;

  bool get isActive => this == pending || this == accepted;
}

class Booking {
  const Booking({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.sitterId,
    required this.sitterName,
    required this.dogId,
    required this.dogName,
    required this.service,
    required this.startAt,
    required this.endAt,
    required this.totalCop,
    required this.status,
    required this.createdAt,
    required this.responseDeadline,
    this.reviewed = false,
  });

  final String id;
  final String ownerId;
  final String ownerName;
  final String sitterId;
  final String sitterName;
  final String dogId;
  final String dogName;
  final ServiceType service;
  final DateTime startAt;
  final DateTime endAt;
  final int totalCop;
  final BookingStatus status;
  final DateTime createdAt;

  /// Hasta cuándo puede aceptar o rechazar el cuidador.
  final DateTime responseDeadline;

  /// El dueño ya dejó reseña de esta reserva.
  final bool reviewed;

  Booking copyWith({BookingStatus? status, bool? reviewed}) {
    return Booking(
      id: id,
      ownerId: ownerId,
      ownerName: ownerName,
      sitterId: sitterId,
      sitterName: sitterName,
      dogId: dogId,
      dogName: dogName,
      service: service,
      startAt: startAt,
      endAt: endAt,
      totalCop: totalCop,
      status: status ?? this.status,
      createdAt: createdAt,
      responseDeadline: responseDeadline,
      reviewed: reviewed ?? this.reviewed,
    );
  }
}
