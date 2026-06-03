import '../entities/store_config.dart';

abstract class StoreRepository {
  Stream<StoreConfig> watchStoreConfig();
  Future<StoreConfig> getStoreConfig();
  Future<void> updateStoreConfig(StoreConfig config);
}
