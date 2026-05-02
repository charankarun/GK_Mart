import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/repositories/wishlist_repository.dart';

class FirestoreWishlistRepository implements WishlistRepository {
  FirestoreWishlistRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _wishlistDoc(String userId) {
    return _firestore.collection('wishlist').doc(userId);
  }

  @override
  Stream<List<String>> watchWishlistProductIds(String userId) {
    return _wishlistDoc(userId).snapshots().map((snapshot) {
      final data = snapshot.data() ?? const <String, dynamic>{};
      final productIds = data['productIds'];
      if (productIds is! Iterable) return const <String>[];

      return _normalizeProductIds(productIds);
    });
  }

  @override
  Future<void> addProduct({
    required String userId,
    required String productId,
  }) {
    final normalizedProductId = _normalizeProductId(productId);
    return _wishlistDoc(userId).set({
      'productIds': FieldValue.arrayUnion([normalizedProductId]),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> removeProduct({
    required String userId,
    required String productId,
  }) {
    final normalizedProductId = _normalizeProductId(productId);
    return _wishlistDoc(userId).set({
      'productIds': FieldValue.arrayRemove([normalizedProductId]),
    }, SetOptions(merge: true));
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
}
