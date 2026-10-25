enum UserRole {
  owner('Dueño'),
  sitter('Cuidador'),
  admin('Administrador'),
  superadmin('Superadministrador');

  const UserRole(this.label);
  final String label;

  bool get isAdmin => this == admin || this == superadmin;

  /// Roles que el usuario puede elegir al registrarse o cambiar en ajustes.
  bool get isSelectable => this == owner || this == sitter;
}

enum UserStatus { pendingReview, approved, suspended }

class Profile {
  const Profile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.status,
    this.verified = false,
    this.avatarUrl,
    this.bio,
    this.termsAcceptedAt,
  });

  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final UserStatus status;
  final bool verified;
  final String? avatarUrl;
  final String? bio;
  final DateTime? termsAcceptedAt;

  Profile copyWith({
    UserRole? role,
    UserStatus? status,
    bool? verified,
    String? bio,
  }) {
    return Profile(
      id: id,
      email: email,
      fullName: fullName,
      role: role ?? this.role,
      status: status ?? this.status,
      verified: verified ?? this.verified,
      avatarUrl: avatarUrl,
      bio: bio ?? this.bio,
      termsAcceptedAt: termsAcceptedAt,
    );
  }
}
