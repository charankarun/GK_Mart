import '../entities/cart_item.dart';
import '../entities/customer_order.dart';

abstract class OrderRepository {
  Stream<List<Order>> watchUserOrders(String userId);

  Stream<List<Order>> watchAllOrders({int limit = 100});

  Stream<Order?> watchOrder(String orderId);

  Future<String> createOrder(CreateOrderRequest request);

  Future<String> placeOrder({
    required String userId,
    required String customerName,
    required List<CartItem> cartItems,
    required double total,
    required String address,
    required String paymentMethod,
  });

  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
  });
}
