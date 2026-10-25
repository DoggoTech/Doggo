import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/booking.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../../shared/widgets/pill.dart';
import '../sitter_dashboard/countdown.dart';
import '../safety/report_sheet.dart';
import 'bookings_providers.dart';
import 'contact_box.dart';
import 'review_sheet.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/appear_in.dart';

enum _Section { upcoming, past, cancelled }

/// "Mis reservas" del dueño, con el estado en vivo.
class OwnerBookingsTab extends ConsumerStatefulWidget {
  const OwnerBookingsTab({super.key});

  @override
  ConsumerState<OwnerBookingsTab> createState() => _OwnerBookingsTabState();
}

class _OwnerBookingsTabState extends ConsumerState<OwnerBookingsTab> {
  _Section _section = _Section.upcoming;

  /// Una reserva pendiente con el plazo pasado ya es "vencida" para la UI,
  /// aunque el servidor todavía no la haya marcado.
  static BookingStatus _effective(Booking b, DateTime now) =>
      b.status == BookingStatus.pending && !b.responseDeadline.isAfter(now)
      ? BookingStatus.expired
      : b.status;

  static _Section _sectionOf(Booking b, DateTime now) {
    switch (_effective(b, now)) {
      case BookingStatus.pending:
        return _Section.upcoming;
      case BookingStatus.accepted:
        return b.endAt.isAfter(now) ? _Section.upcoming : _Section.past;
      case BookingStatus.completed:
        return _Section.past;
      case BookingStatus.rejected:
      case BookingStatus.cancelled:
      case BookingStatus.expired:
        return _Section.cancelled;
    }
  }

  void _announceChanges(List<Booking>? before, List<Booking> after) {
    if (before == null) return;
    final old = {for (final b in before) b.id: b.status};
    for (final b in after) {
      final prev = old[b.id];
      if (prev == null || prev == b.status) continue;
      final name = b.sitterName.split(' ').first;
      final msg = switch (b.status) {
        BookingStatus.accepted => '$name aceptó tu reserva',
        BookingStatus.rejected => '$name rechazó tu solicitud',
        BookingStatus.expired => 'Tu solicitud a $name venció sin respuesta',
        BookingStatus.completed => '$name marcó tu reserva como completada',
        _ => null,
      };
      if (msg != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(myBookingsProvider, (prev, next) {
      if (next.value != null) _announceChanges(prev?.value, next.value!);
    });
    final theme = Theme.of(context);
    return ref
        .watch(myBookingsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorState(
            'No pudimos cargar tus reservas.',
            onRetry: () => ref.invalidate(myBookingsProvider),
          ),
          data: (all) {
            final now = DateTime.now();
            List<Booking> of(_Section s) =>
                all.where((b) => _sectionOf(b, now) == s).toList();
            final shown = of(_section)
              ..sort(
                (a, b) => _section == _Section.upcoming
                    ? a.startAt.compareTo(b.startAt)
                    : b.startAt.compareTo(a.startAt),
              );
            String label(_Section s, String name) {
              final n = of(s).length;
              return n == 0 ? name : '$name ($n)';
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Semantics(
                  header: true,
                  container: true,
                  child: Text(
                    'Mis reservas',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (s, name) in [
                      (_Section.upcoming, 'Próximas'),
                      (_Section.past, 'Pasadas'),
                      (_Section.cancelled, 'Canceladas'),
                    ])
                      Pill(
                        elevated: false,
                        label: label(s, name),
                        selected: _section == s,
                        onTap: () => setState(() => _section = s),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.event_note_rounded,
                          size: 56,
                          color: AppColors.muted,
                        ),
                        const SizedBox(height: 12),
                        Semantics(
                          container: true,
                          child: Text(switch (_section) {
                            _Section.upcoming => 'No tienes reservas próximas.',
                            _Section.past => 'Aún no tienes reservas pasadas.',
                            _Section.cancelled =>
                              'No tienes reservas canceladas.',
                          }, style: theme.textTheme.titleMedium),
                        ),
                      ],
                    ),
                  )
                else
                  for (final b in shown)
                    AppearIn(
                      key: ValueKey(b.id),
                      child: _BookingCard(
                        booking: b,
                        status: _effective(b, now),
                      ),
                    ),
              ],
            );
          },
        );
  }
}

class _BookingCard extends ConsumerStatefulWidget {
  const _BookingCard({required this.booking, required this.status});

  final Booking booking;
  final BookingStatus status;

  @override
  ConsumerState<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends ConsumerState<_BookingCard> {
  bool _busy = false;

  Color get _statusColor => switch (widget.status) {
    BookingStatus.pending => AppColors.primary,
    BookingStatus.accepted || BookingStatus.completed => AppColors.success,
    BookingStatus.rejected => AppColors.error,
    BookingStatus.cancelled || BookingStatus.expired => AppColors.muted,
  };

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Cancelar la reserva?'),
        content: Text('Le avisaremos a ${widget.booking.sitterName}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Volver'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).cancelBooking(widget.booking.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Reserva cancelada')),
      );
    } on ValidationFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final status = widget.status;
    final theme = Theme.of(context);
    final first = b.sitterName.split(' ').first;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  container: true,
                  child: Text(
                    '${b.service.label} con ${b.sitterName}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              Semantics(
                container: true,
                label: 'Estado: ${status.label}',
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.label,
                    style: TextStyle(
                      color: _statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Semantics(
            container: true,
            child: Text(
              '${b.dogName} · ${formatDateTime(b.startAt)} · ${formatCop(b.totalCop)}',
            ),
          ),
          if (status == BookingStatus.pending) ...[
            const SizedBox(height: 8),
            ResponseCountdown(
              deadline: b.responseDeadline,
              label: '$first responde en',
            ),
            const SizedBox(height: 4),
            Text(
              'Verás su teléfono y dirección cuando acepte.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
          ],
          if (status == BookingStatus.accepted) ContactBox(booking: b),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (status.isActive)
                OutlinedButton(
                  onPressed: _busy ? null : _cancel,
                  child: const Text('Cancelar reserva'),
                ),
              if (status == BookingStatus.completed && !b.reviewed)
                FilledButton(
                  onPressed: () => showReviewSheet(context, b),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  child: Text('Calificar a $first'),
                ),
              TextButton(
                onPressed: () => showReportSheet(
                  context,
                  userId: b.sitterId,
                  userName: b.sitterName,
                  bookingId: b.id,
                ),
                child: const Text('Reportar'),
              ),
              if (status == BookingStatus.completed && b.reviewed)
                Semantics(
                  container: true,
                  child: Text(
                    'Ya calificaste esta reserva',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
