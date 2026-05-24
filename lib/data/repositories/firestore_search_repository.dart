import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/repository_exception.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/search_repository.dart';
import '../models/category_model.dart';
import '../models/product_model.dart';

class FirestoreSearchRepository implements SearchRepository {
  FirestoreSearchRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const _collectionPath = FirestoreCollections.products;
  static const _categoryCollectionPath = FirestoreCollections.categories;
  static const _prefixSearchTerminator = '\uf8ff';

  CollectionReference<Map<String, dynamic>> get _products {
    return _firestore.collection(_collectionPath);
  }

  CollectionReference<Map<String, dynamic>> get _categories {
    return _firestore.collection(_categoryCollectionPath);
  }

  @override
  Stream<List<Product>> watchProductSuggestions({
    required String query,
    required int limit,
  }) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || limit <= 0) {
      return Stream.value(const <Product>[]);
    }

    final searchableQuery = normalizedQuery.toLowerCase();
    final searchToken = _searchToken(searchableQuery);

    return RepositoryGuard.watch(
      message: 'Unable to load product suggestions.',
      create: () => _watchMergedProductSuggestions(
        query: searchableQuery,
        token: searchToken,
        limit: limit,
      ),
    );
  }

  @override
  Future<List<Category>> fetchCategorySuggestions({
    required String query,
    required int limit,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty || limit <= 0) {
      return Future.value(const <Category>[]);
    }

    return RepositoryGuard.run(
      message: 'Unable to load category suggestions.',
      action: () async {
        final categoriesById = <String, Category>{};
        final token = _searchToken(normalizedQuery);

        if (token.isNotEmpty) {
          final tokenSnapshot = await _categories
              .where(CategoryField.searchTokens, arrayContains: token)
              .limit(limit)
              .get()
              .timeout(AppDurations.networkTimeout);
          for (final doc in tokenSnapshot.docs) {
            categoriesById[doc.id] = CategoryModel.fromFirestore(doc);
          }
        }

        if (categoriesById.length < limit) {
          final searchNameSnapshot = await _categories
              .where(
                CategoryField.searchName,
                isGreaterThanOrEqualTo: normalizedQuery,
              )
              .where(
                CategoryField.searchName,
                isLessThanOrEqualTo: '$normalizedQuery$_prefixSearchTerminator',
              )
              .orderBy(CategoryField.searchName)
              .limit(limit)
              .get()
              .timeout(AppDurations.networkTimeout);
          for (final doc in searchNameSnapshot.docs) {
            categoriesById[doc.id] = CategoryModel.fromFirestore(doc);
          }
        }

        for (final queryVariant in _legacyNameQueryVariants(query)) {
          if (categoriesById.length >= limit) break;

          final legacySnapshot = await _categories
              .orderBy(CategoryField.name)
              .startAt([queryVariant])
              .endAt(['$queryVariant$_prefixSearchTerminator'])
              .limit(limit)
              .get()
              .timeout(AppDurations.networkTimeout);
          for (final doc in legacySnapshot.docs) {
            categoriesById[doc.id] = CategoryModel.fromFirestore(doc);
          }
        }

        final categories = categoriesById.values.toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        return categories.take(limit).toList();
      },
    );
  }

  Stream<List<Product>> _watchMergedProductSuggestions({
    required String query,
    required String token,
    required int limit,
  }) {
    late StreamController<List<Product>> controller;
    final productsById = <String, Product>{};
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    void emit() {
      if (controller.isClosed) return;
      final products = productsById.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      controller.add(products.take(limit).toList());
    }

    void listenTo(Query<Map<String, dynamic>> query) {
      final subscription = query.snapshots().listen(
        (snapshot) {
          for (final doc in snapshot.docs) {
            productsById[doc.id] = ProductModel.fromFirestore(doc);
          }
          emit();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (error is FirebaseException && _isMissingIndex(error)) return;
          controller.addError(error, stackTrace);
        },
      );
      subscriptions.add(subscription);
    }

    controller = StreamController<List<Product>>(
      onListen: () {
        if (token.isNotEmpty) {
          listenTo(
            _products
                .where(ProductField.searchTokens, arrayContains: token)
                .orderBy(ProductField.searchName)
                .limit(limit),
          );
        }

        listenTo(
          _products
              .where(
                ProductField.searchName,
                isGreaterThanOrEqualTo: query,
              )
              .where(
                ProductField.searchName,
                isLessThanOrEqualTo: '$query$_prefixSearchTerminator',
              )
              .orderBy(ProductField.searchName)
              .limit(limit),
        );

        for (final queryVariant in _legacyNameQueryVariants(query)) {
          listenTo(
            _products.orderBy(ProductField.name).startAt([queryVariant]).endAt(
                ['$queryVariant$_prefixSearchTerminator']).limit(limit),
          );
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

  static bool _isMissingIndex(FirebaseException error) {
    return error.code == 'failed-precondition' &&
        (error.message?.toLowerCase().contains('index') ?? false);
  }
}
