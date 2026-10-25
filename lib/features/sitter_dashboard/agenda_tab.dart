import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/booking.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../bookings/bookings_providers.dart';

/// Agenda del cuidador: reservas aceptadas (próximas) y completadas.
class AgendaTab extends ConsumerWidget {
  const AgendaTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref
        .watch(myBookingsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text('No pudimos cargar tu agenda.')),
          data: (all) {
            final upcoming =
                all.where((b) => b.status == BookingStatus.accepted).toList()
                  ..sort((a, b) => a.startAt.compareTo(b.startAt));
            final done = all
                .where((b) => b.status == BookingStatus.completed)
                .toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Semantics(
                  header: true,
                  container: true,
                  child: Text(
                    'Agenda',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _Section(title: 'Próximas'),
                if (upcoming.isEmpty)
                  Semantics(
                    container: true,
                    child: Text(
                      'No tienes reservas aceptadas.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  )
                else
                  for (final b in upcoming)
                    _AgendaCard(key: ValueKey(b.id), booking: b),
                if (done.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _Section(title: 'Completadas'),
                  for (final b in done)
                    _AgendaCard(key: ValueKey(b.id), booking: b),
                ],
              ],
            );
          },
        );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      header: true,
      container: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w900),
      ),
    ),
  );
}

class _AgendaCard extends ConsumerStatefulWidget {
  const _AgendaCard({super.key, required this.booking});

  final Booking booking;

  @override
  ConsumerState<_AgendaCard> createState() => _AgendaCardState();
}

class _AgendaCardState extends ConsumerState<_AgendaCard> {
  bool _busy = false;

  Future<void> _complete() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).completeBooking(widget.booking.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Reserva completada')),
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
    final theme = Theme.of(context);
    final accepted = b.status == BookingStatus.accepted;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: accepted ? AppTheme.softShadow : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              container: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatDateTime(b.startAt)} · ${b.service.label}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${b.dogName}, de ${b.ownerName}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    '${formatCop(b.totalCop)} · ${b.status.label}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (accepted)
            TextButton(
              onPressed: _busy ? null : _complete,
              child: const Text('Marcar completada'),
            ),
        ],
      ),
    );
  }
}
