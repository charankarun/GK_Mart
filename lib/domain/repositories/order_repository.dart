import '../entities/cart_item.dart';
import '../entities/customer_order.dart';
import '../entities/order_analytics.dart';
import '../entities/order_page.dart';

abstract class OrderRepository {
  Stream<List<Order>> watchUserOrders(String userId, {int limit = 20});

  Stream<List<Order>> watchAllOrders({int limit = 50});

  Stream<Order?> watchOrder(String orderId);

  Future<OrderPage> fetchUserOrdersPage({
    required String userId,
    required int limit,
    OrderPageCursor? cursor,
  });

  Future<OrderPage> fetchAllOrdersPage({
    required int limit,
    OrderPageCursor? cursor,
  });

  Future<OrderPage> searchAdminOrders({
    required String query,
    required int limit,
  });

  Future<OrderAnalytics> fetchOrderAnalytics({DateTime? date});

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
