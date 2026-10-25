import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/dog.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../sitter_profile/sitter_providers.dart';
import 'dog_form_dialog.dart';

/// Mis perros: lista con agregar, editar y borrar.
class DogsTab extends ConsumerWidget {
  const DogsTab({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref, Dog dog) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Borrar a ${dog.name}?'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Volver'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sí, borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).deleteDog(dog.id);
      ref.invalidate(myDogsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('${dog.name} fue borrado')),
      );
    } on ValidationFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dogs = ref.watch(myDogsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                container: true,
                child: Text(
                  'Mis perros',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => showDogForm(context),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar perro'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        dogs.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const Text('No pudimos cargar tus perros.'),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.pets_rounded,
                        size: 56,
                        color: AppColors.muted,
                      ),
                      const SizedBox(height: 12),
                      Semantics(
                        container: true,
                        child: Text(
                          'Aún no registras perros.',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (final d in list)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                          boxShadow: AppTheme.softShadow,
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 24,
                              backgroundColor: AppColors.background,
                              child: Icon(
                                Icons.pets_rounded,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Semantics(
                                container: true,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.name,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                    Text(
                                      [
                                        if (d.breed != null) d.breed!,
                                        d.size.label,
                                      ].join(' · '),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(color: AppColors.muted),
                                    ),
                                    if (d.notes != null)
                                      Text(
                                        'Notas: ${d.notes}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Editar a ${d.name}',
                              onPressed: () => showDogForm(context, dog: d),
                              icon: const Icon(Icons.edit_rounded),
                            ),
                            IconButton(
                              tooltip: 'Borrar a ${d.name}',
                              onPressed: () => _delete(context, ref, d),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
