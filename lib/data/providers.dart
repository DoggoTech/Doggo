import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import 'demo/demo_repository.dart';
import 'models/profile.dart';
import 'repositories/repository.dart';
import 'supabase/supabase_repository.dart';

/// Real: Supabase (cuentas y datos compartidos). Demo: datos de ejemplo en
/// memoria, solo en este navegador.
enum AppMode { live, demo }

/// Arranca en real si hay claves de Supabase. "Probar demo" pasa a demo y
/// "Cerrar sesión" vuelve al modo de arranque.
class AppModeNotifier extends Notifier<AppMode> {
  @override
  AppMode build() => supabaseConfigured ? AppMode.live : AppMode.demo;

  void useDemo() => state = AppMode.demo;

  void reset() => state = build();
}

final appModeProvider = NotifierProvider<AppModeNotifier, AppMode>(
  AppModeNotifier.new,
);

/// Una sola demo por sesión del navegador: lo que se hace en ella dura hasta
/// recargar la página, aunque se salga y se vuelva a entrar.
final demoRepositoryProvider = Provider<DemoRepository>(
  (ref) => DemoRepository(),
);

final supabaseRepositoryProvider = Provider<SupabaseRepository>(
  (ref) => SupabaseRepository(),
);

final repositoryProvider = Provider<Repository>(
  (ref) => switch (ref.watch(appModeProvider)) {
    AppMode.live => ref.watch(supabaseRepositoryProvider),
    AppMode.demo => ref.watch(demoRepositoryProvider),
  },
);

final authStateProvider = StreamProvider<Profile?>((ref) {
  return ref.watch(repositoryProvider).authChanges();
});

/// Cierra la sesión y, si estaba en la demo, vuelve al modo real.
Future<void> signOutAndReset(WidgetRef ref) async {
  await ref.read(repositoryProvider).signOut();
  ref.read(appModeProvider.notifier).reset();
}
