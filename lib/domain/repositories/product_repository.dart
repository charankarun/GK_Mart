import '../entities/product.dart';
import '../entities/product_image_upload.dart';
import '../entities/product_page.dart';

abstract class ProductRepository {
  Stream<List<Product>> watchProducts();

  Stream<List<Product>> watchProductsByIds(List<String> productIds);

  Future<ProductPage> fetchProductsPage({
    required int limit,
    ProductPageCursor? cursor,
  });

  Future<void> addProduct(Product product);

  Future<void> updateProduct(Product product);

  Future<void> updateProductAvailability({
    required String productId,
    required bool isAvailable,
  });

  Future<String> uploadProductImage(ProductImageUpload upload);

  Future<void> deleteProduct(String productId);
}
