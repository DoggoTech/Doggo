import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../bookings/bookings_providers.dart';

/// Bio pública del cuidador ("Sobre mí" en su perfil).
class BioCard extends ConsumerWidget {
  const BioCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(mySitterProfileProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const SizedBox.shrink(),
          data: (s) => _BioForm(key: ValueKey(s.bio), bio: s.bio),
        );
  }
}

class _BioForm extends ConsumerStatefulWidget {
  const _BioForm({super.key, required this.bio});

  final String bio;

  @override
  ConsumerState<_BioForm> createState() => _BioFormState();
}

class _BioFormState extends ConsumerState<_BioForm> {
  late final _bio = TextEditingController(text: widget.bio);
  String? _error;

  @override
  void dispose() {
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    try {
      await ref.read(repositoryProvider).saveMyBio(_bio.text);
      ref.invalidate(mySitterProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Bio guardada')));
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
          Text('Sobre mí', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'La ven los dueños en tu perfil. Por seguridad no incluyas teléfonos, correos ni enlaces.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bio,
            minLines: 3,
            maxLines: 6,
            maxLength: 600,
            decoration: const InputDecoration(labelText: 'Tu bio'),
          ),
          if (_error != null)
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _save, child: const Text('Guardar bio')),
        ],
      ),
    );
  }
}
