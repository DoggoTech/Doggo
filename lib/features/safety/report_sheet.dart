import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/report.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../../shared/widgets/pill.dart';

/// Reportar a un usuario, opcionalmente sobre una reserva concreta.
Future<void> showReportSheet(
  BuildContext context, {
  required String userId,
  required String userName,
  String? bookingId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) =>
        _ReportSheet(userId: userId, userName: userName, bookingId: bookingId),
  );
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({
    required this.userId,
    required this.userName,
    this.bookingId,
  });

  final String userId;
  final String userName;
  final String? bookingId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  ReportReason? _reason;
  final _comment = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .createReport(
            reportedUserId: widget.userId,
            bookingId: widget.bookingId,
            reason: _reason!,
            comment: _comment.text,
          );
      if (mounted) setState(() => _sent = true);
    } on ValidationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_sent) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.shield_rounded,
              size: 72,
              color: AppColors.success,
            ),
            const SizedBox(height: 12),
            Text(
              'Gracias por avisarnos',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Nuestro equipo revisará el reporte. Si hay un peligro inmediato, llama al 123.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Listo'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Reportar a ${widget.userName}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'El reporte es confidencial: ${widget.userName.split(' ').first} no sabrá quién lo envió.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Motivo',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in ReportReason.values)
                  Pill(
                    elevated: false,
                    label: r.label,
                    selected: _reason == r,
                    onTap: () => setState(() => _reason = r),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _comment,
              minLines: 2,
              maxLines: 5,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: '¿Qué pasó? (opcional)',
              ),
            ),
            if (_error != null)
              Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: (_reason != null && !_busy) ? _send : null,
              child: const Text('Enviar reporte'),
            ),
          ],
        ),
      ),
    );
  }
}
