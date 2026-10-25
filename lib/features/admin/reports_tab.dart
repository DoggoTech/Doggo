import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/report.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../../shared/widgets/pill.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import '../../shared/widgets/error_state.dart';

/// Reportes de usuarios: abiertos (por atender) y atendidos.
class ReportsTab extends ConsumerStatefulWidget {
  const ReportsTab({super.key});

  @override
  ConsumerState<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<ReportsTab> {
  bool _showOpen = true;

  @override
  Widget build(BuildContext context) {
    return ref
        .watch(reportsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorState(
            'No pudimos cargar los reportes.',
            onRetry: () => ref.invalidate(reportsProvider),
          ),
          data: (all) {
            final open = all
                .where((r) => r.status == ReportStatus.open)
                .toList();
            final done = all
                .where((r) => r.status != ReportStatus.open)
                .toList();
            final shown = _showOpen ? open : done;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                const AdminHeader('Reportes'),
                Wrap(
                  spacing: 8,
                  children: [
                    Pill(
                      elevated: false,
                      label: open.isEmpty
                          ? 'Abiertos'
                          : 'Abiertos (${open.length})',
                      selected: _showOpen,
                      onTap: () => setState(() => _showOpen = true),
                    ),
                    Pill(
                      elevated: false,
                      label: done.isEmpty
                          ? 'Atendidos'
                          : 'Atendidos (${done.length})',
                      selected: !_showOpen,
                      onTap: () => setState(() => _showOpen = false),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Semantics(
                      container: true,
                      child: Text(
                        _showOpen
                            ? 'No hay reportes abiertos.'
                            : 'Aún no hay reportes atendidos.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  )
                else
                  for (final r in shown)
                    _ReportCard(key: ValueKey(r.id), report: r),
              ],
            );
          },
        );
  }
}

class _ReportCard extends ConsumerStatefulWidget {
  const _ReportCard({super.key, required this.report});

  final Report report;

  @override
  ConsumerState<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<_ReportCard> {
  bool _busy = false;

  Future<void> _resolve(ReportStatus status, {bool suspend = false}) async {
    final r = widget.report;
    if (suspend) {
      final ok = await confirmAction(
        context,
        title: '¿Suspender a ${r.reportedName}?',
        body: 'Desaparecerá del mapa y no podrá reservar ni recibir reservas.',
        confirm: 'Sí, suspender',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(repositoryProvider)
          .resolveReport(r.id, status, suspendReported: suspend);
      refreshAdminData(ref);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            suspend
                ? '${r.reportedName} fue suspendido'
                : 'Reporte ${status.label.toLowerCase()}',
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
    final r = widget.report;
    final theme = Theme.of(context);
    final first = r.reportedName.split(' ').first;
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            child: Text(
              r.reason.label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Semantics(
            container: true,
            child: Text(
              '${r.reporterName} reportó a ${r.reportedName}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (r.comment != null)
            Semantics(
              container: true,
              child: Text('“${r.comment}”', style: theme.textTheme.bodyMedium),
            ),
          Text(
            '${formatDateTime(r.createdAt)}${r.bookingId != null ? ' · sobre una reserva' : ''}'
            '${r.status != ReportStatus.open ? ' · ${r.status.label}' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
          if (r.status == ReportStatus.open) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                LabeledButton(
                  text: 'Marcar revisado',
                  label: 'Marcar revisado: reporte a ${r.reportedName}',
                  onPressed: _busy
                      ? null
                      : () => _resolve(ReportStatus.reviewed),
                ),
                LabeledButton(
                  text: 'Descartar',
                  label: 'Descartar: reporte a ${r.reportedName}',
                  onPressed: _busy
                      ? null
                      : () => _resolve(ReportStatus.dismissed),
                ),
                LabeledButton(
                  text: 'Suspender a $first',
                  label: 'Suspender a ${r.reportedName}',
                  filled: true,
                  onPressed: _busy
                      ? null
                      : () => _resolve(ReportStatus.reviewed, suspend: true),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
