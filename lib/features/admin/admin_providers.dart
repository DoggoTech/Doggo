import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/admin.dart';
import '../../data/models/profile.dart';
import '../../data/models/report.dart';
import '../../data/providers.dart';

final pendingSittersProvider = FutureProvider.autoDispose<List<PendingSitter>>(
  (ref) => ref.watch(repositoryProvider).fetchPendingSitters(),
);

/// Casos propios que esperan reunión (insignia de la pestaña Aprobaciones).
final myNewCasesProvider = StreamProvider.autoDispose<int>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(repositoryProvider).watchMyNewCases();
});

/// Admins que pueden llevar casos (para que el superadmin reasigne).
final caseHandlersProvider = FutureProvider.autoDispose<List<AdminUserRow>>(
  (ref) => ref.watch(repositoryProvider).fetchCaseHandlers(),
);

final reportsProvider = FutureProvider.autoDispose<List<Report>>(
  (ref) => ref.watch(repositoryProvider).fetchReports(),
);

typedef UserSearch = ({String query, UserRole? role, UserStatus? status});

final userSearchProvider = FutureProvider.autoDispose
    .family<List<AdminUserRow>, UserSearch>(
      (ref, q) => ref
          .watch(repositoryProvider)
          .searchUsers(query: q.query, role: q.role, status: q.status),
    );

final adminActionsProvider = FutureProvider.autoDispose<List<AdminAction>>(
  (ref) => ref.watch(repositoryProvider).fetchAdminActions(),
);

/// Tras una acción de moderación, todo lo que depende de ella se recarga.
void refreshAdminData(WidgetRef ref) {
  ref.invalidate(pendingSittersProvider);
  ref.invalidate(reportsProvider);
  ref.invalidate(userSearchProvider);
  ref.invalidate(adminActionsProvider);
}
