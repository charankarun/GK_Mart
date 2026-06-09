import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_app/domain/entities/cart_item.dart';
import 'package:supermarket_app/domain/entities/customer_order.dart';
import 'package:supermarket_app/domain/entities/order_analytics.dart';
import 'package:supermarket_app/domain/entities/order_page.dart';
import 'package:supermarket_app/domain/entities/product_stats.dart';
import 'package:supermarket_app/domain/repositories/order_repository.dart';
import 'package:supermarket_app/presentation/providers/auth_providers.dart';
import 'package:supermarket_app/presentation/providers/order_providers.dart';
import 'package:supermarket_app/presentation/providers/product_provider.dart';
import 'package:supermarket_app/presentation/providers/repository_providers.dart';
import 'package:supermarket_app/presentation/screens/admin/admin_dashboard_screen.dart';
import 'package:supermarket_app/domain/entities/app_user.dart';
import 'package:supermarket_app/domain/entities/user_role.dart';
import 'package:supermarket_app/domain/entities/user_status.dart';

void main() {
  test('admin all-orders list supports search, sort, and status filter',
      () async {
    final repository = _FakeOrderRepository(_orders);
    final container = ProviderContainer(
      overrides: [
        orderRepositoryProvider.overrideWith((ref) => repository),
        currentUserProfileProvider.overrideWithValue(
          const AsyncValue<AppUser?>.data(
            AppUser(
              uid: 'admin-1',
              role: UserRole.owner,
              status: UserStatus.active,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(adminOrderListProvider.notifier);

    await controller.loadInitial();
    expect(_visibleOrderIds(container), ['GK00003', 'GK00002', 'GK00001']);

    await controller.setStatusFilter(OrderStatus.delivered);
    expect(_visibleOrderIds(container), ['GK00002']);
    expect(container.read(adminOrderListProvider).value?.statusFilter,
        OrderStatus.delivered);

    await controller.setStatusFilter('');
    await controller.setSortAscending(true);
    expect(_visibleOrderIds(container), ['GK00001', 'GK00002', 'GK00003']);
    expect(container.read(adminOrderListProvider).value?.sortAscending, true);

    await controller.search('asha');
    expect(_visibleOrderIds(container), ['GK00001']);

    await controller.search('2222');
    expect(_visibleOrderIds(container), ['GK00002']);

    await controller.search('GK00003');
    expect(_visibleOrderIds(container), ['GK00003']);
  });

  testWidgets('dashboard order cards open the expected drill-down screens',
      (tester) async {
    final repository = _FakeOrderRepository(_orders);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isAdminProvider.overrideWith((ref) => Stream<bool>.value(true)),
          orderRepositoryProvider.overrideWith((ref) => repository),
          currentUserProfileProvider.overrideWithValue(
            const AsyncValue<AppUser?>.data(
              AppUser(
                uid: 'admin-1',
                role: UserRole.owner,
                status: UserStatus.active,
              ),
            ),
          ),
          dashboardInventoryStatsProvider.overrideWith((ref) async {
            return const ProductStats(
              totalProducts: 3,
              availableProducts: 2,
              outOfStockProducts: 1,
              lowStockProducts: 1,
              totalCategories: 0,
            );
          }),
        ],
        child: const MaterialApp(home: AdminDashboardScreen()),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Total Orders'));
    await tester.pumpAndSettle();
    expect(find.text('Admin Orders'), findsOneWidget);

    Navigator.of(tester.element(find.text('Admin Orders'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Orders For Selected Date'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Orders - '), findsOneWidget);
  });

  test('cancelOrder updates order status to Cancelled', () async {
    final repository = _FakeOrderRepository([
      Order(
        id: 'GK00001',
        userId: 'customer-1',
        userName: 'Asha Rao',
        phone: '+9199991111',
        items: const <OrderItem>[],
        totalAmount: 120,
        totalSavings: 0,
        address: 'Address 1',
        status: OrderStatus.placed,
        createdAt: DateTime(2026, 6, 1, 9),
      ),
    ]);
    
    await repository.cancelOrder(orderId: 'GK00001', userId: 'customer-1');
    final orderPage = await repository.fetchAllOrdersPage(limit: 10);
    expect(orderPage.orders.first.status, OrderStatus.cancelled);
  });
}

List<String> _visibleOrderIds(ProviderContainer container) {
  return container
          .read(adminOrderListProvider)
          .value
          ?.orders
          .map((order) => order.id)
          .toList() ??
      const <String>[];
}

final _orders = [
  Order(
    id: 'GK00001',
    userId: 'customer-1',
    userName: 'Asha Rao',
    phone: '+9199991111',
    items: const <OrderItem>[],
    totalAmount: 120,
    totalSavings: 0,
    address: 'Address 1',
    status: OrderStatus.placed,
    createdAt: DateTime(2026, 6, 1, 9),
  ),
  Order(
    id: 'GK00002',
    userId: 'customer-2',
    userName: 'Bharat Kumar',
    phone: '+9199992222',
    items: const <OrderItem>[],
    totalAmount: 240,
    totalSavings: 0,
    address: 'Address 2',
    status: OrderStatus.delivered,
    createdAt: DateTime(2026, 6, 1, 10),
  ),
  Order(
    id: 'GK00003',
    userId: 'customer-3',
    userName: 'Chitra Devi',
    phone: '+9199993333',
    items: const <OrderItem>[],
    totalAmount: 360,
    totalSavings: 0,
    address: 'Address 3',
    status: OrderStatus.packed,
    createdAt: DateTime(2026, 6, 1, 11),
  ),
];

class _FakeOrderRepository implements OrderRepository {
  _FakeOrderRepository(this._orders);

  final List<Order> _orders;

  @override
  Future<OrderPage> fetchAllOrdersPage({
    required int limit,
    OrderPageCursor? cursor,
    String? status,
    bool descending = true,
  }) async {
    return _page(
      _filterStatus(_orders, status),
      limit: limit,
      descending: descending,
    );
  }

  @override
  Future<OrderPage> searchAdminOrders({
    required String query,
    required int limit,
    String? status,
    bool descending = true,
  }) async {
    final normalizedQuery = _normalize(query);
    final matches = _filterStatus(_orders, status).where((order) {
      return _normalize(order.id).contains(normalizedQuery) ||
          _normalize(order.customerDisplayName).contains(normalizedQuery) ||
          _normalize(order.phone).contains(normalizedQuery);
    });

    return _page(matches, limit: limit, descending: descending);
  }

  OrderPage _page(
    Iterable<Order> orders, {
    required int limit,
    required bool descending,
  }) {
    final sorted = orders.toList()
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return descending ? bDate.compareTo(aDate) : aDate.compareTo(bDate);
      });

    return OrderPage(
      orders: sorted.take(limit).toList(),
      hasMore: sorted.length > limit,
    );
  }

  Iterable<Order> _filterStatus(Iterable<Order> orders, String? status) {
    final normalizedStatus = _normalizeStatus(status);
    if (normalizedStatus == null) return orders;
    return orders.where((order) {
      return OrderStatus.normalize(order.status) == normalizedStatus;
    });
  }

  String? _normalizeStatus(String? status) {
    final trimmed = status?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return OrderStatus.normalize(trimmed);
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  DateTime _dateOnly(DateTime date) {
    final localDate = date.toLocal();
    return DateTime(localDate.year, localDate.month, localDate.day);
  }

  @override
  Future<String> createOrder(CreateOrderRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<OrderAnalytics> fetchOrderAnalytics({DateTime? date}) async {
    final selectedDate = _dateOnly(date ?? DateTime.now());
    final nextDate = selectedDate.add(const Duration(days: 1));
    final selectedDateOrders = _orders.where((order) {
      final createdAt = order.createdAt;
      return createdAt != null &&
          !createdAt.isBefore(selectedDate) &&
          createdAt.isBefore(nextDate);
    }).length;

    return OrderAnalytics(
      totalOrders: _orders.length,
      revenue: _orders.fold<double>(
        0,
        (total, order) => total + order.total,
      ),
      pendingOrders: _orders.where((order) {
        return OrderStatus.normalize(order.status) != OrderStatus.delivered;
      }).length,
      deliveredOrders: _orders.where((order) {
        return OrderStatus.normalize(order.status) == OrderStatus.delivered;
      }).length,
      selectedDate: selectedDate,
      selectedDateOrders: selectedDateOrders,
      selectedDateRevenue: _orders.fold<double>(0, (total, order) {
        final createdAt = order.createdAt;
        if (createdAt == null ||
            createdAt.isBefore(selectedDate) ||
            !createdAt.isBefore(nextDate)) {
          return total;
        }
        return total + order.total;
      }),
    );
  }

  @override
  Future<OrderPage> fetchOrdersByDatePage({
    required DateTime date,
    required int limit,
    OrderPageCursor? cursor,
    String? status,
    bool descending = true,
  }) async {
    final startDate = _dateOnly(date);
    final endDate = startDate.add(const Duration(days: 1));
    final matches = _filterStatus(_orders, status).where((order) {
      final createdAt = order.createdAt;
      return createdAt != null &&
          !createdAt.isBefore(startDate) &&
          createdAt.isBefore(endDate);
    });

    return _page(matches, limit: limit, descending: descending);
  }

  @override
  Future<OrderPage> fetchUserOrdersPage({
    required String userId,
    required int limit,
    OrderPageCursor? cursor,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> placeOrder({
    required String userId,
    required String customerName,
    required List<CartItem> cartItems,
    required double total,
    required String address,
    required String paymentMethod,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<OrderPage> searchAdminOrdersByDate({
    required String query,
    required DateTime date,
    required int limit,
    String? status,
    bool descending = true,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> cancelOrder({
    required String orderId,
    required String userId,
  }) async {
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index != -1) {
      _orders[index] = Order(
        id: _orders[index].id,
        userId: _orders[index].userId,
        userName: _orders[index].userName,
        phone: _orders[index].phone,
        items: _orders[index].items,
        totalAmount: _orders[index].totalAmount,
        totalSavings: _orders[index].totalSavings,
        address: _orders[index].address,
        status: OrderStatus.cancelled,
        createdAt: _orders[index].createdAt,
      );
    }
  }

  @override
  Stream<List<Order>> watchAllOrders({int limit = 50}) {
    throw UnimplementedError();
  }

  @override
  Stream<Order?> watchOrder(String orderId) {
    throw UnimplementedError();
  }

  @override
  Stream<List<Order>> watchUserOrders(String userId, {int limit = 20}) {
    throw UnimplementedError();
  }
}
