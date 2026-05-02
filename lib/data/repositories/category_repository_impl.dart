import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';
import '../models/category_model.dart';

class CategoryRepositoryImpl implements CategoryRepository {
  CategoryRepositoryImpl(this._firestore);

  final FirebaseFirestore _firestore;

  static const _collectionPath = 'categories';

  CollectionReference<Map<String, dynamic>> get _categories {
    return _firestore.collection(_collectionPath);
  }

  @override
  Stream<List<Category>> watchCategories() {
    return _categories.snapshots().map((snapshot) {
      final categories =
          snapshot.docs.map(CategoryModel.fromFirestore).toList();
      categories.sort((a, b) => a.name.compareTo(b.name));
      return categories;
    });
  }

  @override
  Future<void> addCategory(Category category) {
    final model = CategoryModel.fromEntity(category);
    return _categories.add(model.toFirestore(includeCreatedAt: true));
  }

  @override
  Future<void> updateCategory(Category category) {
    final categoryId = category.id.trim();
    if (categoryId.isEmpty) {
      throw ArgumentError.value(category.id, 'category.id', 'Required');
    }

    final model = CategoryModel.fromEntity(category);
    return _categories.doc(categoryId).set(
          model.toFirestore(includeCreatedAt: false),
          SetOptions(merge: true),
        );
  }

  @override
  Future<void> deleteCategory(String categoryId) {
    return _categories.doc(categoryId).delete();
  }
}
