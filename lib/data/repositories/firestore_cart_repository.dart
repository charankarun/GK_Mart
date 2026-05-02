import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/cart_item.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/cart_repository.dart';
import '../mappers/firestore_value_parser.dart';

class FirestoreCartRepository implements CartRepository {
  FirestoreCartRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _items(String userId) {
    return _firestore.collection('carts').doc(userId).collection('items');
  }

  @override
  Stream<List<CartItem>> watchCart(String userId) {
    return _items(userId).snapshots().map((snapshot) {
      return snapshot.docs.map(_fromDocument).toList();
    });
  }

  @override
  Future<void> addProduct({
    required String userId,
    required Product product,
  }) {
    return _items(userId).doc(product.id).set({
      'name': product.name,
      'price': product.price,
      'discountPrice': product.discountPrice,
      'unit': product.unit,
      'image': product.imageUrl,
      'quantity': FieldValue.increment(1),
    }, SetOptions(merge: true));
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

    return _items(userId).doc(item.productId).set({
      'name': item.name,
      'price': item.price,
      'discountPrice': item.discountPrice,
      'unit': item.unit,
      'image': item.imageUrl,
      'quantity': quantity,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> incrementItem({
    required String userId,
    required String productId,
  }) {
    return _items(userId).doc(productId).set({
      'quantity': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> decrementItem({
    required String userId,
    required String productId,
  }) async {
    final doc = await _items(userId).doc(productId).get();
    final quantity = readInt(doc.data()?['quantity']);

    if (!doc.exists || quantity <= 1) {
      await removeItem(userId: userId, productId: productId);
      return;
    }

    await doc.reference.update({
      'quantity': FieldValue.increment(-1),
    });
  }

  @override
  Future<void> removeItem({
    required String userId,
    required String productId,
  }) {
    return _items(userId).doc(productId).delete();
  }

  @override
  Future<void> clearCart(String userId) async {
    final snapshot = await _items(userId).get();
    final batch = _firestore.batch();

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
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
}
