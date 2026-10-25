import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/admin.dart';
import '../../data/models/profile.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'audit_list.dart';

/// Solo el superadmin: nombrar o quitar admins, suspenderlos y ver toda la
/// auditoría. La base valida cada acción por su cuenta (RPC `superadmin_*`).
class TeamTab extends ConsumerStatefulWidget {
  const TeamTab({super.key});

  @override
  ConsumerState<TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends ConsumerState<TeamTab> {
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _promote() async {
    final email = _email.text.trim().toLowerCase();
    final messenger = ScaffoldMessenger.of(context);
    if (email.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Escribe el correo de la cuenta.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      final matches = await repo.searchUsers(query: email);
      final user = matches
          .where((u) => u.email.toLowerCase() == email)
          .firstOrNull;
      if (!mounted) return;
      if (user == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No hay ninguna cuenta con ese correo.'),
          ),
        );
        return;
      }
      if (user.role == UserRole.admin) {
        messenger.showSnackBar(
          SnackBar(content: Text('${user.name} ya es administrador.')),
        );
        return;
      }
      final ok = await confirmAction(
        context,
        title: '¿Nombrar administrador a ${user.name}?',
        body:
            'Podrá aprobar cuidadores, atender reportes y suspender dueños y '
            'cuidadores. Dejará de usar la app como ${user.role.label.toLowerCase()}.',
        confirm: 'Sí, nombrar',
      );
      if (!ok) return;
      await repo.setAdmin(user.id, makeAdmin: true);
      refreshAdminData(ref);
      _email.clear();
      messenger.showSnackBar(
        SnackBar(content: Text('${user.name} ahora es administrador')),
      );
    } on ValidationFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final admins = ref.watch(
      userSearchProvider((query: '', role: UserRole.admin, status: null)),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const AdminHeader(
          'Equipo',
          subtitle: 'Nombra o quita administradores y revisa todo lo que hace el equipo.',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nombrar administrador', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Busca la cuenta por su correo exacto. Debe estar registrada y sin reservas activas.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => _busy ? null : _promote(),
                decoration: const InputDecoration(
                  labelText: 'Correo del nuevo administrador',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
              ),
              const SizedBox(height: 12),
              LabeledButton(
                text: 'Hacer administrador',
                label: 'Hacer administrador',
                filled: true,
                onPressed: _busy ? null : _promote,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          container: true,
          child: Text(
            'Administradores',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 10),
        admins.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('$e'),
          data: (rows) => rows.isEmpty
              ? Semantics(
                  container: true,
                  child: const Text('Todavía no hay administradores.'),
                )
              : Column(
                  children: [
                    for (final u in rows)
                      _AdminRow(key: ValueKey(u.id), user: u),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        const AuditList(title: 'Auditoría completa'),
      ],
    );
  }
}

class _AdminRow extends ConsumerStatefulWidget {
  const _AdminRow({super.key, required this.user});

  final AdminUserRow user;

  @override
  ConsumerState<_AdminRow> createState() => _AdminRowState();
}

class _AdminRowState extends ConsumerState<_AdminRow> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      refreshAdminData(ref);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ValidationFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleSuspended() async {
    final u = widget.user;
    final suspend = u.status != UserStatus.suspended;
    if (suspend) {
      final ok = await confirmAction(
        context,
        title: '¿Suspender a ${u.name}?',
        body:
            'No podrá iniciar sesión ni usar el panel hasta que lo reactives.',
        confirm: 'Sí, suspender',
      );
      if (!ok || !mounted) return;
    }
    await _run(
      () => ref.read(repositoryProvider).setUserSuspended(u.id, suspend),
      suspend ? '${u.name} fue suspendido' : '${u.name} fue reactivado',
    );
  }

  Future<void> _revoke() async {
    final u = widget.user;
    final ok = await confirmAction(
      context,
      title: '¿Quitarle el rol de administrador a ${u.name}?',
      body: 'Perderá el acceso al panel y su cuenta pasará a ser de dueño.',
      confirm: 'Sí, quitar',
    );
    if (!ok || !mounted) return;
    await _run(
      () => ref.read(repositoryProvider).setAdmin(u.id, makeAdmin: false),
      '${u.name} ya no es administrador',
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final theme = Theme.of(context);
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
                        u.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        u.email,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              StatusChip(u.status),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              LabeledButton(
                text: suspended ? 'Reactivar' : 'Suspender',
                label: '${suspended ? 'Reactivar' : 'Suspender'} a ${u.name}',
                filled: suspended,
                onPressed: _busy ? null : _toggleSuspended,
              ),
              LabeledButton(
                text: 'Quitar admin',
                label: 'Quitar admin a ${u.name}',
                onPressed: _busy ? null : _revoke,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
