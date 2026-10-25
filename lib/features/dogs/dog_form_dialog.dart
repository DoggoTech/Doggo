import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/dog.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../../shared/widgets/pill.dart';
import '../sitter_profile/sitter_providers.dart';

/// Crear (o editar, si se pasa [dog]) un perro. Devuelve el perro guardado.
Future<Dog?> showDogForm(BuildContext context, {Dog? dog}) => showDialog<Dog>(
  context: context,
  builder: (_) => _DogFormDialog(dog: dog),
);

class _DogFormDialog extends ConsumerStatefulWidget {
  const _DogFormDialog({this.dog});

  final Dog? dog;

  @override
  ConsumerState<_DogFormDialog> createState() => _DogFormDialogState();
}

class _DogFormDialogState extends ConsumerState<_DogFormDialog> {
  late final _name = TextEditingController(text: widget.dog?.name);
  late final _breed = TextEditingController(text: widget.dog?.breed);
  late final _notes = TextEditingController(text: widget.dog?.notes);
  late DogSize _size = widget.dog?.size ?? DogSize.medium;
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(repositoryProvider);
    try {
      final saved = widget.dog == null
          ? await repo.addDog(
              name: _name.text,
              breed: _breed.text,
              size: _size,
              notes: _notes.text,
            )
          : await repo.updateDog(
              Dog(
                id: widget.dog!.id,
                ownerId: widget.dog!.ownerId,
                name: _name.text,
                breed: _breed.text,
                size: _size,
                notes: _notes.text,
              ),
            );
      ref.invalidate(myDogsProvider);
      if (mounted) Navigator.of(context).pop(saved);
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
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.dog == null ? 'Agregar perro' : 'Editar perro'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre del perro',
                ),
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
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Notas médicas o de comportamiento (opcional)',
                  helperText:
                      'Solo las verá el cuidador cuando acepte una reserva.',
                  helperMaxLines: 2,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
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
