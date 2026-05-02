import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import 'repository_providers.dart';

final productsStreamProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(productRepositoryProvider).watchProducts();
});

final productsProvider = productsStreamProvider;

final addProductProvider = Provider<Future<void> Function(Product)>((ref) {
  return (product) {
    return ref.read(productRepositoryProvider).addProduct(product);
  };
});

final updateProductProvider = Provider<Future<void> Function(Product)>((ref) {
  return (product) {
    return ref.read(productRepositoryProvider).updateProduct(product);
  };
});

final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchCategories();
});

final categoriesProvider = categoriesStreamProvider;

final addCategoryProvider = Provider<Future<void> Function(Category)>((ref) {
  return (category) {
    return ref.read(categoryRepositoryProvider).addCategory(category);
  };
});

final updateCategoryProvider = Provider<Future<void> Function(Category)>((ref) {
  return (category) {
    return ref.read(categoryRepositoryProvider).updateCategory(category);
  };
});

final deleteCategoryProvider = Provider<Future<void> Function(String)>((ref) {
  return (categoryId) {
    return ref.read(categoryRepositoryProvider).deleteCategory(categoryId);
  };
});
