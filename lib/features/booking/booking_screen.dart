import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/booking.dart';
import '../../data/models/service_type.dart';
import '../../data/models/sitter_summary.dart';
import '../../data/pricing.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../../shared/widgets/pill.dart';
import '../sitter_profile/sitter_providers.dart';
import 'add_dog_dialog.dart';

/// Primera y última hora de inicio que se ofrecen.
const _firstHour = 7;
const _lastHour = 19;
const _daysAhead = 7;

class BookingScreen extends ConsumerWidget {
  const BookingScreen({super.key, required this.sitterId});

  final String sitterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sitter = ref.watch(sitterProvider(sitterId));
    return sitter.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('No pudimos cargar al cuidador.')),
      ),
      data: (s) => s == null
          ? Scaffold(
              appBar: AppBar(),
              body: const Center(
                child: Text('Este cuidador ya no está disponible.'),
              ),
            )
          : _BookingForm(sitter: s),
    );
  }
}

class _BookingForm extends ConsumerStatefulWidget {
  const _BookingForm({required this.sitter});

  final SitterSummary sitter;

  @override
  ConsumerState<_BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends ConsumerState<_BookingForm> {
  ServiceType? _service;
  String? _dogId;
  DateTime? _day;
  int? _hour;

  /// Minutos (paseo), días (guardería) o noches (hospedaje).
  int _amount = 1;
  String? _error;
  bool _busy = false;
  Booking? _confirmed;

  late final DateTime _today = DateTime.now();

  void _selectService(ServiceType t) => setState(() {
    _service = t;
    _amount = t == ServiceType.walk ? 60 : 1;
  });

  bool _hourAvailable(DateTime day, int hour) =>
      DateTime(day.year, day.month, day.day, hour).isAfter(DateTime.now());

  DateTime? get _start => (_day == null || _hour == null)
      ? null
      : DateTime(_day!.year, _day!.month, _day!.day, _hour!);

  DateTime? get _end => (_service == null || _start == null)
      ? null
      : bookingEnd(_service!, _start!, amount: _amount);

  bool get _complete => _service != null && _dogId != null && _start != null;

  Future<void> _addDog() async {
    final dog = await showAddDogDialog(context);
    if (dog != null && mounted) setState(() => _dogId = dog.id);
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final booking = await ref
          .read(repositoryProvider)
          .createBooking(
            sitterId: widget.sitter.id,
            dogId: _dogId!,
            service: _service!,
            startAt: _start!,
            endAt: _end!,
          );
      if (mounted) setState(() => _confirmed = booking);
    } on ValidationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sitter;
    if (_confirmed != null) return _Confirmed(booking: _confirmed!);

    final theme = Theme.of(context);
    final dogs = ref.watch(myDogsProvider);
    final days = [
      for (var i = 0; i < _daysAhead; i++)
        DateTime(_today.year, _today.month, _today.day + i),
    ];

    return Scaffold(
      appBar: AppBar(title: Text('Reservar con ${s.name.split(' ').first}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _Section(
                title: 'Servicio',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in ServiceType.values.where(s.offers))
                      Pill(
                        elevated: false,
                        label: '${t.label} · ${formatCop(s.services[t]!)}',
                        selected: _service == t,
                        onTap: () => _selectService(t),
                      ),
                  ],
                ),
              ),
              if (_service == ServiceType.walk)
                _Section(
                  title: 'Duración',
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final m in const [30, 60])
                        Pill(
                          elevated: false,
                          label: '$m min',
                          selected: _amount == m,
                          onTap: () => setState(() => _amount = m),
                        ),
                    ],
                  ),
                ),
              if (_service == ServiceType.daycare ||
                  _service == ServiceType.boarding)
                _Section(
                  title: _service == ServiceType.daycare ? 'Días' : 'Noches',
                  child: _Stepper(
                    value: _amount,
                    max: _service == ServiceType.daycare ? 7 : 14,
                    noun: _service == ServiceType.daycare ? 'día' : 'noche',
                    onChanged: (v) => setState(() => _amount = v),
                  ),
                ),
              _Section(
                title: 'Perro',
                child: dogs.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('No pudimos cargar tus perros.'),
                  data: (list) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in list)
                        Pill(
                          elevated: false,
                          label: d.name,
                          selected: _dogId == d.id,
                          onTap: () => setState(() => _dogId = d.id),
                        ),
                      Pill(
                        elevated: false,
                        icon: Icons.add_rounded,
                        label: list.isEmpty
                            ? 'Agregar mi perro'
                            : 'Agregar perro',
                        onTap: _addDog,
                      ),
                    ],
                  ),
                ),
              ),
              _Section(
                title: 'Fecha',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in days)
                      Pill(
                        elevated: false,
                        label: formatDayChip(d, _today),
                        selected: _day == d,
                        onTap: () => setState(() {
                          _day = d;
                          if (_hour != null && !_hourAvailable(d, _hour!)) {
                            _hour = null;
                          }
                        }),
                      ),
                  ],
                ),
              ),
              if (_day != null)
                _Section(
                  title: 'Hora de inicio',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var h = _firstHour; h <= _lastHour; h++)
                        Pill(
                          elevated: false,
                          label: '$h:00',
                          selected: _hour == h,
                          enabled: _hourAvailable(_day!, h),
                          onTap: () => setState(() => _hour = h),
                        ),
                    ],
                  ),
                ),
              if (_complete)
                _Summary(
                  sitter: s,
                  service: _service!,
                  start: _start!,
                  end: _end!,
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    container: true,
                    liveRegion: true,
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: (_complete && !_busy) ? _confirm : null,
                child: Text(_busy ? 'Enviando…' : 'Confirmar reserva'),
              ),
              if (!_complete)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Elige servicio, perro, fecha y hora para continuar.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({
    required this.sitter,
    required this.service,
    required this.start,
    required this.end,
  });

  final SitterSummary sitter;
  final ServiceType service;
  final DateTime start;
  final DateTime end;

  String _unitsText(int units) {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final price = sitter.services[service]!;
    final units = bookingUnits(service, start, end);
    final total = bookingTotal(service, price, start, end);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            container: true,
            child: Text(
              'Resumen',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${service.label} con ${sitter.name}',
            style: theme.textTheme.titleMedium,
          ),
          Text('Desde: ${formatDateTime(start)}', style: muted),
          Text('Hasta: ${formatDateTime(end)}', style: muted),
          const Divider(height: 24),
          Text('${_unitsText(units)} × ${formatCop(price)}', style: muted),
          const SizedBox(height: 4),
          Text(
            'Total ${formatCop(total)}',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'El pago se acuerda dentro de Doggo. No pagues por fuera de la app.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Confirmed extends StatelessWidget {
  const _Confirmed({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.4, end: 1),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.elasticOut,
                    builder: (_, v, child) =>
                        Transform.scale(scale: v, child: child),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      size: 96,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '¡Solicitud enviada!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${booking.sitterName} recibirá tu solicitud. Te avisaremos cuando responda.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
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
                        const SizedBox(height: 8),
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
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.go(Routes.home),
                    child: const Text('Volver al mapa'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            container: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.max,
    required this.noun,
    required this.onChanged,
  });

  final int value;
  final int max;
  final String noun;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = value == 1 ? '1 $noun' : '$value ${noun}s';
    return Row(
      children: [
        _StepButton(
          label: 'Menos ${noun}s',
          icon: Icons.remove_rounded,
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 110,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        _StepButton(
          label: 'Más ${noun}s',
          icon: Icons.add_rounded,
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
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
