import '../entities/cart_item.dart';
import '../entities/product.dart';

abstract class CartRepository {
  Stream<List<CartItem>> watchCart(String userId);

  Future<void> addProduct({
    required String userId,
    required Product product,
  });

  Future<void> setQuantity({
    required String userId,
    required CartItem item,
    required int quantity,
  });

  Future<void> incrementItem({
    required String userId,
    required String productId,
  });

  Future<void> decrementItem({
    required String userId,
    required String productId,
  });

  Future<void> removeItem({
    required String userId,
    required String productId,
  });

  Future<void> clearCart(String userId);
}
