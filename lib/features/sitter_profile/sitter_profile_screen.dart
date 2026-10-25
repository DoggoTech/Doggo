import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/profile.dart';
import '../../data/models/review.dart';
import '../../data/models/service_type.dart';
import '../../data/models/sitter_summary.dart';
import '../../data/providers.dart';
import '../map/sitter_list.dart';
import 'sitter_providers.dart';

class SitterProfileScreen extends ConsumerWidget {
  const SitterProfileScreen({super.key, required this.sitterId});

  final String sitterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sitter = ref.watch(sitterProvider(sitterId));
    final isOwner = ref.watch(authStateProvider).value?.role == UserRole.owner;
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil del cuidador')),
      body: sitter.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Message(
          text: 'No pudimos cargar este perfil.',
          action: 'Reintentar',
          onAction: () => ref.invalidate(sitterProvider(sitterId)),
        ),
        data: (s) => s == null
            ? const _Message(text: 'Este cuidador ya no está disponible.')
            : _ProfileBody(sitter: s),
      ),
      bottomNavigationBar: (sitter.value != null && isOwner)
          ? SafeArea(
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: FilledButton(
                      onPressed: () => context.push('/sitter/$sitterId/book'),
                      child: const Text('Reservar'),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.sitter});

  final SitterSummary sitter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reviews = ref.watch(reviewsProvider(sitter.id));
    final services = ServiceType.values.where(sitter.offers).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Center(child: SitterAvatar(sitter: sitter, radius: 56)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    sitter.name,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (sitter.verified) ...[
                  const SizedBox(width: 6),
                  const VerifiedBadge(size: 22),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Center(child: RatingText(sitter)),
            Text(
              '${sitter.neighborhood} · atiende a ${sitter.radiusKm} km a la redonda',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 20),
            _Card(
              title: 'Sobre mí',
              child: Text(sitter.bio, style: theme.textTheme.bodyLarge),
            ),
            const SizedBox(height: 14),
            _Card(
              title: 'Servicios',
              child: Column(
                children: [
                  for (final t in services)
                    Semantics(
                      container: true,
                      label:
                          '${t.label}, ${formatCop(sitter.services[t]!)} ${t.unit}',
                      excludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.label,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              formatCop(sitter.services[t]!),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              t.unit,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _Card(
              title: sitter.ratingCount == 0
                  ? 'Reseñas'
                  : 'Reseñas (${sitter.ratingCount})',
              child: reviews.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => const Text('No pudimos cargar las reseñas.'),
                data: (list) => list.isEmpty
                    ? Text(
                        'Aún no tiene reseñas. ¡Sé el primero en reservar!',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                      )
                    : Column(
                        children: [
                          for (final r in list) _ReviewTile(review: r),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label:
          'Reseña de ${review.authorName}, ${review.rating} de 5. ${review.comment ?? ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < 5; i++)
                  Icon(
                    i < review.rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                const SizedBox(width: 8),
                Text(review.authorName, style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  formatDay(review.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
            if (review.comment != null) ...[
              const SizedBox(height: 4),
              Text(review.comment!, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            header: true,
            container: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge
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

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      ),
    );
  }
}
