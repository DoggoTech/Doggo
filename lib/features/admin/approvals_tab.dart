import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/admin.dart';
import '../../data/models/service_type.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../map/sitter_list.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import '../../shared/widgets/error_state.dart';

/// Cuidadores en revisión: aprobar (le da la insignia "Verificado") o rechazar.
class ApprovalsTab extends ConsumerWidget {
  const ApprovalsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(pendingSittersProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorState(
            'No pudimos cargar las solicitudes de cuidadores.',
            onRetry: () => ref.invalidate(pendingSittersProvider),
          ),
          data: (list) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              const AdminHeader(
                'Aprobaciones',
                subtitle: 'Cuidadores nuevos. No aparecen en el mapa hasta que los apruebes.',
              ),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.verified_user_rounded,
                        size: 56,
                        color: AppColors.muted,
                      ),
                      const SizedBox(height: 12),
                      Semantics(
                        container: true,
                        child: Text(
                          'No hay cuidadores por aprobar.',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final p in list)
                  _PendingCard(key: ValueKey(p.user.id), pending: p),
            ],
          ),
        );
  }
}

class _PendingCard extends ConsumerStatefulWidget {
  const _PendingCard({super.key, required this.pending});

  final PendingSitter pending;

  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
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

  @override
  Widget build(BuildContext context) {
    final u = widget.pending.user;
    final s = widget.pending.sitter;
    final repo = ref.read(repositoryProvider);
    final theme = Theme.of(context);
    final services = ServiceType.values.where(s.offers).toList();
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SitterAvatar(sitter: s, radius: 26),
              const SizedBox(width: 12),
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
                        '${u.email} · ${s.neighborhood}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            container: true,
            child: Text(
              s.bio.isEmpty ? 'Sin bio todavía.' : s.bio,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            container: true,
            child: Text(
              services.isEmpty
                  ? 'Aún no configura servicios: no aparecerá en el mapa hasta hacerlo.'
                  : services
                        .map((t) => '${t.label} ${formatCop(s.services[t]!)}')
                        .join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 4),
          Semantics(
            container: true,
            child: Text(
              s.locationConfirmed
                  ? 'Zona: ${s.neighborhood}, ${s.radiusKm} km a la redonda'
                  : 'Aún no define su zona de servicio: no saldrá en el mapa hasta hacerlo.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: s.locationConfirmed ? null : theme.colorScheme.error,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              LabeledButton(
                text: 'Rechazar',
                label: 'Rechazar a ${u.name}',
                onPressed: _busy
                    ? null
                    : () async {
                        final ok = await confirmAction(
                          context,
                          title: '¿Rechazar a ${u.name}?',
                          body: 'Su cuenta quedará suspendida y no aparecerá en el mapa.',
                          confirm: 'Sí, rechazar',
                        );
                        if (ok) {
                          await _run(
                            () => repo.setSitterApproval(u.id, approve: false),
                            '${u.name} fue rechazado',
                          );
                        }
                      },
              ),
              LabeledButton(
                text: 'Aprobar',
                label: 'Aprobar a ${u.name}',
                filled: true,
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => repo.setSitterApproval(u.id, approve: true),
                        '${u.name} fue aprobado',
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
