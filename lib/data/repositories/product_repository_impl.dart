import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/repository_exception.dart';
import '../../core/storage/storage_image_uploader.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_image_upload.dart';
import '../../domain/entities/product_page.dart';
import '../../domain/entities/product_stats.dart';
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
  static const _searchSourceTokens = 'tokens';
  static const _searchSourceSearchName = 'searchName';
  static const _searchSourceLegacyNamePrefix = 'legacyName:';
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
  Stream<Product?> watchProduct(String productId) {
    final normalizedProductId = productId.trim();
    if (normalizedProductId.isEmpty) return Stream.value(null);

    return RepositoryGuard.watch(
      message: 'Unable to load product.',
      create: () async* {
        // Yield cached product first if exists
        final cached = _productCache[normalizedProductId];
        if (cached != null) yield cached;

        yield* _products.doc(normalizedProductId).snapshots().map((snapshot) {
          if (!snapshot.exists) return null;
          final product = ProductModel.fromFirestore(snapshot);
          _productCache[product.id] = product;
          return product;
        });
      },
    );
  }

  @override
  Future<List<Product>> fetchProductsByIds(List<String> productIds) {
    final ids = _normalizeProductIds(productIds);
    if (ids.isEmpty) return Future.value(const <Product>[]);

    return RepositoryGuard.run(
      message: 'Unable to load products.',
      action: () async {
        final idChunks = _chunks(ids, _whereInLimit).toList();
        final fetchFutures = idChunks.map((chunk) {
          return _products.where(FieldPath.documentId, whereIn: chunk).get();
        });

        final snapshots = await Future.wait(fetchFutures);
        final productsById = <String, Product>{};

        for (final snapshot in snapshots) {
          for (final doc in snapshot.docs) {
            productsById[doc.id] = ProductModel.fromFirestore(doc);
          }
        }

        _cacheProducts(productsById.values);

        return [
          for (final id in ids)
            if (productsById[id] != null) productsById[id]!,
        ];
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

        final barcodePage = await _fetchBarcodeExactPage(
          query: query.trim(),
          limit: safeLimit,
        );
        if (barcodePage.products.isNotEmpty) {
          return barcodePage;
        }

        final cursorSource = cursor?.source;
        if (cursorSource == _searchSourceTokens) {
          try {
            return await _fetchTokenSearchPage(
              query: normalizedQuery,
              limit: safeLimit,
              cursor: cursor,
            );
          } on FirebaseException catch (error) {
            if (!_isMissingIndex(error)) rethrow;
          }
        }
        if (cursorSource == _searchSourceSearchName) {
          return _fetchSearchNamePage(
            query: normalizedQuery,
            limit: safeLimit,
            cursor: cursor,
          );
        }
        if (cursorSource?.startsWith(_searchSourceLegacyNamePrefix) == true) {
          return _fetchLegacyNamePage(
            queryVariant: cursorSource!.substring(
              _searchSourceLegacyNamePrefix.length,
            ),
            limit: safeLimit,
            cursor: cursor,
          );
        }

        try {
          final tokenPage = await _fetchTokenSearchPage(
            query: normalizedQuery,
            limit: safeLimit,
            cursor: cursor,
          );
          if (tokenPage.products.isNotEmpty || tokenPage.hasMore) {
            return tokenPage;
          }
        } on FirebaseException catch (error) {
          if (!_isMissingIndex(error)) rethrow;
        }

        final searchNamePage = await _fetchSearchNamePage(
          query: normalizedQuery,
          limit: safeLimit,
          cursor: cursor,
        );
        if (searchNamePage.products.isNotEmpty || searchNamePage.hasMore) {
          return searchNamePage;
        }

        for (final queryVariant in _legacyNameQueryVariants(query)) {
          final legacyPage = await _fetchLegacyNamePage(
            queryVariant: queryVariant,
            limit: safeLimit,
            cursor: cursor,
          );
          if (legacyPage.products.isNotEmpty || legacyPage.hasMore) {
            return legacyPage;
          }
        }

        return const ProductPage(products: <Product>[], hasMore: false);
      },
    );
  }

  @override
  Future<void> addProduct(Product product) {
    return RepositoryGuard.run(
      message: 'Unable to add product.',
      action: () async {
        final model = ProductModel.fromEntity(product);
        await _products
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
      action: () async {
        final model = ProductModel.fromEntity(product);
        await _products
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
      action: () async {
        await _products.doc(normalizedProductId).update({
          ProductField.isAvailable: isAvailable,
          ProductField.updatedAt: FieldValue.serverTimestamp(),
        }).timeout(AppDurations.networkTimeout);
      },
    );
  }

  @override
  Future<void> updateProductStock({
    required String productId,
    required int stockQuantity,
  }) {
    final normalizedProductId = productId.trim();
    if (normalizedProductId.isEmpty) {
      throw ArgumentError.value(productId, 'productId', 'Required');
    }
    if (stockQuantity < 0) {
      throw ArgumentError.value(
        stockQuantity,
        'stockQuantity',
        'Must not be negative',
      );
    }

    return RepositoryGuard.run(
      message: 'Unable to update stock quantity.',
      action: () async {
        await _products.doc(normalizedProductId).update({
          ProductField.stockQuantity: stockQuantity,
          ProductField.isAvailable: stockQuantity > 0,
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
        return StorageImageUploader.uploadBytesWithRetry(
          ref: ref,
          bytes: upload.bytes,
          metadata: SettableMetadata(
            contentType: upload.contentType,
            cacheControl: _imageCacheControl,
          ),
          uploadTimeout: AppDurations.uploadTimeout,
          downloadUrlTimeout: AppDurations.networkTimeout,
          logName: 'ProductImageUpload',
        );
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
      action: () async {
        await _products.doc(normalizedProductId).delete().timeout(
              AppDurations.networkTimeout,
            );
      },
    );
  }

  @override
  Future<ProductStats> fetchInventoryStats() {
    return RepositoryGuard.run(
      message: 'Unable to fetch inventory statistics.',
      action: () async {
        final doc = await _firestore
            .collection(FirestoreCollections.systemStats)
            .doc(FirestoreDocuments.dashboardStats)
            .get()
            .timeout(AppDurations.networkTimeout);

        if (!doc.exists) {
          return const ProductStats(
            totalProducts: 0,
            availableProducts: 0,
            outOfStockProducts: 0,
            lowStockProducts: 0,
            totalCategories: 0,
          );
        }

        final data = doc.data() ?? {};
        return ProductStats(
          totalProducts: data['totalProducts'] as int? ?? 0,
          availableProducts: data['availableProducts'] as int? ?? 0,
          outOfStockProducts: data['outOfStockProducts'] as int? ?? 0,
          lowStockProducts: data['lowStockProducts'] as int? ?? 0,
          totalCategories: data['totalCategories'] as int? ?? 0,
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
    int limit, {
    String? cursorSource,
    String Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)?
        cursorName,
  }) {
    final products = snapshot.docs.map(ProductModel.fromFirestore).toList();
    _cacheProducts(products);

    ProductPageCursor? nextCursor;
    if (products.isNotEmpty) {
      final lastDoc = snapshot.docs.last;
      final lastProduct = products.last;
      nextCursor = ProductPageCursor(
        id: lastProduct.id,
        name: cursorName?.call(lastDoc) ?? lastProduct.name,
        source: cursorSource,
      );
    }

    return ProductPage(
      products: products,
      nextCursor: nextCursor,
      hasMore: snapshot.docs.length == limit,
    );
  }

  Future<ProductPage> _fetchTokenSearchPage({
    required String query,
    required int limit,
    required ProductPageCursor? cursor,
  }) async {
    final token = _searchToken(query);
    if (token.isEmpty) {
      return const ProductPage(products: <Product>[], hasMore: false);
    }

    Query<Map<String, dynamic>> productQuery = _products
        .where(ProductField.searchTokens, arrayContains: token)
        .orderBy(ProductField.searchName)
        .limit(limit);
    productQuery = await _startAfterProductCursor(
      query: productQuery,
      cursor: cursor,
      fallbackValue: cursor?.name.toLowerCase(),
    );

    final snapshot =
        await productQuery.get().timeout(AppDurations.networkTimeout);
    return _pageFromSnapshot(
      snapshot,
      limit,
      cursorSource: _searchSourceTokens,
      cursorName: _searchNameCursorValue,
    );
  }

  Future<ProductPage> _fetchBarcodeExactPage({
    required String query,
    required int limit,
  }) async {
    final barcode = _barcodeSearchValue(query);
    if (!RegExp(r'^\d{4,}$').hasMatch(barcode)) {
      return const ProductPage(products: <Product>[], hasMore: false);
    }

    final snapshot = await _products
        .where(ProductField.barcode, isEqualTo: barcode)
        .limit(limit)
        .get()
        .timeout(AppDurations.networkTimeout);
    final products = snapshot.docs.map(ProductModel.fromFirestore).toList();
    _cacheProducts(products);
    return ProductPage(products: products, hasMore: false);
  }

  Future<ProductPage> _fetchSearchNamePage({
    required String query,
    required int limit,
    required ProductPageCursor? cursor,
  }) async {
    Query<Map<String, dynamic>> productQuery = _products
        .where(
          ProductField.searchName,
          isGreaterThanOrEqualTo: query,
        )
        .where(
          ProductField.searchName,
          isLessThanOrEqualTo: '$query$_prefixSearchTerminator',
        )
        .orderBy(ProductField.searchName)
        .limit(limit);
    productQuery = await _startAfterProductCursor(
      query: productQuery,
      cursor: cursor,
      fallbackValue: cursor?.name.toLowerCase(),
    );

    final snapshot =
        await productQuery.get().timeout(AppDurations.networkTimeout);
    return _pageFromSnapshot(
      snapshot,
      limit,
      cursorSource: _searchSourceSearchName,
      cursorName: _searchNameCursorValue,
    );
  }

  Future<ProductPage> _fetchLegacyNamePage({
    required String queryVariant,
    required int limit,
    required ProductPageCursor? cursor,
  }) async {
    Query<Map<String, dynamic>> productQuery = _products
        .orderBy(ProductField.name)
        .startAt([queryVariant]).endAt(
            ['$queryVariant$_prefixSearchTerminator']).limit(limit);
    productQuery = await _startAfterProductCursor(
      query: productQuery,
      cursor: cursor,
      fallbackValue: cursor?.name,
    );

    final snapshot =
        await productQuery.get().timeout(AppDurations.networkTimeout);
    return _pageFromSnapshot(
      snapshot,
      limit,
      cursorSource: '$_searchSourceLegacyNamePrefix$queryVariant',
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

  static bool _isMissingIndex(FirebaseException error) {
    return error.code == 'failed-precondition' &&
        (error.message?.toLowerCase().contains('index') ?? false);
  }

  static String _searchNameCursorValue(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final value = data[ProductField.searchName]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
    return data[ProductField.name]?.toString().trim().toLowerCase() ?? '';
  }

  static String _searchToken(String query) {
    final words = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    return words.last;
  }

  static String _barcodeSearchValue(String query) {
    return query.trim().replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
  }

  static List<String> _legacyNameQueryVariants(String query) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return const <String>[];

    final lower = trimmedQuery.toLowerCase();
    final upper = trimmedQuery.toUpperCase();
    final title = lower.split(RegExp(r'\s+')).map((word) {
      if (word.isEmpty) return word;
      return '${word[0].toUpperCase()}${word.substring(1)}';
    }).join(' ');

    return {
      trimmedQuery,
      lower,
      title,
      upper,
    }.where((value) => value.trim().isNotEmpty).toList();
  }
}
