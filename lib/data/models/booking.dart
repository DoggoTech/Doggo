import 'service_type.dart';

enum BookingStatus {
  pending('Pendiente'),
  accepted('Aceptada'),
  rejected('Rechazada'),
  cancelled('Cancelada'),
  completed('Completada');

  const BookingStatus(this.label);
  final String label;

  bool get isActive => this == pending || this == accepted;
}

class Booking {
  const Booking({
    required this.id,
    required this.ownerId,
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
  });

  final String id;
  final String ownerId;
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
}
