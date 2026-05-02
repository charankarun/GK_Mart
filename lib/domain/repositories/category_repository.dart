import '../entities/category.dart';

abstract class CategoryRepository {
  Stream<List<Category>> watchCategories();

  Future<void> addCategory(Category category);

  Future<void> updateCategory(Category category);

  Future<void> deleteCategory(String categoryId);
}
