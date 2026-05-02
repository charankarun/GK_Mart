import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../domain/entities/product.dart';
import '../../domain/entities/product_image_upload.dart';
import '../../domain/entities/product_page.dart';
import '../../domain/repositories/product_repository.dart';
import '../models/product_model.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
  })  : _firestore = firestore,
        _storage = storage;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  static const _collectionPath = 'products';
  static const _storagePath = 'product_images';
  static const _whereInLimit = 10;

  CollectionReference<Map<String, dynamic>> get _products {
    return _firestore.collection(_collectionPath);
  }

  @override
  Stream<List<Product>> watchProducts() {
    return _products.snapshots().map((snapshot) {
      final products = snapshot.docs.map(ProductModel.fromFirestore).toList();
      products.sort((a, b) => a.name.compareTo(b.name));
      return products;
    });
  }

  @override
  Stream<List<Product>> watchProductsByIds(List<String> productIds) {
    final ids = _normalizeProductIds(productIds);
    if (ids.isEmpty) return Stream.value(const <Product>[]);

    final idChunks = _chunks(ids, _whereInLimit).toList();
    late StreamController<List<Product>> controller;
    final chunkProducts = <int, Map<String, Product>>{};
    final loadedChunks = <int>{};
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    void emitProductsIfReady() {
      if (loadedChunks.length < idChunks.length || controller.isClosed) return;

      final productsById = <String, Product>{};
      for (final products in chunkProducts.values) {
        productsById.addAll(products);
      }

      controller.add([
        for (final id in ids)
          if (productsById[id] != null) productsById[id]!,
      ]);
    }

    controller = StreamController<List<Product>>(
      onListen: () {
        for (var index = 0; index < idChunks.length; index += 1) {
          final chunkIndex = index;
          final idChunk = idChunks[index];
          final subscription = _products
              .where(FieldPath.documentId, whereIn: idChunk)
              .snapshots()
              .listen(
            (snapshot) {
              chunkProducts[chunkIndex] = {
                for (final doc in snapshot.docs)
                  doc.id: ProductModel.fromFirestore(doc),
              };
              loadedChunks.add(chunkIndex);
              emitProductsIfReady();
            },
            onError: controller.addError,
          );

          subscriptions.add(subscription);
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );

    return controller.stream;
  }

  @override
  Future<ProductPage> fetchProductsPage({
    required int limit,
    ProductPageCursor? cursor,
  }) async {
    if (limit <= 0) {
      return const ProductPage(products: <Product>[], hasMore: false);
    }

    Query<Map<String, dynamic>> query =
        _products.orderBy(ProductField.name).limit(limit);

    if (cursor != null) {
      final cursorDoc = await _products.doc(cursor.id).get();
      query = cursorDoc.exists
          ? query.startAfterDocument(cursorDoc)
          : query.startAfter([cursor.name]);
    }

    final snapshot = await query.get();
    final products = snapshot.docs.map(ProductModel.fromFirestore).toList();

    ProductPageCursor? nextCursor;
    if (products.isNotEmpty) {
      final lastProduct = products.last;
      nextCursor = ProductPageCursor(
        id: lastProduct.id,
        name: lastProduct.name,
      );
    }

    return ProductPage(
      products: products,
      nextCursor: nextCursor,
      hasMore: snapshot.docs.length == limit,
    );
  }

  @override
  Future<void> addProduct(Product product) {
    final model = ProductModel.fromEntity(product);
    return _products.add(model.toFirestore(includeCreatedAt: true));
  }

  @override
  Future<void> updateProduct(Product product) {
    final productId = product.id.trim();
    if (productId.isEmpty) {
      throw ArgumentError.value(product.id, 'product.id', 'Required');
    }

    final model = ProductModel.fromEntity(product);
    return _products.doc(productId).set(
        model.toFirestore(includeCreatedAt: false), SetOptions(merge: true));
  }

  @override
  Future<void> updateProductAvailability({
    required String productId,
    required bool isAvailable,
  }) {
    final normalizedProductId = productId.trim();
    if (normalizedProductId.isEmpty) {
      throw ArgumentError.value(productId, 'productId', 'Required');
    }

    return _products.doc(normalizedProductId).update({
      ProductField.isAvailable: isAvailable,
      ProductField.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<String> uploadProductImage(ProductImageUpload upload) async {
    if (upload.bytes.isEmpty) {
      throw ArgumentError.value(upload.bytes, 'upload.bytes', 'Required');
    }

    final fileName = _safeFileName(upload.fileName);
    final ref = _storage.ref().child(
          '$_storagePath/${DateTime.now().millisecondsSinceEpoch}_$fileName',
        );
    final task = await ref.putData(
      upload.bytes,
      SettableMetadata(contentType: upload.contentType),
    );

    return task.ref.getDownloadURL();
  }

  @override
  Future<void> deleteProduct(String productId) {
    return _products.doc(productId).delete();
  }

  static List<String> _normalizeProductIds(List<String> productIds) {
    final ids = <String>[];
    final seenIds = <String>{};

    for (final productId in productIds) {
      final normalizedProductId = productId.trim();
      if (normalizedProductId.isEmpty ||
          seenIds.contains(normalizedProductId)) {
        continue;
      }

      ids.add(normalizedProductId);
      seenIds.add(normalizedProductId);
    }

    return ids;
  }

  static Iterable<List<String>> _chunks(List<String> values, int size) sync* {
    for (var index = 0; index < values.length; index += size) {
      final end = index + size > values.length ? values.length : index + size;
      yield values.sublist(index, end);
    }
  }

  static String _safeFileName(String fileName) {
    final normalizedFileName = fileName.trim().replaceAll(
          RegExp(r'[^a-zA-Z0-9._-]+'),
          '_',
        );

    if (normalizedFileName.isEmpty) return 'product_image.jpg';
    return normalizedFileName;
  }
}
