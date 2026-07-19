// ==============================================================================
// FILE: lib/domain/repositories/order_repository.dart
// PURPOSE: Abstract interface contract defining order tracking and query behavior.
// LAYER: Domain / Repository Contracts
// DEPENDENCIES: Domain entities (Order, CartItem, OrderAnalytics, OrderPage)
//
// ARCHITECTURAL ROLE:
// Decouples UI controllers (providers) from specific database clients (Firestore).
// Defines contract interfaces for real-time order streams, paginated queries,
// full-text order searches, status updates, and order placements.
// ==============================================================================

import '../entities/cart_item.dart';
import '../entities/customer_order.dart';
import '../entities/order_analytics.dart';
import '../entities/order_page.dart';

/// Abstract repository defining order management CRUD operations.
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
    String? status,
    bool descending = true,
  });

  Future<OrderPage> fetchOrdersByDatePage({
    required DateTime date,
    required int limit,
    OrderPageCursor? cursor,
    String? status,
    bool descending = true,
  });

  Future<OrderPage> searchAdminOrders({
    required String query,
    required int limit,
    String? status,
    bool descending = true,
  });

  Future<OrderPage> searchAdminOrdersByDate({
    required String query,
    required DateTime date,
    required int limit,
    String? status,
    bool descending = true,
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

  Future<void> cancelOrder({
    required String orderId,
    required String userId,
  });
}
