import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/booking_rules.dart';
import '../../data/models/booking.dart';
import '../../data/models/service_type.dart';
import '../../data/models/sitter_summary.dart';
import '../../data/pricing.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../../shared/widgets/pill.dart';
import '../sitter_profile/sitter_providers.dart';
import '../dogs/dog_form_dialog.dart';

/// Franja de horas de inicio que se ofrecen, en pasos de 30 min.
const _firstMinute = 7 * 60;
const _lastMinute = 19 * 60;
const _slotMinutes = 30;
const _daysAhead = 14;

/// Hoja compacta de reserva que sube sobre el perfil del cuidador.
Future<void> showBookingSheet(BuildContext context, SitterSummary sitter) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _BookingSheet(sitter: sitter),
  );
}

class _BookingSheet extends ConsumerStatefulWidget {
  const _BookingSheet({required this.sitter});

  final SitterSummary sitter;

  @override
  ConsumerState<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends ConsumerState<_BookingSheet> {
  late ServiceType _service = widget.sitter.offers(ServiceType.walk)
      ? ServiceType.walk
      : ServiceType.values.firstWhere(widget.sitter.offers);

  /// Minutos (paseo), días (guardería) o noches (hospedaje).
  late int _amount = _defaultAmount(_service);
  String? _dogId;
  late List<DateTime> _days = _bookableDays();
  late DateTime _day = _days.isEmpty ? DateTime.now() : _days.first;
  late DateTime _start = _days.isEmpty ? DateTime.now() : _slotsFor(_day).first;
  String? _error;
  bool _busy = false;
  Booking? _confirmed;

  static int _defaultAmount(ServiceType t) => t == ServiceType.walk ? 60 : 1;

  /// Horas de inicio válidas de un día: dentro de la franja y con al menos
  /// 1 h de anticipación (regla de la base).
  List<DateTime> _slotsFor(DateTime day) =>
      [
            for (var m = _firstMinute; m <= _lastMinute; m += _slotMinutes)
              DateTime(day.year, day.month, day.day, m ~/ 60, m % 60),
          ]
          .where(
            (s) => startIsBookable(s) && widget.sitter.availability.allows(s),
          )
          .toList();

  List<DateTime> _bookableDays() {
    final now = DateTime.now();
    return [
      for (var i = 0; i < _daysAhead; i++)
        DateTime(now.year, now.month, now.day + i),
    ].where((d) => _slotsFor(d).isNotEmpty).toList();
  }

  void _moveDay(int delta) {
    final i = _days.indexOf(_day) + delta;
    if (i < 0 || i >= _days.length) return;
    setState(() {
      _day = _days[i];
      // Conserva la hora si ese día la ofrece; si no, la primera disponible.
      final slots = _slotsFor(_day);
      _start = slots.firstWhere(
        (s) => s.hour == _start.hour && s.minute == _start.minute,
        orElse: () => slots.first,
      );
    });
  }

  void _moveTime(int delta) {
    final slots = _slotsFor(_day);
    final i = slots.indexOf(_start) + delta;
    if (i < 0 || i >= slots.length) return;
    setState(() => _start = slots[i]);
  }

  DateTime get _end => bookingEnd(_service, _start, amount: _amount);

  Future<void> _addDog() async {
    final dog = await showDogForm(context);
    if (dog != null && mounted) setState(() => _dogId = dog.id);
  }

  Future<void> _send(String dogId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final booking = await ref
          .read(repositoryProvider)
          .createBooking(
            sitterId: widget.sitter.id,
            dogId: dogId,
            service: _service,
            startAt: _start,
            endAt: _end,
          );
      if (mounted) setState(() => _confirmed = booking);
    } on ValidationFailure catch (e) {
      // La hora pudo dejar de ser válida mientras la hoja estaba abierta.
      if (mounted) {
        setState(() {
          _error = e.message;
          _days = _bookableDays();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmed != null) return _Confirmed(booking: _confirmed!);
    if (_days.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Semantics(
          container: true,
          child: Text(
            '${widget.sitter.name.split(' ').first} no tiene horarios disponibles en los próximos $_daysAhead días.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final s = widget.sitter;
    final theme = Theme.of(context);
    final dogs = ref.watch(myDogsProvider);
    final dogList = dogs.value ?? const [];
    // Con un solo perro, queda elegido.
    final dogId = _dogId ?? (dogList.length == 1 ? dogList.first.id : null);
    final slots = _slotsFor(_day);
    final dayIndex = _days.indexOf(_day);
    final slotIndex = slots.indexOf(_start);
    final price = s.services[_service]!;
    final units = bookingUnits(_service, _start, _end);
    final deadline = responseDeadline(DateTime.now(), _start);
    final firstName = s.name.split(' ').first;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reservar con $firstName',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in ServiceType.values.where(s.offers))
                Pill(
                  elevated: false,
                  label: '${t.label} · ${formatCop(s.services[t]!)}',
                  selected: _service == t,
                  onTap: () => setState(() {
                    _service = t;
                    _amount = _defaultAmount(t);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _StepperRow(
            title: 'Día',
            value: formatDayChip(_day, DateTime.now()),
            detail: formatDay(_day),
            prevLabel: 'Día anterior',
            nextLabel: 'Día siguiente',
            onPrev: dayIndex > 0 ? () => _moveDay(-1) : null,
            onNext: dayIndex < _days.length - 1 ? () => _moveDay(1) : null,
          ),
          _StepperRow(
            title: 'Hora',
            value: formatTime(_start),
            prevLabel: 'Hora anterior',
            nextLabel: 'Hora siguiente',
            onPrev: slotIndex > 0 ? () => _moveTime(-1) : null,
            onNext: slotIndex < slots.length - 1 ? () => _moveTime(1) : null,
          ),
          if (_service == ServiceType.walk)
            _StepperRow(
              title: 'Duración',
              value: '$_amount min',
              prevLabel: 'Menos minutos',
              nextLabel: 'Más minutos',
              onPrev: _amount > 30 ? () => setState(() => _amount = 30) : null,
              onNext: _amount < 60 ? () => setState(() => _amount = 60) : null,
            ),
          if (_service == ServiceType.daycare ||
              _service == ServiceType.boarding)
            _StepperRow(
              title: _service == ServiceType.daycare ? 'Días' : 'Noches',
              value: _service == ServiceType.daycare
                  ? (_amount == 1 ? '1 día' : '$_amount días')
                  : (_amount == 1 ? '1 noche' : '$_amount noches'),
              prevLabel: _service == ServiceType.daycare
                  ? 'Menos días'
                  : 'Menos noches',
              nextLabel: _service == ServiceType.daycare
                  ? 'Más días'
                  : 'Más noches',
              onPrev: _amount > 1 ? () => setState(() => _amount--) : null,
              onNext: _amount < (_service == ServiceType.daycare ? 7 : 14)
                  ? () => setState(() => _amount++)
                  : null,
            ),
          const SizedBox(height: 12),
          Text(
            'Perro',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          dogs.isLoading
              ? const LinearProgressIndicator()
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in dogList)
                      Pill(
                        elevated: false,
                        label: d.name,
                        selected: dogId == d.id,
                        onTap: () => setState(() => _dogId = d.id),
                      ),
                    Pill(
                      elevated: false,
                      icon: Icons.add_rounded,
                      label: dogList.isEmpty
                          ? 'Agregar mi perro'
                          : 'Agregar perro',
                      onTap: _addDog,
                    ),
                  ],
                ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  container: true,
                  child: Text(
                    'Total ${formatCop(price * units)}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                Semantics(
                  container: true,
                  child: Text(
                    '${_unitsText(_service, units)} × ${formatCop(price)} · '
                    '${formatTime(_start)} a ${formatDateTime(_end)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Semantics(
                  container: true,
                  child: Text(
                    '$firstName tiene hasta ${_deadlineText(deadline, _day)} para responder.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
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
            ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: (dogId != null && !_busy) ? () => _send(dogId) : null,
            child: Text(_busy ? 'Enviando…' : 'Enviar solicitud'),
          ),
          if (dogId == null && !dogs.isLoading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Elige tu perro para continuar.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _unitsText(ServiceType service, int units) {
  switch (service) {
    case ServiceType.walk:
      return '1 paseo';
    case ServiceType.daycare:
      return units == 1 ? '1 día' : '$units días';
    case ServiceType.boarding:
      return units == 1 ? '1 noche' : '$units noches';
    case ServiceType.homeVisit:
      return '1 visita';
    case ServiceType.grooming:
    case ServiceType.training:
      return '1 sesión';
  }
}

/// "las 11:30" si es hoy (o el día de la reserva), si no "sáb 25 oct, 11:30".
String _deadlineText(DateTime deadline, DateTime bookingDay) {
  final now = DateTime.now();
  final sameDay =
      deadline.year == now.year &&
      deadline.month == now.month &&
      deadline.day == now.day;
  return sameDay ? 'las ${formatTime(deadline)}' : formatDateTime(deadline);
}

/// Fila compacta "Título  [−]  valor  [+]".
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.title,
    required this.value,
    required this.prevLabel,
    required this.nextLabel,
    required this.onPrev,
    required this.onNext,
    this.detail,
  });

  final String title;
  final String value;
  final String? detail;
  final String prevLabel;
  final String nextLabel;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showDetail = detail != null && detail != value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _StepButton(
            label: prevLabel,
            icon: Icons.remove_rounded,
            onPressed: onPrev,
          ),
          Expanded(
            child: Semantics(
              container: true,
              label: '$title: $value',
              excludeSemantics: true,
              child: Column(
                children: [
                  Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (showDetail)
                    Text(
                      detail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          _StepButton(
            label: nextLabel,
            icon: Icons.add_rounded,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

/// Botón +/- con nombre accesible fijo (el tooltip de IconButton lo pierde).
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: IconButton.filledTonal(onPressed: onPressed, icon: Icon(icon)),
    );
  }
}

class _Confirmed extends StatelessWidget {
  const _Confirmed({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstName = booking.sitterName.split(' ').first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.4, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 88,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '¡Solicitud enviada!',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$firstName tiene hasta ${_deadlineText(booking.responseDeadline, booking.startAt)} '
            'para responder. Si acepta, verán el teléfono y la dirección del otro.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${booking.service.label} · ${booking.dogName}',
                  style: theme.textTheme.titleMedium,
                ),
                Text(formatDateTime(booking.startAt)),
                Text('Total ${formatCop(booking.totalCop)}'),
                const SizedBox(height: 6),
                Text(
                  'Estado: ${booking.status.label}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go(Routes.home);
            },
            child: const Text('Volver al mapa'),
          ),
        ],
      ),
    );
  }
}
