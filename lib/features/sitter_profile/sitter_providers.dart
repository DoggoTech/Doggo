import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/dog.dart';
import '../../data/models/review.dart';
import '../../data/models/sitter_summary.dart';
import '../../data/providers.dart';

final sitterProvider = FutureProvider.autoDispose
    .family<SitterSummary?, String>(
      (ref, id) => ref.watch(repositoryProvider).fetchSitter(id),
    );

final reviewsProvider = FutureProvider.autoDispose.family<List<Review>, String>(
  (ref, id) => ref.watch(repositoryProvider).fetchReviews(id),
);

/// Perros del dueño con sesión. Se invalida al agregar uno.
final myDogsProvider = FutureProvider.autoDispose<List<Dog>>(
  (ref) => ref.watch(repositoryProvider).fetchMyDogs(),
);
