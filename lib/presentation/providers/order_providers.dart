import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/entities/order.dart';
import '../../domain/entities/order_page.dart';
import 'repository_providers.dart';

final userOrdersProvider =
    StreamProvider.family<List<Order>, String>((ref, userId) {
  return ref.watch(orderRepositoryProvider).watchUserOrders(userId);
});

final ordersStreamProvider = StreamProvider<List<Order>>((ref) {
  return ref.watch(orderRepositoryProvider).watchAllOrders();
});

final adminOrdersProvider = ordersStreamProvider;

final orderAnalyticsProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(orderRepositoryProvider).fetchOrderAnalytics();
});

final userOrderListProvider = StateNotifierProvider.autoDispose
    .family<UserOrderListController, AsyncValue<OrderListState>, String>(
  (ref, userId) {
    return UserOrderListController(ref, userId)..loadInitial();
  },
);

final adminOrderListProvider = StateNotifierProvider.autoDispose<
    AdminOrderListController, AsyncValue<OrderListState>>((ref) {
  return AdminOrderListController(ref)..loadInitial();
});

final orderDetailsProvider =
    StreamProvider.family<Order?, String>((ref, orderId) {
  return ref.watch(orderRepositoryProvider).watchOrder(orderId);
});

final serviceablePincodesProvider = Provider<Set<String>>((ref) {
  return const {
    '560001',
    '560002',
    '560003',
    '560004',
    '560005',
  };
});

final orderCreationControllerProvider =
    StateNotifierProvider<OrderCreationController, AsyncValue<String?>>((ref) {
  return OrderCreationController(ref);
});

class OrderCreationController extends StateNotifier<AsyncValue<String?>> {
  OrderCreationController(this._ref) : super(const AsyncData(null));

  final Ref _ref;
  Future<String>? _activeCreateOrder;

  Future<String> createOrder(CreateOrderRequest request) async {
    final activeCreateOrder = _activeCreateOrder;
    if (activeCreateOrder != null) return activeCreateOrder;

    final createOrder = _createOrder(request);
    _activeCreateOrder = createOrder;

    try {
      return await createOrder;
    } finally {
      _activeCreateOrder = null;
    }
  }

  Future<String> _createOrder(CreateOrderRequest request) async {
    state = const AsyncLoading();

    try {
      final orderId = await _ref.read(orderRepositoryProvider).createOrder(
            request,
          );
      state = AsyncData(orderId);
      return orderId;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  void reset() {
    state = const AsyncData(null);
  }
}

final orderStatusUpdateControllerProvider =
    NotifierProvider<OrderStatusUpdateController, Map<String, String>>(
  OrderStatusUpdateController.new,
);

class OrderStatusUpdateController extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() {
    ref.listen<AsyncValue<List<Order>>>(ordersStreamProvider, (_, next) {
      next.whenData(_clearSyncedStatuses);
    });

    return const <String, String>{};
  }

  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
  }) async {
    if (state.containsKey(orderId)) return;

    final normalizedStatus = OrderStatus.normalize(status);
    final previousStatus = state[orderId];

    state = {
      ...state,
      orderId: normalizedStatus,
    };

    try {
      await ref.read(orderRepositoryProvider).updateOrderStatus(
            orderId: orderId,
            status: normalizedStatus,
          );
      final nextState = Map<String, String>.from(state)..remove(orderId);
      state = nextState;
    } catch (_) {
      final nextState = Map<String, String>.from(state);
      if (previousStatus == null) {
        nextState.remove(orderId);
      } else {
        nextState[orderId] = previousStatus;
      }
      state = nextState;
      rethrow;
    }
  }

  void _clearSyncedStatuses(List<Order> orders) {
    if (state.isEmpty) return;

    final nextState = Map<String, String>.from(state);

    for (final order in orders) {
      final pendingStatus = nextState[order.id];
      if (pendingStatus == null) continue;

      if (OrderStatus.normalize(order.status) == pendingStatus) {
        nextState.remove(order.id);
      }
    }

    if (nextState.length != state.length) {
      state = nextState;
    }
  }
}

class UserOrderListController
    extends StateNotifier<AsyncValue<OrderListState>> {
  UserOrderListController(this._ref, this._userId)
      : super(const AsyncLoading());

  final Ref _ref;
  final String _userId;

  Future<void> loadInitial() async {
    state = const AsyncLoading();

    try {
      final page = await _ref.read(orderRepositoryProvider).fetchUserOrdersPage(
            userId: _userId,
            limit: OrderProviderConfig.pageSize,
          );
      state = AsyncData(OrderListState.fromPage(page));
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> loadNext() {
    return _loadNext((cursor) {
      return _ref.read(orderRepositoryProvider).fetchUserOrdersPage(
            userId: _userId,
            limit: OrderProviderConfig.pageSize,
            cursor: cursor,
          );
    });
  }

  Future<void> _loadNext(OrderPageLoader loadPage) async {
    final currentState = _currentState;
    if (currentState == null ||
        currentState.isLoadingMore ||
        !currentState.hasMore) {
      return;
    }

    state = AsyncData(currentState.copyWith(isLoadingMore: true));

    try {
      final page = await loadPage(currentState.nextCursor);
      state = AsyncData(currentState.appendPage(page));
    } catch (_) {
      state = AsyncData(currentState.copyWith(isLoadingMore: false));
      rethrow;
    }
  }

  OrderListState? get _currentState {
    return state.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
  }
}

class AdminOrderListController
    extends StateNotifier<AsyncValue<OrderListState>> {
  AdminOrderListController(this._ref) : super(const AsyncLoading());

  final Ref _ref;

  Future<void> loadInitial() async {
    state = const AsyncLoading();

    try {
      final page = await _ref.read(orderRepositoryProvider).fetchAllOrdersPage(
            limit: OrderProviderConfig.pageSize,
          );
      state = AsyncData(OrderListState.fromPage(page));
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> loadNext() async {
    final currentState = _currentState;
    if (currentState == null ||
        currentState.isLoadingMore ||
        !currentState.hasMore) {
      return;
    }

    state = AsyncData(currentState.copyWith(isLoadingMore: true));

    try {
      final page = await _ref.read(orderRepositoryProvider).fetchAllOrdersPage(
            limit: OrderProviderConfig.pageSize,
            cursor: currentState.nextCursor,
          );
      state = AsyncData(currentState.appendPage(page));
    } catch (_) {
      state = AsyncData(currentState.copyWith(isLoadingMore: false));
      rethrow;
    }
  }

  OrderListState? get _currentState {
    return state.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
  }
}

typedef OrderPageLoader = Future<OrderPage> Function(
  OrderPageCursor? cursor,
);

class OrderListState {
  const OrderListState({
    required this.orders,
    required this.hasMore,
    this.nextCursor,
    this.isLoadingMore = false,
  });

  final List<Order> orders;
  final OrderPageCursor? nextCursor;
  final bool hasMore;
  final bool isLoadingMore;

  factory OrderListState.fromPage(OrderPage page) {
    return OrderListState(
      orders: page.orders,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  OrderListState copyWith({
    List<Order>? orders,
    OrderPageCursor? nextCursor,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return OrderListState(
      orders: orders ?? this.orders,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  OrderListState appendPage(OrderPage page) {
    return OrderListState(
      orders: [...orders, ...page.orders],
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }
}

class OrderProviderConfig {
  const OrderProviderConfig._();

  static const pageSize = 20;
}
