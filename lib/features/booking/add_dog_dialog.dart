import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/dog.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../../shared/widgets/pill.dart';
import '../sitter_profile/sitter_providers.dart';

/// Registro rápido de un perro desde la reserva. Devuelve el perro creado.
Future<Dog?> showAddDogDialog(BuildContext context) =>
    showDialog<Dog>(context: context, builder: (_) => const _AddDogDialog());

class _AddDogDialog extends ConsumerStatefulWidget {
  const _AddDogDialog();

  @override
  ConsumerState<_AddDogDialog> createState() => _AddDogDialogState();
}

class _AddDogDialogState extends ConsumerState<_AddDogDialog> {
  final _name = TextEditingController();
  final _breed = TextEditingController();
  DogSize _size = DogSize.medium;
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dog = await ref
          .read(repositoryProvider)
          .addDog(name: _name.text, breed: _breed.text, size: _size);
      ref.invalidate(myDogsProvider);
      if (mounted) Navigator.of(context).pop(dog);
    } on ValidationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar perro'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre del perro'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _breed,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Raza (opcional)'),
            ),
            const SizedBox(height: 16),
            Text('Tamaño', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in DogSize.values)
                  Pill(
                    elevated: false,
                    label: s.label,
                    selected: _size == s,
                    onTap: () => setState(() => _size = s),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _busy ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
