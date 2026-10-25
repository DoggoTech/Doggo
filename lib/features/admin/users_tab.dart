import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/admin.dart';
import '../../data/models/profile.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../../shared/widgets/pill.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

/// Buscar usuarios por nombre o correo, filtrar y suspender o reactivar.
class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key});

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab> {
  String _query = '';
  UserRole? _role;
  UserStatus? _status;

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(
      userSearchProvider((query: _query, role: _role, status: _status)),
    );
    final me = ref.watch(authStateProvider).value;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const AdminHeader('Usuarios'),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            labelText: 'Buscar por nombre o correo',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (r, label) in [
              (null, 'Todos los roles'),
              (UserRole.owner, 'Dueños'),
              (UserRole.sitter, 'Cuidadores'),
              (UserRole.admin, 'Admins'),
            ])
              Pill(
                elevated: false,
                label: label,
                selected: _role == r,
                onTap: () => setState(() => _role = r),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (s, label) in [
              (null, 'Cualquier estado'),
              (UserStatus.approved, 'Activos'),
              (UserStatus.pendingReview, 'En revisión'),
              (UserStatus.suspended, 'Suspendidos'),
            ])
              Pill(
                elevated: false,
                label: label,
                selected: _status == s,
                onTap: () => setState(() => _status = s),
              ),
          ],
        ),
        const SizedBox(height: 16),
        results.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('$e'),
          data: (rows) => rows.isEmpty
              ? Semantics(
                  container: true,
                  child: const Text('Ningún usuario coincide con la búsqueda.'),
                )
              : Column(
                  children: [
                    for (final u in rows)
                      _UserRow(key: ValueKey(u.id), user: u, me: me),
                  ],
                ),
        ),
      ],
    );
  }
}

class _UserRow extends ConsumerStatefulWidget {
  const _UserRow({super.key, required this.user, required this.me});

  final AdminUserRow user;
  final Profile? me;

  @override
  ConsumerState<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends ConsumerState<_UserRow> {
  bool _busy = false;

  /// Mismas reglas que la base: nadie se toca a sí mismo, nadie toca al
  /// superadmin y solo el superadmin toca a otros admins.
  String? get _protectedReason {
    final u = widget.user;
    final me = widget.me;
    if (me == null) return 'Protegido';
    if (u.id == me.id) return 'Tú';
    if (u.role == UserRole.superadmin) return 'Protegido';
    if (u.role == UserRole.admin && me.role != UserRole.superadmin) {
      return 'Protegido';
    }
    return null;
  }

  Future<void> _setVerified(bool verified) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).setVerified(widget.user.id, verified);
      refreshAdminData(ref);
      messenger.showSnackBar(
        const SnackBar(content: Text('Insignia actualizada')),
      );
    } on ValidationFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle() async {
    final u = widget.user;
    final suspend = u.status != UserStatus.suspended;
    if (suspend) {
      final ok = await confirmAction(
        context,
        title: '¿Suspender a ${u.name}?',
        body: 'Desaparecerá del mapa y no podrá iniciar sesión, reservar ni recibir reservas.',
        confirm: 'Sí, suspender',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).setUserSuspended(u.id, suspend);
      refreshAdminData(ref);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            suspend ? '${u.name} fue suspendido' : '${u.name} fue reactivado',
          ),
        ),
      );
    } on ValidationFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final theme = Theme.of(context);
    final protected = _protectedReason;
    final suspended = u.status == UserStatus.suspended;
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  container: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u.verified ? '${u.name} ✓' : u.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${u.email} · ${u.role.label}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              StatusChip(u.status),
              const SizedBox(width: 8),
              if (protected != null)
                Semantics(
                  container: true,
                  label: '$protected: ${u.name}',
                  excludeSemantics: true,
                  child: Text(
                    protected,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                )
              else
                LabeledButton(
                  text: suspended ? 'Reactivar' : 'Suspender',
                  label: '${suspended ? 'Reactivar' : 'Suspender'} a ${u.name}',
                  filled: suspended,
                  onPressed: _busy ? null : _toggle,
                ),
            ],
          ),
          // La insignia se puede dar o quitar en cualquier momento, también
          // después de aprobar (p. ej. cuando el cuidador envía su documento).
          if (u.role == UserRole.sitter)
            Row(
              children: [
                Semantics(
                  container: true,
                  label: 'Verificado: ${u.name}',
                  toggled: u.verified,
                  onTap: _busy ? null : () => _setVerified(!u.verified),
                  excludeSemantics: true,
                  child: Switch(
                    value: u.verified,
                    onChanged: _busy ? null : _setVerified,
                  ),
                ),
                const Text('Verificado (documento y selfie revisados)'),
              ],
            ),
        ],
      ),
    );
  }
}
