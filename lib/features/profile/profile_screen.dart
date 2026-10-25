import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/demo/demo_repository.dart';
import '../../data/models/profile.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String? _error;

  Future<void> _switchRole(UserRole role) async {
    setState(() => _error = null);
    try {
      await ref.read(repositoryProvider).switchRole(role);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _demoSwitch(UserRole role) async {
    final repo = ref.read(repositoryProvider);
    await repo.signOut();
    await repo.signIn(
      email: DemoRepository.demoAccountByRole[role]!,
      password: demoPassword,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final repo = ref.watch(repositoryProvider);
    final theme = Theme.of(context);
    final otherRole = p.role == UserRole.owner
        ? UserRole.sitter
        : UserRole.owner;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: CircleAvatar(
            radius: 44,
            backgroundColor: AppColors.primary,
            child: Text(
              p.fullName.isEmpty ? '?' : p.fullName[0].toUpperCase(),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          p.fullName,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          p.email,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Rol: ${p.role.label}',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (p.role.isSelectable) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              boxShadow: AppTheme.softShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Ajustes', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _switchRole(otherRole),
                  child: Text('Cambiar a ${otherRole.label.toLowerCase()}'),
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
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (repo is DemoRepository)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              boxShadow: AppTheme.softShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Modo demo: cambiar de rol',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in DemoRepository.demoAccountByRole.keys)
                      OutlinedButton(
                        onPressed: () => _demoSwitch(r),
                        child: Text('Demo: ${r.label}'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => ref.read(repositoryProvider).signOut(),
          child: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}
