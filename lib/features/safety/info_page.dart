import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Página de texto informativo (seguridad, términos, privacidad).
class InfoPage extends StatelessWidget {
  const InfoPage({
    super.key,
    required this.title,
    required this.sections,
    this.intro,
    this.footnote,
  });

  final String title;
  final String? intro;
  final List<(String, List<String>)> sections;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              if (intro != null) ...[
                Text(intro!, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 16),
              ],
              for (final (heading, items) in sections)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
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
                          heading,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final item in items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Semantics(
                            container: true,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 6, right: 10),
                                  child: Icon(
                                    Icons.circle,
                                    size: 7,
                                    color: AppColors.primary,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    item,
                                    style: theme.textTheme.bodyLarge,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (footnote != null)
                Text(
                  footnote!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
