import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/sitter_case.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../../shared/open_link.dart';

/// Caso del cuidador en revisión, en vivo (admin asignado y reunión).
final myCaseProvider = StreamProvider.autoDispose<SitterCase?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(repositoryProvider).watchMyCase();
});

final myDocumentsProvider = FutureProvider.autoDispose<List<SitterDocument>>(
  (ref) => ref.watch(repositoryProvider).fetchMyDocuments(),
);

/// Pantalla del cuidador nuevo mientras un admin no lo aprueba: su proceso
/// (admin asignado, reunión virtual) y sus certificados opcionales.
class PendingReviewView extends StatelessWidget {
  const PendingReviewView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget step(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        const Icon(
          Icons.hourglass_top_rounded,
          size: 72,
          color: AppColors.primary,
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          container: true,
          child: Text(
            'Tu perfil está en revisión',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Un administrador de Doggo revisará tu perfil. Mientras tanto no apareces '
          'en el mapa ni puedes recibir reservas.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 24),
        const _ProcessCard(),
        const SizedBox(height: 16),
        const _DocumentsCard(),
        const SizedBox(height: 16),
        _Card(
          title: 'Mientras tanto',
          children: [
            step(
              Icons.sell_rounded,
              'Activa tus servicios y pon tus precios en la pestaña Servicios.',
            ),
            step(
              Icons.calendar_month_rounded,
              'Define en qué días y horas atiendes.',
            ),
            step(
              Icons.verified_user_rounded,
              'Al aprobarte sales en el mapa con la insignia "Verificado".',
            ),
          ],
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

/// Pasos del proceso: caso asignado -> reunión virtual -> decisión.
class _ProcessCard extends ConsumerStatefulWidget {
  const _ProcessCard();

  @override
  ConsumerState<_ProcessCard> createState() => _ProcessCardState();
}

class _ProcessCardState extends ConsumerState<_ProcessCard> {
  bool _busy = false;

  Future<void> _confirm() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).confirmMeeting();
      messenger.showSnackBar(
        const SnackBar(content: Text('Confirmaste tu asistencia')),
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
    final c = ref.watch(myCaseProvider).value;
    final admin = c?.assignedAdminName;
    final stage = c?.stage ?? CaseStage.fresh;

    Widget step({
      required int n,
      required bool done,
      required bool current,
      required String title,
      required String body,
      List<Widget> actions = const [],
    }) {
      final color = done
          ? AppColors.success
          : current
          ? AppColors.primary
          : AppColors.muted;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: color.withValues(alpha: 0.15),
              child: done
                  ? Icon(Icons.check_rounded, size: 18, color: color)
                  : Text(
                      '$n',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    container: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(body, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    final meeting = c != null && c.hasMeeting ? c : null;
    return _Card(
      title: 'Tu proceso',
      children: [
        step(
          n: 1,
          done: admin != null,
          current: admin == null,
          title: 'Revisión asignada',
          body: admin != null
              ? 'Tu caso lo lleva $admin, del equipo de Doggo.'
              : 'Pronto un administrador tomará tu caso.',
        ),
        step(
          n: 2,
          done: stage == CaseStage.meetingDone,
          current: stage != CaseStage.meetingDone,
          title: 'Reunión virtual inicial',
          body: switch (stage) {
            CaseStage.fresh =>
              '${admin ?? 'Tu administrador'} te propondrá una fecha para una '
                  'videollamada corta en la que te conoceremos.',
            CaseStage.meetingScheduled =>
              'Videollamada el ${formatDateTime(meeting!.meetingAt!)}.'
                  '${meeting.meetingConfirmed ? ' Confirmaste tu asistencia.' : ''}',
            CaseStage.meetingDone => 'Ya tuviste la reunión. ¡Gracias!',
          },
          actions: [
            if (stage == CaseStage.meetingScheduled && meeting != null) ...[
              FilledButton.icon(
                onPressed: () =>
                    openExternal(context, Uri.parse(meeting.meetingLink!)),
                icon: const Icon(Icons.videocam_rounded),
                label: const Text('Unirme a la reunión'),
              ),
              if (!meeting.meetingConfirmed)
                OutlinedButton(
                  onPressed: _busy ? null : _confirm,
                  child: const Text('Confirmar asistencia'),
                ),
            ],
          ],
        ),
        step(
          n: 3,
          done: false,
          current: stage == CaseStage.meetingDone,
          title: 'Decisión',
          body:
              'Te aprobamos o te contamos qué falta. Al aprobarte apareces en '
              'el mapa.',
        ),
      ],
    );
  }
}

/// Certificados opcionales (PDF o imagen, hasta 10 MB, máximo 10).
class _DocumentsCard extends ConsumerStatefulWidget {
  const _DocumentsCard();

  @override
  ConsumerState<_DocumentsCard> createState() => _DocumentsCardState();
}

class _DocumentsCardState extends ConsumerState<_DocumentsCard> {
  bool _busy = false;

  Future<void> _upload() async {
    final messenger = ScaffoldMessenger.of(context);
    final kind = await showModalBottomSheet<SitterDocKind>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _UploadSheet(),
    );
    if (kind == null) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .uploadMyDocument(
            kind: kind,
            fileName: file.name,
            bytes: await file.xFile.readAsBytes(),
          );
      ref.invalidate(myDocumentsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Documento subido')));
    } on ValidationFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(SitterDocument doc) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).deleteMyDocument(doc.id);
      ref.invalidate(myDocumentsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('Borraste ${doc.fileName}')),
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
    final docs = ref.watch(myDocumentsProvider).value ?? const [];
    return _Card(
      title: 'Certificados (opcional)',
      children: [
        Text(
          'No es obligatorio, pero subir tus certificados de cuidado animal, '
          'primeros auxilios o cursos aumenta mucho tus probabilidades de ser '
          'aprobado. Solo los ve el equipo de Doggo.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        for (final d in docs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              d.isImage ? Icons.image_rounded : Icons.picture_as_pdf_rounded,
              color: AppColors.primary,
            ),
            title: Text(d.fileName, overflow: TextOverflow.ellipsis),
            subtitle: Text('${d.kind.label} · ${formatFileSize(d.sizeBytes)}'),
            onTap: () => openSitterDocument(context, ref, d),
            trailing: IconButton(
              tooltip: 'Borrar ${d.fileName}',
              onPressed: _busy ? null : () => _delete(d),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: _busy || docs.length >= maxSitterDocs ? null : _upload,
          icon: const Icon(Icons.upload_file_rounded),
          label: Text(_busy ? 'Subiendo…' : 'Subir documento'),
        ),
      ],
    );
  }
}

/// Elige el tipo de documento y autoriza su revisión antes de elegir el archivo.
class _UploadSheet extends StatefulWidget {
  const _UploadSheet();

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  SitterDocKind _kind = SitterDocKind.certificate;
  bool _consent = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Subir documento',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'PDF, JPG, PNG o WEBP de hasta 10 MB.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 8),
            RadioGroup<SitterDocKind>(
              groupValue: _kind,
              onChanged: (k) => setState(() => _kind = k ?? _kind),
              child: Column(
                children: [
                  for (final k in SitterDocKind.values)
                    RadioListTile<SitterDocKind>(
                      value: k,
                      title: Text(k.label),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            CheckboxListTile(
              value: _consent,
              onChanged: (v) => setState(() => _consent = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Autorizo a Doggo a revisar este documento solo para verificar '
                'mi perfil (Ley 1581 de 2012).',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _consent ? () => Navigator.pop(context, _kind) : null,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              child: const Text('Elegir archivo'),
            ),
          ],
        ),
      ),
    );
  }
}
