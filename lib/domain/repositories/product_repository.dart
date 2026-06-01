import '../entities/product.dart';
import '../entities/product_image_upload.dart';
import '../entities/product_page.dart';

abstract class ProductRepository {
  Stream<List<Product>> watchProducts({int limit = 40});

  Stream<List<Product>> watchProductsByIds(List<String> productIds);

  Future<ProductPage> fetchProductsPage({
    required int limit,
    ProductPageCursor? cursor,
  });

  Future<ProductPage> fetchProductsByCategoryPage({
    required String categoryId,
    String? categoryName,
    required int limit,
    ProductPageCursor? cursor,
  });

  Future<ProductPage> fetchProductSearchPage({
    required String query,
    required int limit,
    ProductPageCursor? cursor,
  });

  Future<void> addProduct(Product product);

  Future<void> updateProduct(Product product);

  Future<void> updateProductAvailability({
    required String productId,
    required bool isAvailable,
  });

  Future<void> updateProductStock({
    required String productId,
    required int stockQuantity,
  });

  Future<String> uploadProductImage(ProductImageUpload upload);

  Future<void> deleteProduct(String productId);
}
