enum ReportReason {
  inappropriateBehavior('Comportamiento inapropiado'),
  fakeProfile('Perfil falso'),
  offPlatformPayment('Cobro fuera de la app'),
  animalAbuse('Maltrato animal'),
  other('Otro');

  const ReportReason(this.label);
  final String label;
}

enum ReportStatus {
  open('Abierto'),
  reviewed('Revisado'),
  dismissed('Descartado');

  const ReportStatus(this.label);
  final String label;
}

class Report {
  const Report({
    required this.id,
    required this.reporterId,
    required this.reporterName,
    required this.reportedUserId,
    required this.reportedName,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.bookingId,
    this.comment,
  });

  final String id;
  final String reporterId;
  final String reporterName;
  final String reportedUserId;
  final String reportedName;
  final String? bookingId;
  final ReportReason reason;
  final String? comment;
  final ReportStatus status;
  final DateTime createdAt;
}
