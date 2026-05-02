import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

final adminModeProvider = NotifierProvider<AdminModeController, bool>(
  AdminModeController.new,
);

class AdminModeController extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool value) {
    state = value;
  }

  void disable() {
    state = false;
  }
}

final effectiveAdminModeProvider = Provider<bool>((ref) {
  final isAdmin = ref.watch(isAdminProvider).maybeWhen(
        data: (value) => value,
        orElse: () => false,
      );

  return isAdmin && ref.watch(adminModeProvider);
});
