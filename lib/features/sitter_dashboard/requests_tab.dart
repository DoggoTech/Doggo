import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/booking.dart';
import '../../data/models/profile.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../bookings/bookings_providers.dart';
import '../safety/report_sheet.dart';
import 'countdown.dart';
import 'map_visibility_banner.dart';
import 'pending_review_view.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/appear_in.dart';

/// Solicitudes pendientes del cuidador. Llegan solas (stream) y vencen solas.
class RequestsTab extends ConsumerWidget {
  const RequestsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authStateProvider).value;
    if (profile?.status == UserStatus.pendingReview) {
      return const PendingReviewView();
    }

    // Aviso cuando llega una solicitud nueva mientras miras la pantalla.
    ref.listen(myBookingsProvider, (previous, next) {
      final before = {
        for (final b in previous?.value ?? const <Booking>[]) b.id,
      };
      for (final b in next.value ?? const <Booking>[]) {
        if (b.status == BookingStatus.pending &&
            previous?.value != null &&
            !before.contains(b.id)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Nueva solicitud de ${b.ownerName}')),
          );
        }
      }
    });

    final bookings = ref.watch(myBookingsProvider);
    return bookings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ErrorState(
        'No pudimos cargar tus solicitudes.',
        onRetry: () => ref.invalidate(myBookingsProvider),
      ),
      data: (all) {
        final now = DateTime.now();
        final pending =
            all
                .where(
                  (b) =>
                      b.status == BookingStatus.pending &&
                      b.responseDeadline.isAfter(now),
                )
                .toList()
              ..sort(
                (a, b) => a.responseDeadline.compareTo(b.responseDeadline),
              );
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Semantics(
              header: true,
              container: true,
              child: Text(
                'Solicitudes',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tienes 2 horas para responder cada solicitud.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            // Sin servicios o sin zona, ningún dueño puede encontrarte.
            const MapVisibilityBanner(),
            if (pending.isEmpty)
              const _Empty()
            else
              for (final b in pending)
                AppearIn(
                  key: ValueKey(b.id),
                  child: _RequestCard(booking: b),
                ),
          ],
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(Icons.inbox_rounded, size: 56, color: AppColors.muted),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            child: Text(
              'No tienes solicitudes pendientes.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Cuando un dueño te reserve, aparecerá aquí al instante.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({required this.booking});

  final Booking booking;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(repositoryProvider)
          .respondToBooking(widget.booking.id, accept: accept);
      messenger.showSnackBar(
        SnackBar(
          content: Text(accept ? 'Reserva aceptada' : 'Solicitud rechazada'),
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
    final b = widget.booking;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
            container: true,
            child: Text(
              '${b.ownerName} · ${b.dogName}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Semantics(
            container: true,
            child: Text(
              '${b.service.label} · ${formatDateTime(b.startAt)} a ${formatTime(b.endAt)}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Semantics(
            container: true,
            child: Text(
              'Total ${formatCop(b.totalCop)}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ResponseCountdown(deadline: b.responseDeadline),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _respond(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Rechazar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _respond(true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Aceptar'),
                ),
              ),
            ],
          ),
          // Discreto y aparte: el contador y las respuestas son lo principal.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showReportSheet(
                context,
                userId: b.ownerId,
                userName: b.ownerName,
                bookingId: b.id,
              ),
              style: TextButton.styleFrom(foregroundColor: AppColors.muted),
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: Text('Reportar a ${b.ownerName.split(' ').first}'),
            ),
          ),
        ],
      ),
    );
  }
}
