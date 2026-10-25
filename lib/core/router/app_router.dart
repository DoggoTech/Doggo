import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/onboarding_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/sitter_profile/sitter_profile_screen.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Avisa al router cada vez que cambia la sesión para re-evaluar `redirect`.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final profile = ref.read(authStateProvider).value;
      final signedIn = profile != null;
      final path = state.matchedLocation;
      final isGuestRoute = path == Routes.login || path == Routes.register;
      final isPublic =
          isGuestRoute || path == Routes.splash || path == Routes.onboarding;
      if (!signedIn && !isPublic) return Routes.login;
      if (signedIn && isGuestRoute) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        pageBuilder: (context, state) => _fade(state, const OnboardingScreen()),
      ),
      GoRoute(
        path: Routes.login,
        pageBuilder: (context, state) => _fade(state, const LoginScreen()),
      ),
      GoRoute(
        path: Routes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: Routes.home,
        pageBuilder: (context, state) => _fade(state, const HomeScreen()),
      ),
      GoRoute(
        path: '/sitter/:id',
        builder: (context, state) =>
            SitterProfileScreen(sitterId: state.pathParameters['id']!),
      ),
    ],
  );
});

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondary, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}
