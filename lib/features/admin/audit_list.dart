import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/admin.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import '../../shared/widgets/error_state.dart';

/// Verbo de cada acción de `admin_actions`, para leerla como una frase.
String auditVerb(String action) => switch (action) {
  'approve_sitter' => 'aprobó a',
  'reject_sitter' => 'rechazó a',
  'suspend_user' => 'suspendió a',
  'reactivate_user' => 'reactivó a',
  'resolve_report' => 'atendió un reporte sobre',
  'promote_admin' => 'nombró administrador a',
  'revoke_admin' => 'quitó el rol de administrador a',
  'delete_user' => 'eliminó la cuenta de',
  _ => action,
};

/// Historial de auditoría: el admin ve lo suyo; el superadmin, todo.
class AuditList extends ConsumerWidget {
  const AuditList({super.key, required this.title, this.limit = 30});

  final String title;

  /// Las más recientes primero; el resto se omite para no alargar la página.
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          container: true,
          child: Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 10),
        ref
            .watch(adminActionsProvider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => ErrorState(
                'No pudimos cargar el historial.',
                onRetry: () => ref.invalidate(adminActionsProvider),
              ),
              data: (actions) => actions.isEmpty
                  ? Semantics(
                      container: true,
                      child: const Text('Aún no hay acciones registradas.'),
                    )
                  : AdminCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final a in actions.take(limit)) _AuditRow(a),
                        ],
                      ),
                    ),
            ),
      ],
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow(this.action);

  final AdminAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = action;
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${a.adminName} ${auditVerb(a.action)} ${a.targetName}'),
            Text(
              [
                formatDateTime(a.createdAt),
                if (a.details != null && a.details!.isNotEmpty) a.details!,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
