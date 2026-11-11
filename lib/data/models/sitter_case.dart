/// Etapa del caso de verificación de un cuidador en revisión.
enum CaseStage {
  /// Recién asignado: falta agendar la reunión.
  fresh('new', 'Nuevo'),
  meetingScheduled('meeting_scheduled', 'Reunión agendada'),
  meetingDone('meeting_done', 'Reunión hecha');

  const CaseStage(this.db, this.label);

  /// Nombre en la base (`public.case_stage`).
  final String db;
  final String label;

  static CaseStage fromDb(String v) => values.firstWhere((s) => s.db == v);
}

/// Caso de verificación: lo abre la base al registrarse un cuidador y lo
/// reparte al admin con menos casos abiertos. Se cierra al aprobar o rechazar.
class SitterCase {
  const SitterCase({
    required this.sitterId,
    required this.stage,
    this.assignedAdminId,
    this.assignedAdminName,
    this.meetingAt,
    this.meetingLink,
    this.meetingConfirmed = false,
  });

  final String sitterId;
  final CaseStage stage;

  /// `null` si no había ningún admin cuando se abrió (cualquiera lo puede tomar).
  final String? assignedAdminId;
  final String? assignedAdminName;

  /// Reunión virtual inicial (fecha local y enlace https).
  final DateTime? meetingAt;
  final String? meetingLink;

  /// El cuidador confirmó que asistirá.
  final bool meetingConfirmed;

  bool get hasMeeting => meetingAt != null && meetingLink != null;
}

enum SitterDocKind {
  certificate('Certificado de cuidado animal'),
  firstAid('Primeros auxilios'),
  idDocument('Documento de identidad'),
  other('Otro');

  const SitterDocKind(this.label);
  final String label;
}

/// Certificado (opcional) que sube el cuidador para su verificación.
class SitterDocument {
  const SitterDocument({
    required this.id,
    required this.sitterId,
    required this.kind,
    required this.fileName,
    required this.storagePath,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String id;
  final String sitterId;
  final SitterDocKind kind;
  final String fileName;
  final String storagePath;
  final int sizeBytes;
  final DateTime createdAt;

  bool get isImage =>
      sitterDocMimeType(fileName)?.startsWith('image/') ?? false;
}

/// Reglas de los certificados (las mismas que el bucket `sitter-docs`).
const maxSitterDocBytes = 10 * 1024 * 1024;
const maxSitterDocs = 10;

/// Tipo MIME según la extensión, o `null` si no se acepta (PDF, JPG, PNG, WEBP).
String? sitterDocMimeType(String fileName) {
  final name = fileName.toLowerCase();
  if (name.endsWith('.pdf')) return 'application/pdf';
  if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.webp')) return 'image/webp';
  return null;
}

/// Valida un archivo antes de subirlo; devuelve el mensaje de error o `null`.
String? validateSitterDoc({
  required String fileName,
  required int sizeBytes,
  required int existing,
}) {
  if (existing >= maxSitterDocs) {
    return 'Puedes subir hasta $maxSitterDocs documentos.';
  }
  if (sitterDocMimeType(fileName) == null) {
    return 'El documento debe ser PDF, JPG, PNG o WEBP.';
  }
  if (sizeBytes <= 0 || sizeBytes > maxSitterDocBytes) {
    return 'El documento puede pesar hasta 10 MB.';
  }
  if (fileName.trim().isEmpty || fileName.length > 120) {
    return 'El nombre del archivo es demasiado largo.';
  }
  return null;
}

/// Valida la reunión virtual; devuelve el mensaje de error o `null`.
String? validateMeeting(DateTime at, String link, DateTime now) {
  if (!at.isAfter(now)) return 'Elige una fecha y hora en el futuro.';
  if (at.isAfter(now.add(const Duration(days: 90)))) {
    return 'Agenda la reunión dentro de los próximos 90 días.';
  }
  final l = link.trim();
  if (!RegExp(r'^https://\S+$').hasMatch(l) || l.length > 300) {
    return 'Pega el enlace de la videollamada (empieza por https://).';
  }
  return null;
}
