import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/admin.dart';
import '../../data/models/profile.dart';
import '../../data/models/service_type.dart';
import '../../data/models/sitter_case.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../../shared/open_link.dart';
import '../map/sitter_list.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import '../../shared/widgets/error_state.dart';

/// Cuidadores en revisión. Cada uno es un caso repartido a un admin, que
/// agenda una reunión virtual inicial y luego aprueba (insignia "Verificado")
/// o rechaza.
class ApprovalsTab extends ConsumerStatefulWidget {
  const ApprovalsTab({super.key});

  @override
  ConsumerState<ApprovalsTab> createState() => _ApprovalsTabState();
}

class _ApprovalsTabState extends ConsumerState<ApprovalsTab> {
  /// `null` = según el rol: el admin ve sus casos; el superadmin, todos.
  bool? _onlyMine;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authStateProvider).value;
    final onlyMine = _onlyMine ?? me?.role != UserRole.superadmin;
    // Un caso nuevo o reasignado recarga la lista sin tocar nada.
    ref.listen(myNewCasesProvider, (prev, next) {
      if (prev?.value != null && prev?.value != next.value) {
        ref.invalidate(pendingSittersProvider);
      }
    });
    return ref
        .watch(pendingSittersProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorState(
            'No pudimos cargar las solicitudes de cuidadores.',
            onRetry: () => ref.invalidate(pendingSittersProvider),
          ),
          data: (all) {
            bool mine(PendingSitter p) =>
                p.sitterCase?.assignedAdminId == me?.id;
            final sorted = [...all]
              ..sort((a, b) => (mine(b) ? 1 : 0) - (mine(a) ? 1 : 0));
            final list = onlyMine
                ? sorted
                      .where(
                        (p) => mine(p) || p.sitterCase?.assignedAdminId == null,
                      )
                      .toList()
                : sorted;
            final mineCount = all.where(mine).length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                const AdminHeader(
                  'Aprobaciones',
                  subtitle:
                      'Cada cuidador nuevo se asigna a un admin. Agenda una '
                      'reunión virtual y luego decide. No aparecen en el mapa '
                      'hasta que los apruebes.',
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: Text('Mis casos ($mineCount)'),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('Todos (${all.length})'),
                      ),
                    ],
                    selected: {onlyMine},
                    onSelectionChanged: (v) =>
                        setState(() => _onlyMine = v.first),
                  ),
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
                            onlyMine
                                ? 'No tienes casos por revisar.'
                                : 'No hay cuidadores por aprobar.',
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
            );
          },
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

  Future<void> _schedule() async {
    final u = widget.pending.user;
    final c = widget.pending.sitterCase;
    final result = await showDialog<(DateTime, String)>(
      context: context,
      builder: (_) => _MeetingDialog(
        name: u.name,
        initialAt: c?.meetingAt,
        initialLink: c?.meetingLink,
      ),
    );
    if (result == null) return;
    await _run(
      () => ref
          .read(repositoryProvider)
          .scheduleMeeting(u.id, at: result.$1, link: result.$2),
      'Reunión con ${u.name} agendada para el ${formatDateTime(result.$1)}',
    );
  }

  Future<void> _reassign() async {
    final u = widget.pending.user;
    final current = widget.pending.sitterCase?.assignedAdminId;
    final handlers = await ref.read(caseHandlersProvider.future);
    if (!mounted) return;
    final picked = await showDialog<AdminUserRow>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('¿Quién lleva el caso de ${u.name}?'),
        children: [
          for (final h in handlers)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, h),
              child: Row(
                children: [
                  Expanded(child: Text('${h.name} · ${h.role.label}')),
                  if (h.id == current)
                    const Icon(Icons.check_rounded, color: AppColors.success),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || picked.id == current) return;
    await _run(
      () => ref.read(repositoryProvider).reassignCase(u.id, picked.id),
      'El caso de ${u.name} ahora lo lleva ${picked.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.pending.user;
    final s = widget.pending.sitter;
    final c = widget.pending.sitterCase;
    final docs = widget.pending.documents;
    final me = ref.watch(authStateProvider).value;
    final isSuper = me?.role == UserRole.superadmin;
    final unassigned = c != null && c.assignedAdminId == null;
    final canHandle = c == null || c.assignedAdminId == me?.id || isSuper;
    final repo = ref.read(repositoryProvider);
    final theme = Theme.of(context);
    final services = ServiceType.values.where(s.offers).toList();

    final handler = c == null
        ? null
        : unassigned
        ? 'Sin asignar'
        : c.assignedAdminId == me?.id
        ? 'Lo llevas tú'
        : 'Lo lleva ${c.assignedAdminName ?? 'otro admin'}';
    final meetingText = switch (c?.stage) {
      null || CaseStage.fresh => 'Reunión: sin agendar',
      CaseStage.meetingScheduled =>
        'Reunión: ${formatDateTime(c!.meetingAt!)} · '
            '${c.meetingConfirmed ? 'el cuidador confirmó' : 'sin confirmar'}',
      CaseStage.meetingDone => 'Reunión hecha',
    };

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
          if (c != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Pill(
                  c.stage.label,
                  color: c.stage == CaseStage.meetingDone
                      ? AppColors.success
                      : AppColors.primary,
                ),
                _Pill(
                  handler!,
                  color: unassigned ? AppColors.error : AppColors.muted,
                ),
                if (docs.isNotEmpty)
                  _Pill(
                    docs.length == 1
                        ? '1 certificado'
                        : '${docs.length} certificados',
                    color: AppColors.success,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Semantics(
              container: true,
              child: Text(meetingText, style: theme.textTheme.bodySmall),
            ),
          ],
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
          if (docs.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final d in docs)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  d.isImage
                      ? Icons.image_rounded
                      : Icons.picture_as_pdf_rounded,
                  color: AppColors.primary,
                ),
                title: Text(d.fileName, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${d.kind.label} · ${formatFileSize(d.sizeBytes)}',
                ),
                trailing: TextButton(
                  onPressed: () => openSitterDocument(context, ref, d),
                  child: Semantics(
                    label: 'Ver ${d.fileName}',
                    excludeSemantics: true,
                    child: const Text('Ver'),
                  ),
                ),
              ),
          ] else if (c != null) ...[
            const SizedBox(height: 4),
            Text(
              'No ha subido certificados (son opcionales).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (!canHandle && !unassigned)
            Text(
              'Solo quien lleva el caso o el superadmin pueden agendar y decidir.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (unassigned)
                LabeledButton(
                  text: 'Tomar caso',
                  label: 'Tomar el caso de ${u.name}',
                  filled: true,
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => repo.takeCase(u.id),
                          'Ahora llevas el caso de ${u.name}',
                        ),
                ),
              if (isSuper && c != null)
                LabeledButton(
                  text: 'Reasignar',
                  label: 'Reasignar el caso de ${u.name}',
                  onPressed: _busy ? null : _reassign,
                ),
              if (canHandle && c != null) ...[
                LabeledButton(
                  text: c.hasMeeting ? 'Cambiar reunión' : 'Agendar reunión',
                  label: c.hasMeeting
                      ? 'Cambiar la reunión con ${u.name}'
                      : 'Agendar reunión con ${u.name}',
                  onPressed: _busy ? null : _schedule,
                ),
                if (c.stage == CaseStage.meetingScheduled) ...[
                  LabeledButton(
                    text: 'Abrir enlace',
                    label: 'Abrir el enlace de la reunión con ${u.name}',
                    onPressed: () =>
                        openExternal(context, Uri.parse(c.meetingLink!)),
                  ),
                  LabeledButton(
                    text: 'Reunión hecha',
                    label: 'Marcar la reunión con ${u.name} como hecha',
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => repo.markMeetingDone(u.id),
                            'Reunión con ${u.name} marcada como hecha',
                          ),
                  ),
                ],
              ],
              if (canHandle) ...[
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
                              () =>
                                  repo.setSitterApproval(u.id, approve: false),
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
                      : () async {
                          // La reunión es lo recomendado, no un requisito.
                          if (c != null && c.stage != CaseStage.meetingDone) {
                            final ok = await confirmAction(
                              context,
                              title: '¿Aprobar sin reunión?',
                              body:
                                  'Aún no marcas la reunión con ${u.name} como '
                                  'hecha. ¿Quieres aprobarlo igual?',
                              confirm: 'Sí, aprobar',
                            );
                            if (!ok) return;
                          }
                          await _run(
                            () => repo.setSitterApproval(u.id, approve: true),
                            '${u.name} fue aprobado',
                          );
                        },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// Fecha, hora y enlace de la videollamada. Devuelve `(fecha, enlace)`.
class _MeetingDialog extends StatefulWidget {
  const _MeetingDialog({required this.name, this.initialAt, this.initialLink});

  final String name;
  final DateTime? initialAt;
  final String? initialLink;

  @override
  State<_MeetingDialog> createState() => _MeetingDialogState();
}

class _MeetingDialogState extends State<_MeetingDialog> {
  late DateTime _at;
  late final TextEditingController _link;
  String? _error;

  @override
  void initState() {
    super.initState();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _at =
        widget.initialAt ??
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10);
    _link = TextEditingController(text: widget.initialLink ?? '');
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _at.isBefore(now) ? now : _at,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (d != null) {
      setState(
        () => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute),
      );
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (t != null) {
      setState(
        () => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute),
      );
    }
  }

  void _save() {
    final error = validateMeeting(_at, _link.text, DateTime.now());
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, (_at, _link.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reunión con ${widget.name}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Videollamada corta para conocer al cuidador. La verá en su '
              'pantalla y podrá confirmar su asistencia.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_rounded),
                    label: Text(formatDay(_at)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(formatTime(_at)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Enlace de la videollamada',
                hintText: 'https://meet.google.com/…',
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
        FilledButton(onPressed: _save, child: const Text('Guardar reunión')),
      ],
    );
  }
}
