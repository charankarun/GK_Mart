import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/repository_exception.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/cart_repository.dart';
import '../mappers/firestore_value_parser.dart';

class FirestoreCartRepository implements CartRepository {
  FirestoreCartRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _items(String userId) {
    return _firestore
        .collection(FirestoreCollections.carts)
        .doc(userId)
        .collection(FirestoreCollections.cartItems);
  }

  @override
  Stream<List<CartItem>> watchCart(String userId) {
    final normalizedUserId = _normalizeId(userId, 'userId');
    return RepositoryGuard.watch(
      message: 'Unable to load cart.',
      create: () {
        return _items(normalizedUserId).snapshots().map((snapshot) {
          return snapshot.docs.map(_fromDocument).toList();
        });
      },
    );
  }

  @override
  Future<void> addProduct({
    required String userId,
    required Product product,
  }) {
    final normalizedUserId = _normalizeId(userId, 'userId');
    final normalizedProductId = _normalizeId(product.id, 'product.id');
    return RepositoryGuard.run(
      message: 'Unable to update cart.',
      action: () {
        return _items(normalizedUserId).doc(normalizedProductId).set({
          'name': product.name,
          'price': product.price,
          'discountPrice': product.discountPrice,
          'unit': product.unit,
          'image': product.imageUrl,
          'quantity': FieldValue.increment(1),
        }, SetOptions(merge: true)).timeout(AppDurations.networkTimeout);
      },
    );
  }

  @override
  Future<void> setQuantity({
    required String userId,
    required CartItem item,
    required int quantity,
  }) {
    if (quantity <= 0) {
      return removeItem(userId: userId, productId: item.productId);
    }

    final normalizedUserId = _normalizeId(userId, 'userId');
    final normalizedProductId = _normalizeId(item.productId, 'item.productId');
    return RepositoryGuard.run(
      message: 'Unable to update cart.',
      action: () {
        return _items(normalizedUserId).doc(normalizedProductId).set({
          'name': item.name,
          'price': item.price,
          'discountPrice': item.discountPrice,
          'unit': item.unit,
          'image': item.imageUrl,
          'quantity': quantity,
        }, SetOptions(merge: true)).timeout(AppDurations.networkTimeout);
      },
    );
  }

  @override
  Future<void> incrementItem({
    required String userId,
    required String productId,
  }) {
    final normalizedUserId = _normalizeId(userId, 'userId');
    final normalizedProductId = _normalizeId(productId, 'productId');
    return RepositoryGuard.run(
      message: 'Unable to update cart.',
      action: () {
        return _items(normalizedUserId).doc(normalizedProductId).set({
          'quantity': FieldValue.increment(1),
        }, SetOptions(merge: true)).timeout(AppDurations.networkTimeout);
      },
    );
  }

  @override
  Future<void> decrementItem({
    required String userId,
    required String productId,
  }) async {
    final normalizedUserId = _normalizeId(userId, 'userId');
    final normalizedProductId = _normalizeId(productId, 'productId');

    return RepositoryGuard.run(
      message: 'Unable to update cart.',
      action: () async {
        final doc = await _items(normalizedUserId)
            .doc(normalizedProductId)
            .get()
            .timeout(
              AppDurations.networkTimeout,
            );
        final quantity = readInt(doc.data()?['quantity']);

        if (!doc.exists || quantity <= 1) {
          await removeItem(
              userId: normalizedUserId, productId: normalizedProductId);
          return;
        }

        await doc.reference.update({
          'quantity': FieldValue.increment(-1),
        }).timeout(AppDurations.networkTimeout);
      },
    );
  }

  @override
  Future<void> removeItem({
    required String userId,
    required String productId,
  }) {
    final normalizedUserId = _normalizeId(userId, 'userId');
    final normalizedProductId = _normalizeId(productId, 'productId');
    return RepositoryGuard.run(
      message: 'Unable to remove cart item.',
      action: () {
        return _items(normalizedUserId)
            .doc(normalizedProductId)
            .delete()
            .timeout(
              AppDurations.networkTimeout,
            );
      },
    );
  }

  @override
  Future<void> clearCart(String userId) async {
    final normalizedUserId = _normalizeId(userId, 'userId');

    return RepositoryGuard.run(
      message: 'Unable to clear cart.',
      action: () async {
        final snapshot = await _items(normalizedUserId).get().timeout(
              AppDurations.networkTimeout,
            );
        final batch = _firestore.batch();

        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit().timeout(AppDurations.networkTimeout);
      },
    );
  }

  CartItem _fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};

    return CartItem(
      productId: doc.id,
      name: readString(data, 'name', fallback: 'Product'),
      price: readDouble(data['price']),
      discountPrice: readDouble(data['discountPrice']),
      quantity: readInt(data['quantity']),
      unit: readString(data, 'unit'),
      imageUrl: readString(data, 'image'),
    );
  }

  static String _normalizeId(String value, String name) {
    final normalizedValue = value.trim();
    if (normalizedValue.isEmpty) {
      throw ArgumentError.value(value, name, 'Required');
    }

    return normalizedValue;
  }
}
