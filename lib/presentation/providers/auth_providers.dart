import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_user.dart';
import '../../domain/entities/auth_session.dart';
import 'repository_providers.dart';

final authStateProvider = StreamProvider<AuthSession?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final currentSessionProvider = Provider<AuthSession?>((ref) {
  return ref.watch(authStateProvider).maybeWhen(
        data: (session) => session,
        orElse: () => null,
      );
});

final currentUserProfileProvider = StreamProvider<AppUser?>((ref) {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return Stream.value(null);

  return ref.watch(userRepositoryProvider).watchUser(session.uid);
});

final isAdminProvider = StreamProvider<bool>((ref) {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return Stream.value(false);

  return ref.watch(adminRepositoryProvider).watchIsAdmin(session);
});

final isCurrentUserAdminProvider = isAdminProvider;
