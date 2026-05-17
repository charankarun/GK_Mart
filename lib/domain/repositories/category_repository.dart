import '../entities/category.dart';
import '../entities/category_image_upload.dart';
import '../entities/category_page.dart';

abstract class CategoryRepository {
  Stream<List<Category>> watchCategories({int limit = 50});

  Future<CategoryPage> fetchCategoriesPage({
    required int limit,
    CategoryPageCursor? cursor,
  });

  Future<void> addCategory(Category category);

  Future<void> updateCategory(Category category);

  Future<void> deleteCategory(String categoryId);

  Future<String> uploadCategoryImage(CategoryImageUpload upload);
}
