import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/repository_exception.dart';
import '../../domain/entities/store_config.dart';
import '../../domain/repositories/store_repository.dart';

class FirestoreStoreRepository implements StoreRepository {
  FirestoreStoreRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _configDoc {
    return _firestore.collection('store_settings').doc('config');
  }

  @override
  Stream<StoreConfig> watchStoreConfig() {
    return RepositoryGuard.watch(
      message: 'Unable to load store settings.',
      create: () => _configDoc.snapshots().map(_fromDocument),
    );
  }

  @override
  Future<StoreConfig> getStoreConfig() async {
    return RepositoryGuard.run(
      message: 'Unable to load store settings.',
      action: () async {
        final doc = await _configDoc.get().timeout(AppDurations.networkTimeout);
        return _fromDocument(doc);
      },
    );
  }

  @override
  Future<void> updateStoreConfig(StoreConfig config) {
    return RepositoryGuard.run(
      message: 'Unable to save store settings.',
      action: () async {
        await _configDoc.set({
          'storeEnabled': config.storeEnabled,
          'openHour': config.openHour,
          'openMinute': config.openMinute,
          'closeHour': config.closeHour,
          'closeMinute': config.closeMinute,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(AppDurations.networkTimeout);
      },
    );
  }

  StoreConfig _fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (!doc.exists || data == null) {
      // Default fallback settings: Enabled, 6:00 AM to 10:00 PM
      return const StoreConfig(
        storeEnabled: true,
        openHour: 6,
        openMinute: 0,
        closeHour: 22,
        closeMinute: 0,
      );
    }

    final updatedAtVal = data['updatedAt'];
    DateTime? updatedAt;
    if (updatedAtVal is Timestamp) {
      updatedAt = updatedAtVal.toDate();
    } else if (updatedAtVal is String) {
      updatedAt = DateTime.tryParse(updatedAtVal);
    }

    return StoreConfig(
      storeEnabled: data['storeEnabled'] as bool? ?? false,
      openHour: data['openHour'] as int? ?? 6,
      openMinute: data['openMinute'] as int? ?? 0,
      closeHour: data['closeHour'] as int? ?? 22,
      closeMinute: data['closeMinute'] as int? ?? 0,
      updatedAt: updatedAt,
    );
  }
}
