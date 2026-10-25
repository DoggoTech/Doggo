import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/prefs.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/doggo_logo.dart';

class _Slide {
  const _Slide(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const _slides = [
  _Slide(
    Icons.map_rounded,
    'Encuentra cuidadores cerca',
    'Mira en el mapa quién cuida perros en tu barrio y compara precios de un vistazo.',
  ),
  _Slide(
    Icons.event_available_rounded,
    'Reserva en un toque',
    'Elige el servicio, tu perro y la fecha. Paseos, guardería, hospedaje y más.',
  ),
  _Slide(
    Icons.bolt_rounded,
    'Sigue tu reserva en vivo',
    'El cuidador responde y tú ves el cambio al instante, sin recargar.',
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  bool get _isLast => _page == _slides.length - 1;

  Future<void> _finish() async {
    await ref.read(sharedPreferencesProvider).setBool(onboardingSeenKey, true);
    if (mounted) context.go(Routes.login);
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _finish,
                      child: const Text('Saltar'),
                    ),
                  ),
                  const DoggoLogo(size: 120),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _slides.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (context, i) {
                        final s = _slides[i];
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                s.icon,
                                size: 48,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              s.title,
                              textAlign: TextAlign.center,
                              style: textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              s.body,
                              textAlign: TextAlign.center,
                              style: textTheme.bodyLarge
                                  ?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Semantics(
                    label: 'Paso ${_page + 1} de ${_slides.length}',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _slides.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _page ? 28 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? AppColors.primary
                                  : AppColors.primary.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _next,
                    child: Text(_isLast ? 'Empezar' : 'Siguiente'),
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
