import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/store_config.dart';
import 'repository_providers.dart';

final storeConfigProvider = StreamProvider<StoreConfig>((ref) {
  return ref.watch(storeRepositoryProvider).watchStoreConfig();
});

final storeConfigUpdateControllerProvider =
    NotifierProvider<StoreConfigUpdateController, AsyncValue<void>>(() {
  return StoreConfigUpdateController();
});

class StoreConfigUpdateController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() {
    return const AsyncData(null);
  }

  Future<void> updateConfig(StoreConfig config) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(storeRepositoryProvider).updateStoreConfig(config);
      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}
