import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/availability.dart';
import '../../data/models/service_type.dart';
import '../../data/models/sitter_summary.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../bookings/bookings_providers.dart';
import 'service_area_card.dart';

/// Servicios con precio y horario semanal del cuidador.
class ServicesTab extends ConsumerWidget {
  const ServicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(mySitterProfileProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text('No pudimos cargar tus servicios.')),
          data: (s) => _ServicesEditor(key: ValueKey(s.id), sitter: s),
        );
  }
}

class _ServicesEditor extends ConsumerStatefulWidget {
  const _ServicesEditor({super.key, required this.sitter});

  final SitterSummary sitter;

  @override
  ConsumerState<_ServicesEditor> createState() => _ServicesEditorState();
}

class _ServicesEditorState extends ConsumerState<_ServicesEditor> {
  late final Map<ServiceType, bool> _active = {
    for (final t in ServiceType.values) t: widget.sitter.offers(t),
  };
  late final Map<ServiceType, TextEditingController> _prices = {
    for (final t in ServiceType.values)
      t: TextEditingController(
        text: widget.sitter.services[t]?.toString() ?? '',
      ),
  };
  late WeeklyAvailability _availability = widget.sitter.availability;
  String? _servicesError;
  String? _availabilityError;

  @override
  void dispose() {
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveServices() async {
    setState(() => _servicesError = null);
    final services = <ServiceType, int>{};
    for (final t in ServiceType.values) {
      if (!_active[t]!) continue;
      final price = int.tryParse(_prices[t]!.text.trim());
      if (price == null) {
        setState(() => _servicesError = 'Escribe el precio de ${t.label}.');
        return;
      }
      services[t] = price;
    }
    try {
      await ref.read(repositoryProvider).saveMyServices(services);
      _invalidateSitterData();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Servicios guardados')));
      }
    } on ValidationFailure catch (e) {
      setState(() => _servicesError = e.message);
    }
  }

  Future<void> _saveAvailability() async {
    setState(() => _availabilityError = null);
    try {
      await ref.read(repositoryProvider).saveMyAvailability(_availability);
      _invalidateSitterData();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Horario guardado')));
      }
    } on ValidationFailure catch (e) {
      setState(() => _availabilityError = e.message);
    }
  }

  /// El mapa y los perfiles leen estos datos: que se recarguen.
  void _invalidateSitterData() {
    ref.invalidate(mySitterProfileProvider);
  }

  void _setWindow(int weekday, DayWindow? w) =>
      setState(() => _availability = _availability.withDay(weekday, w));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        if (!widget.sitter.locationConfirmed)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Semantics(
              container: true,
              child: Text(
                'Aún no defines tu zona: no saldrás en el mapa hasta hacerlo. Está al final de esta página.',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        Semantics(
          header: true,
          container: true,
          child: Text(
            'Servicios y precios',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          children: [
            for (final t in ServiceType.values) _serviceRow(t),
            if (_servicesError != null) _ErrorText(_servicesError!),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saveServices,
              child: const Text('Guardar servicios'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          container: true,
          child: Text(
            'Horario de atención',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Horas en las que puedes empezar un servicio. Los dueños solo verán estas horas.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        _Card(
          children: [
            for (var d = 1; d <= 7; d++) _dayRow(d),
            if (_availabilityError != null) _ErrorText(_availabilityError!),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saveAvailability,
              child: const Text('Guardar horario'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          container: true,
          child: Text(
            'Zona de servicio',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ServiceAreaCard(sitter: widget.sitter),
      ],
    );
  }

  Widget _serviceRow(ServiceType t) {
    final theme = Theme.of(context);
    final on = _active[t]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Semantics(
            container: true,
            label: 'Ofrecer ${t.label}',
            toggled: on,
            onTap: () => setState(() => _active[t] = !on),
            excludeSemantics: true,
            child: Switch(
              value: on,
              onChanged: (v) => setState(() => _active[t] = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(t.label, style: theme.textTheme.titleSmall)),
          SizedBox(
            width: 130,
            child: TextField(
              controller: _prices[t],
              enabled: on,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Precio de ${t.label}',
                prefixText: '\$ ',
                isDense: true,
                helperText: t.unit,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayRow(int weekday) {
    final theme = Theme.of(context);
    final name = weekdayNames[weekday - 1];
    final w = _availability.days[weekday];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                container: true,
                label: 'Atiende el ${name.toLowerCase()}',
                toggled: w != null,
                onTap: () => _setWindow(
                  weekday,
                  w == null ? const DayWindow(420, 1140) : null,
                ),
                excludeSemantics: true,
                child: Switch(
                  value: w != null,
                  onChanged: (v) => _setWindow(
                    weekday,
                    v ? const DayWindow(420, 1140) : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (w == null) ...[
                const Spacer(),
                Text(
                  'No atiende',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
          if (w != null)
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _TimeStepper(
                  title: '$name desde',
                  minute: w.startMinute,
                  earlier: w.startMinute > 0
                      ? () => _setWindow(
                          weekday,
                          DayWindow(w.startMinute - 30, w.endMinute),
                        )
                      : null,
                  later: w.startMinute + 30 <= w.endMinute
                      ? () => _setWindow(
                          weekday,
                          DayWindow(w.startMinute + 30, w.endMinute),
                        )
                      : null,
                ),
                _TimeStepper(
                  title: '$name hasta',
                  minute: w.endMinute,
                  earlier: w.endMinute - 30 >= w.startMinute
                      ? () => _setWindow(
                          weekday,
                          DayWindow(w.startMinute, w.endMinute - 30),
                        )
                      : null,
                  later: w.endMinute + 30 <= 23 * 60 + 30
                      ? () => _setWindow(
                          weekday,
                          DayWindow(w.startMinute, w.endMinute + 30),
                        )
                      : null,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// "Lunes desde  [−] 7:00 [+]"
class _TimeStepper extends StatelessWidget {
  const _TimeStepper({
    required this.title,
    required this.minute,
    required this.earlier,
    required this.later,
  });

  final String title;
  final int minute;
  final VoidCallback? earlier;
  final VoidCallback? later;

  @override
  Widget build(BuildContext context) {
    final label = title.split(' ').last; // "desde" / "hasta"
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        _MiniButton(
          label: '$title: más temprano',
          icon: Icons.remove_rounded,
          onPressed: earlier,
        ),
        Semantics(
          container: true,
          label: '$title: ${formatMinuteOfDay(minute)}',
          excludeSemantics: true,
          child: SizedBox(
            width: 52,
            child: Text(
              formatMinuteOfDay(minute),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        _MiniButton(
          label: '$title: más tarde',
          icon: Icons.add_rounded,
          onPressed: later,
        ),
      ],
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onPressed != null,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      boxShadow: AppTheme.softShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Semantics(
      container: true,
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
