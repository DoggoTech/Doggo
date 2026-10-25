import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/contact_info.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../bookings/bookings_providers.dart';

/// Teléfono y dirección propios: privados hasta que una reserva se acepta.
class PrivateDataCard extends ConsumerWidget {
  const PrivateDataCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(myPrivateDataProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const SizedBox.shrink(),
          data: (d) => _Form(key: ValueKey('${d.phone}|${d.address}'), data: d),
        );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({super.key, required this.data});

  final PrivateData data;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final _phone = TextEditingController(text: widget.data.phone);
  late final _address = TextEditingController(text: widget.data.address);
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    try {
      await ref
          .read(repositoryProvider)
          .saveMyPrivateData(
            PrivateData(phone: _phone.text, address: _address.text),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos de contacto guardados')),
        );
      }
    } on ValidationFailure catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mis datos de contacto', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Son privados: solo los verá la otra persona cuando una reserva esté aceptada.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Dirección'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _save,
            child: const Text('Guardar contacto'),
          ),
        ],
      ),
    );
  }
}
