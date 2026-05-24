import '../entities/category.dart';
import '../entities/product.dart';

abstract class SearchRepository {
  Stream<List<Product>> watchProductSuggestions({
    required String query,
    required int limit,
  });

  Future<List<Category>> fetchCategorySuggestions({
    required String query,
    required int limit,
  });
}
