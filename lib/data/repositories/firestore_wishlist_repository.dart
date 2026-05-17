import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/repository_exception.dart';
import '../../domain/repositories/wishlist_repository.dart';

class FirestoreWishlistRepository implements WishlistRepository {
  FirestoreWishlistRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _wishlistDoc(String userId) {
    return _firestore.collection(FirestoreCollections.wishlist).doc(userId);
  }

  @override
  Stream<List<String>> watchWishlistProductIds(String userId) {
    final normalizedUserId = _normalizeUserId(userId);

    return RepositoryGuard.watch(
      message: 'Unable to load wishlist.',
      create: () {
        return _wishlistDoc(normalizedUserId).snapshots().map((snapshot) {
          final data = snapshot.data() ?? const <String, dynamic>{};
          final productIds = data[FirestoreFields.productIds];
          if (productIds is! Iterable) return const <String>[];

          return _normalizeProductIds(productIds);
        });
      },
    );
  }

  @override
  Future<void> addProduct({
    required String userId,
    required String productId,
  }) {
    final normalizedUserId = _normalizeUserId(userId);
    final normalizedProductId = _normalizeProductId(productId);
    return RepositoryGuard.run(
      message: 'Unable to update wishlist.',
      action: () {
        return _wishlistDoc(normalizedUserId).set({
          FirestoreFields.productIds: FieldValue.arrayUnion([
            normalizedProductId,
          ]),
        }, SetOptions(merge: true)).timeout(AppDurations.networkTimeout);
      },
    );
  }

  @override
  Future<void> removeProduct({
    required String userId,
    required String productId,
  }) {
    final normalizedUserId = _normalizeUserId(userId);
    final normalizedProductId = _normalizeProductId(productId);
    return RepositoryGuard.run(
      message: 'Unable to update wishlist.',
      action: () {
        return _wishlistDoc(normalizedUserId).set({
          FirestoreFields.productIds: FieldValue.arrayRemove([
            normalizedProductId,
          ]),
        }, SetOptions(merge: true)).timeout(AppDurations.networkTimeout);
      },
    );
  }

  @override
  Future<void> setWishlisted({
    required String userId,
    required String productId,
    required bool wishlisted,
  }) {
    if (wishlisted) {
      return addProduct(userId: userId, productId: productId);
    }

    return removeProduct(userId: userId, productId: productId);
  }

  static List<String> _normalizeProductIds(Iterable<dynamic> values) {
    final ids = <String>[];
    final seenIds = <String>{};

    for (final value in values) {
      final productId = value.toString().trim();
      if (productId.isEmpty || seenIds.contains(productId)) continue;
      ids.add(productId);
      seenIds.add(productId);
    }

    return ids;
  }

  static String _normalizeProductId(String productId) {
    final normalizedProductId = productId.trim();
    if (normalizedProductId.isEmpty) {
      throw ArgumentError.value(productId, 'productId', 'Required');
    }

    return normalizedProductId;
  }

  static String _normalizeUserId(String userId) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Required');
    }

    return normalizedUserId;
  }
}
