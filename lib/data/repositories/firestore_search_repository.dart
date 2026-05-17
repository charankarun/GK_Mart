import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/repository_exception.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/search_repository.dart';
import '../models/product_model.dart';

class FirestoreSearchRepository implements SearchRepository {
  FirestoreSearchRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const _collectionPath = FirestoreCollections.products;
  static const _prefixSearchTerminator = '\uf8ff';

  CollectionReference<Map<String, dynamic>> get _products {
    return _firestore.collection(_collectionPath);
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

    return RepositoryGuard.watch(
      message: 'Unable to load product suggestions.',
      create: () {
        return _products
            .where(
              ProductField.searchName,
              isGreaterThanOrEqualTo: searchableQuery,
            )
            .where(
              ProductField.searchName,
              isLessThanOrEqualTo: '$searchableQuery$_prefixSearchTerminator',
            )
            .orderBy(ProductField.searchName)
            .limit(limit)
            .snapshots()
            .map((snapshot) {
          return snapshot.docs.map(ProductModel.fromFirestore).toList();
        });
      },
    );
  }
}
