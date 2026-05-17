import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/repository_exception.dart';
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

  static const _collectionPath = FirestoreCollections.products;
  static const _storagePath = FirebaseStoragePaths.productImages;
  static const _defaultWatchLimit = 40;
  static const _maxPageLimit = 60;
  static const _whereInLimit = 10;
  static const _maxUploadBytes = 1536 * 1024;
  static const _imageCacheControl = 'public,max-age=31536000,immutable';
  static const _allowedImageContentTypes = {
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
  };
  static const _prefixSearchTerminator = '\uf8ff';
  static final Map<String, Product> _productCache = <String, Product>{};

  CollectionReference<Map<String, dynamic>> get _products {
    return _firestore.collection(_collectionPath);
  }

  @override
  Stream<List<Product>> watchProducts({int limit = _defaultWatchLimit}) {
    final safeLimit = _safeLimit(limit);
    if (safeLimit <= 0) return Stream.value(const <Product>[]);

    return RepositoryGuard.watch(
      message: 'Unable to load products.',
      create: () async* {
        final cachedProducts = _cachedProducts(limit: safeLimit);
        if (cachedProducts.isNotEmpty) yield cachedProducts;

        yield* _products
            .orderBy(ProductField.name)
            .limit(safeLimit)
            .snapshots()
            .map((snapshot) {
          final products =
              snapshot.docs.map(ProductModel.fromFirestore).toList();
          _cacheProducts(products);
          return products;
        });
      },
    );
  }

  @override
  Stream<List<Product>> watchProductsByIds(List<String> productIds) {
    final ids = _normalizeProductIds(productIds);
    if (ids.isEmpty) return Stream.value(const <Product>[]);

    return RepositoryGuard.watch(
      message: 'Unable to load products.',
      create: () {
        final idChunks = _chunks(ids, _whereInLimit).toList();
        late StreamController<List<Product>> controller;
        final chunkProducts = <int, Map<String, Product>>{};
        final loadedChunks = <int>{};
        final subscriptions =
            <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

        void emitProductsIfReady() {
          if (loadedChunks.length < idChunks.length || controller.isClosed) {
            return;
          }

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
            final cachedProducts = [
              for (final id in ids)
                if (_productCache[id] != null) _productCache[id]!,
            ];
            if (cachedProducts.isNotEmpty) controller.add(cachedProducts);

            for (var index = 0; index < idChunks.length; index += 1) {
              final chunkIndex = index;
              final idChunk = idChunks[index];
              final subscription = _products
                  .where(FieldPath.documentId, whereIn: idChunk)
                  .snapshots()
                  .listen(
                (snapshot) {
                  final products = {
                    for (final doc in snapshot.docs)
                      doc.id: ProductModel.fromFirestore(doc),
                  };
                  chunkProducts[chunkIndex] = products;
                  _cacheProducts(products.values);
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
      },
    );
  }

  @override
  Future<ProductPage> fetchProductsPage({
    required int limit,
    ProductPageCursor? cursor,
  }) async {
    return RepositoryGuard.run(
      message: 'Unable to load products.',
      action: () async {
        final safeLimit = _safeLimit(limit);
        if (safeLimit <= 0) {
          return const ProductPage(products: <Product>[], hasMore: false);
        }

        Query<Map<String, dynamic>> query =
            _products.orderBy(ProductField.name).limit(safeLimit);

        query = await _startAfterProductCursor(
          query: query,
          cursor: cursor,
          fallbackValue: cursor?.name,
        );

        final snapshot = await query.get().timeout(AppDurations.networkTimeout);
        return _pageFromSnapshot(snapshot, safeLimit);
      },
    );
  }

  @override
  Future<ProductPage> fetchProductsByCategoryPage({
    required String categoryId,
    String? categoryName,
    required int limit,
    ProductPageCursor? cursor,
  }) {
    return RepositoryGuard.run(
      message: 'Unable to load category products.',
      action: () async {
        final safeLimit = _safeLimit(limit);
        final categoryValues = _categoryQueryValues(
          categoryId: categoryId,
          categoryName: categoryName,
        );
        if (safeLimit <= 0 || categoryValues.isEmpty) {
          return const ProductPage(products: <Product>[], hasMore: false);
        }

        Query<Map<String, dynamic>> query = categoryValues.length == 1
            ? _products.where(
                ProductField.categoryId,
                isEqualTo: categoryValues.first,
              )
            : _products.where(
                ProductField.categoryId,
                whereIn: categoryValues,
              );
        query = query.orderBy(ProductField.name).limit(safeLimit);
        query = await _startAfterProductCursor(
          query: query,
          cursor: cursor,
          fallbackValue: cursor?.name,
        );

        final snapshot = await query.get().timeout(AppDurations.networkTimeout);
        return _pageFromSnapshot(snapshot, safeLimit);
      },
    );
  }

  @override
  Future<ProductPage> fetchProductSearchPage({
    required String query,
    required int limit,
    ProductPageCursor? cursor,
  }) {
    return RepositoryGuard.run(
      message: 'Unable to load search results.',
      action: () async {
        final safeLimit = _safeLimit(limit);
        final normalizedQuery = query.trim().toLowerCase();
        if (safeLimit <= 0 || normalizedQuery.isEmpty) {
          return const ProductPage(products: <Product>[], hasMore: false);
        }

        Query<Map<String, dynamic>> productQuery = _products
            .where(
              ProductField.searchName,
              isGreaterThanOrEqualTo: normalizedQuery,
            )
            .where(
              ProductField.searchName,
              isLessThanOrEqualTo: '$normalizedQuery$_prefixSearchTerminator',
            )
            .orderBy(ProductField.searchName)
            .limit(safeLimit);
        productQuery = await _startAfterProductCursor(
          query: productQuery,
          cursor: cursor,
          fallbackValue: cursor?.name.toLowerCase(),
        );

        final snapshot =
            await productQuery.get().timeout(AppDurations.networkTimeout);
        return _pageFromSnapshot(snapshot, safeLimit);
      },
    );
  }

  @override
  Future<void> addProduct(Product product) {
    return RepositoryGuard.run(
      message: 'Unable to add product.',
      action: () {
        final model = ProductModel.fromEntity(product);
        return _products
            .add(model.toFirestore(includeCreatedAt: true))
            .timeout(AppDurations.networkTimeout);
      },
    );
  }

  @override
  Future<void> updateProduct(Product product) {
    final productId = product.id.trim();
    if (productId.isEmpty) {
      throw ArgumentError.value(product.id, 'product.id', 'Required');
    }

    return RepositoryGuard.run(
      message: 'Unable to update product.',
      action: () {
        final model = ProductModel.fromEntity(product);
        return _products
            .doc(productId)
            .set(
              model.toFirestore(
                includeCreatedAt: false,
                includeDeletes: true,
              ),
              SetOptions(merge: true),
            )
            .timeout(AppDurations.networkTimeout);
      },
    );
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

    return RepositoryGuard.run(
      message: 'Unable to update stock status.',
      action: () {
        return _products.doc(normalizedProductId).update({
          ProductField.isAvailable: isAvailable,
          ProductField.updatedAt: FieldValue.serverTimestamp(),
        }).timeout(AppDurations.networkTimeout);
      },
    );
  }

  @override
  Future<String> uploadProductImage(ProductImageUpload upload) async {
    if (upload.bytes.isEmpty) {
      throw ArgumentError.value(upload.bytes, 'upload.bytes', 'Required');
    }
    if (upload.bytes.lengthInBytes > _maxUploadBytes) {
      throw ArgumentError.value(
        upload.bytes.lengthInBytes,
        'upload.bytes.lengthInBytes',
        'Product image is too large',
      );
    }
    if (!_isAllowedImageContentType(upload.contentType)) {
      throw ArgumentError.value(
        upload.contentType,
        'upload.contentType',
        'Unsupported image type',
      );
    }

    return RepositoryGuard.run(
      message: 'Unable to upload product image.',
      action: () async {
        final fileName = _safeFileName(upload.fileName);
        final ref = _storage.ref().child(
              '$_storagePath/${DateTime.now().millisecondsSinceEpoch}_$fileName',
            );
        final task = await ref
            .putData(
              upload.bytes,
              SettableMetadata(
                contentType: upload.contentType,
                cacheControl: _imageCacheControl,
              ),
            )
            .timeout(AppDurations.uploadTimeout);

        return task.ref.getDownloadURL().timeout(AppDurations.networkTimeout);
      },
    );
  }

  @override
  Future<void> deleteProduct(String productId) {
    final normalizedProductId = productId.trim();
    if (normalizedProductId.isEmpty) {
      throw ArgumentError.value(productId, 'productId', 'Required');
    }

    return RepositoryGuard.run(
      message: 'Unable to delete product.',
      action: () {
        return _products.doc(normalizedProductId).delete().timeout(
              AppDurations.networkTimeout,
            );
      },
    );
  }

  Future<Query<Map<String, dynamic>>> _startAfterProductCursor({
    required Query<Map<String, dynamic>> query,
    required ProductPageCursor? cursor,
    String? fallbackValue,
  }) async {
    if (cursor == null) return query;

    final cursorDoc = await _products.doc(cursor.id).get().timeout(
          AppDurations.networkTimeout,
        );
    if (cursorDoc.exists) return query.startAfterDocument(cursorDoc);

    final value = fallbackValue?.trim();
    if (value == null || value.isEmpty) return query;
    return query.startAfter([value]);
  }

  ProductPage _pageFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    int limit,
  ) {
    final products = snapshot.docs.map(ProductModel.fromFirestore).toList();
    _cacheProducts(products);

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

  static int _safeLimit(int limit) {
    if (limit <= 0) return 0;
    return limit > _maxPageLimit ? _maxPageLimit : limit;
  }

  static List<Product> _cachedProducts({required int limit}) {
    final products = _productCache.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return products.take(limit).toList();
  }

  static void _cacheProducts(Iterable<Product> products) {
    for (final product in products) {
      if (product.id.trim().isEmpty) continue;
      _productCache[product.id] = product;
    }
  }

  static List<String> _categoryQueryValues({
    required String categoryId,
    required String? categoryName,
  }) {
    final values = <String>[];
    final seenValues = <String>{};

    for (final value in [categoryId, categoryName]) {
      final normalizedValue = value?.trim();
      if (normalizedValue == null || normalizedValue.isEmpty) continue;
      if (seenValues.contains(normalizedValue)) continue;
      values.add(normalizedValue);
      seenValues.add(normalizedValue);
    }

    return values;
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

  static bool _isAllowedImageContentType(String contentType) {
    return _allowedImageContentTypes.contains(contentType.trim().toLowerCase());
  }
}
