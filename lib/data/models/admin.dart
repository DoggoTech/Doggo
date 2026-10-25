import 'profile.dart';
import 'sitter_summary.dart';

/// Una fila del buscador de usuarios del panel de administración.
class AdminUserRow {
  const AdminUserRow({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.verified = false,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;
  final UserStatus status;
  final bool verified;
}

/// Cuidador en revisión con su perfil completo, para aprobarlo o rechazarlo.
class PendingSitter {
  const PendingSitter({required this.user, required this.sitter});

  final AdminUserRow user;
  final SitterSummary sitter;
}

/// Registro de auditoría de una acción de moderación.
class AdminAction {
  const AdminAction({
    required this.adminId,
    required this.adminName,
    required this.action,
    required this.targetUserId,
    required this.targetName,
    required this.createdAt,
    this.details,
  });

  final String adminId;
  final String adminName;

  /// approve_sitter, reject_sitter,
  /// suspend_user, reactivate_user, resolve_report (mismos nombres que la base).
  final String action;
  final String targetUserId;
  final String targetName;
  final String? details;
  final DateTime createdAt;
}
