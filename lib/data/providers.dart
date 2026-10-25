import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'demo/demo_repository.dart';
import 'models/profile.dart';
import 'repositories/repository.dart';

/// Por ahora siempre es el modo demo; la fase de Supabase añade el real.
final repositoryProvider = Provider<Repository>((ref) => DemoRepository());

final authStateProvider = StreamProvider<Profile?>((ref) {
  return ref.watch(repositoryProvider).authChanges();
});
