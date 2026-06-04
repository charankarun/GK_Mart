import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/constants/app_constants.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/utils/phone_number_normalizer.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/order_analytics.dart';
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

final orderAnalyticsProvider =
    FutureProvider.autoDispose.family<OrderAnalytics, DateTime>(
  (ref, date) async {
    _dashboardLog(
      'Riverpod orderAnalyticsProvider start date=${date.toIso8601String()}',
    );
    try {
      final analytics = await ref
          .watch(orderRepositoryProvider)
          .fetchOrderAnalytics(date: date)
          .timeout(AppDurations.dashboardTimeout);
      _dashboardLog(
        'Riverpod orderAnalyticsProvider result '
        'totalOrders=${analytics.totalOrders} '
        'selectedDateOrders=${analytics.selectedDateOrders}',
      );
      return analytics;
    } catch (error, stackTrace) {
      _dashboardLog(
        'Riverpod orderAnalyticsProvider exception',
        error: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  },
);

final dashboardRecentOrdersProvider =
    FutureProvider.autoDispose<List<Order>>((ref) async {
  _dashboardLog(
    'Orders query start dashboardRecentOrders '
    'limit=${OrderProviderConfig.dashboardRecentOrderLimit}',
  );
  try {
    final page = await ref
        .watch(orderRepositoryProvider)
        .fetchAllOrdersPage(
          limit: OrderProviderConfig.dashboardRecentOrderLimit,
        )
        .timeout(AppDurations.dashboardTimeout);
    _dashboardLog('Orders query result count=${page.orders.length}');
    return page.orders;
  } catch (error, stackTrace) {
    _dashboardLog(
      'Riverpod dashboardRecentOrdersProvider exception',
      error: error,
      stackTrace: stackTrace,
    );
    Error.throwWithStackTrace(error, stackTrace);
  }
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

final adminDateOrderListProvider = StateNotifierProvider.autoDispose
    .family<AdminDateOrderListController, AsyncValue<OrderListState>, DateTime>(
  (ref, date) {
    return AdminDateOrderListController(ref, _dateOnly(date))..loadInitial();
  },
);

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
    _orderCreationLog(
      'Controller createOrder start '
      'userIdPresent=${request.userId.trim().isNotEmpty} '
      'items=${request.items.length} '
      'phoneNormalized='
      '${PhoneNumberNormalizer.toIndianLocalNumber(request.phone).isNotEmpty}',
    );

    try {
      _orderCreationLog('Repository called');
      final orderId = await _ref.read(orderRepositoryProvider).createOrder(
            request,
          );
      state = AsyncData(orderId);
      _orderCreationLog('Controller createOrder success orderId=$orderId.');
      return orderId;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      _orderCreationLog(
        'Controller createOrder failed.',
        error: error,
        stackTrace: stackTrace,
      );
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
    return const <String, String>{};
  }

  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
    required String targetUserId,
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

      // Notify the customer that their order status has changed.
      if (targetUserId.trim().isNotEmpty) {
        unawaited(
          NotificationService.instance.enqueueOrderStatusNotification(
            targetUserId: targetUserId.trim(),
            orderId: orderId,
            status: normalizedStatus,
          ),
        );
      }
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
  String _searchQuery = '';
  String? _statusFilter;
  bool _sortAscending = false;
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> loadInitial({
    String? searchQuery,
    String? statusFilter,
    bool? sortAscending,
  }) async {
    if (searchQuery != null) _searchQuery = searchQuery.trim();
    if (statusFilter != null) {
      _statusFilter = _normalizedStatusFilter(statusFilter);
    }
    if (sortAscending != null) _sortAscending = sortAscending;

    state = const AsyncLoading();

    try {
      final page = _searchQuery.isEmpty
          ? await _ref.read(orderRepositoryProvider).fetchAllOrdersPage(
                limit: OrderProviderConfig.pageSize,
                status: _statusFilter,
                descending: !_sortAscending,
              )
          : await _ref.read(orderRepositoryProvider).searchAdminOrders(
                query: _searchQuery,
                limit: OrderProviderConfig.pageSize,
                status: _statusFilter,
                descending: !_sortAscending,
              );
      state = AsyncData(
        OrderListState.fromPage(page).copyWith(
          searchQuery: _searchQuery,
          statusFilter: _statusFilter ?? '',
          sortAscending: _sortAscending,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed == _searchQuery) return;

    _debounceTimer?.cancel();

    if (trimmed.isEmpty) {
      _searchQuery = '';
      await loadInitial(searchQuery: '');
      return;
    }

    if (trimmed.length < 2) {
      return;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return loadInitial(searchQuery: trimmed);
    }

    final completer = Completer<void>();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        await loadInitial(searchQuery: trimmed);
        if (!completer.isCompleted) completer.complete();
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });

    return completer.future;
  }

  Future<void> setStatusFilter(String statusFilter) {
    return loadInitial(statusFilter: statusFilter);
  }

  Future<void> setSortAscending(bool sortAscending) {
    return loadInitial(sortAscending: sortAscending);
  }

  Future<void> loadNext() async {
    final currentState = _currentState;
    if (currentState == null ||
        currentState.isLoadingMore ||
        !currentState.hasMore ||
        _searchQuery.isNotEmpty) {
      return;
    }

    state = AsyncData(currentState.copyWith(isLoadingMore: true));

    try {
      final page = await _ref.read(orderRepositoryProvider).fetchAllOrdersPage(
            limit: OrderProviderConfig.pageSize,
            cursor: currentState.nextCursor,
            status: _statusFilter,
            descending: !_sortAscending,
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

class AdminDateOrderListController
    extends StateNotifier<AsyncValue<OrderListState>> {
  AdminDateOrderListController(this._ref, this._date)
      : super(const AsyncLoading());

  final Ref _ref;
  final DateTime _date;
  String _searchQuery = '';
  String? _statusFilter;
  bool _sortAscending = false;
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> loadInitial({
    String? searchQuery,
    String? statusFilter,
    bool? sortAscending,
  }) async {
    if (searchQuery != null) _searchQuery = searchQuery.trim();
    if (statusFilter != null) {
      _statusFilter = _normalizedStatusFilter(statusFilter);
    }
    if (sortAscending != null) _sortAscending = sortAscending;

    state = const AsyncLoading();

    try {
      final repository = _ref.read(orderRepositoryProvider);
      final page = _searchQuery.isEmpty
          ? await repository.fetchOrdersByDatePage(
              date: _date,
              limit: OrderProviderConfig.dateOrderPageSize,
              status: _statusFilter,
              descending: !_sortAscending,
            )
          : await repository.searchAdminOrdersByDate(
              query: _searchQuery,
              date: _date,
              limit: OrderProviderConfig.dateOrderPageSize,
              status: _statusFilter,
              descending: !_sortAscending,
            );

      state = AsyncData(
        OrderListState.fromPage(page).copyWith(
          searchQuery: _searchQuery,
          statusFilter: _statusFilter ?? '',
          sortAscending: _sortAscending,
          dateFilter: _date,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed == _searchQuery) return;

    _debounceTimer?.cancel();

    if (trimmed.isEmpty) {
      _searchQuery = '';
      await loadInitial(searchQuery: '');
      return;
    }

    if (trimmed.length < 2) {
      return;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return loadInitial(searchQuery: trimmed);
    }

    final completer = Completer<void>();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        await loadInitial(searchQuery: trimmed);
        if (!completer.isCompleted) completer.complete();
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });

    return completer.future;
  }

  Future<void> setStatusFilter(String statusFilter) {
    return loadInitial(statusFilter: statusFilter);
  }

  Future<void> setSortAscending(bool sortAscending) {
    return loadInitial(sortAscending: sortAscending);
  }

  Future<void> loadNext() async {
    final currentState = _currentState;
    if (currentState == null ||
        currentState.isLoadingMore ||
        !currentState.hasMore ||
        _searchQuery.isNotEmpty) {
      return;
    }

    state = AsyncData(currentState.copyWith(isLoadingMore: true));

    try {
      final page =
          await _ref.read(orderRepositoryProvider).fetchOrdersByDatePage(
                date: _date,
                limit: OrderProviderConfig.dateOrderPageSize,
                cursor: currentState.nextCursor,
                status: _statusFilter,
                descending: !_sortAscending,
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
    this.searchQuery = '',
    this.statusFilter = '',
    this.sortAscending = false,
    this.dateFilter,
  });

  final List<Order> orders;
  final OrderPageCursor? nextCursor;
  final bool hasMore;
  final bool isLoadingMore;
  final String searchQuery;
  final String statusFilter;
  final bool sortAscending;
  final DateTime? dateFilter;

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
    String? searchQuery,
    String? statusFilter,
    bool? sortAscending,
    DateTime? dateFilter,
  }) {
    return OrderListState(
      orders: orders ?? this.orders,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      searchQuery: searchQuery ?? this.searchQuery,
      statusFilter: statusFilter ?? this.statusFilter,
      sortAscending: sortAscending ?? this.sortAscending,
      dateFilter: dateFilter ?? this.dateFilter,
    );
  }

  OrderListState appendPage(OrderPage page) {
    final ordersById = <String, Order>{
      for (final order in orders) order.id: order,
    };
    for (final order in page.orders) {
      ordersById[order.id] = order;
    }

    return OrderListState(
      orders: ordersById.values.toList(),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      searchQuery: searchQuery,
      statusFilter: statusFilter,
      sortAscending: sortAscending,
      dateFilter: dateFilter,
    );
  }
}

class OrderProviderConfig {
  const OrderProviderConfig._();

  static const pageSize = 20;
  static const dateOrderPageSize = 30;
  static const dashboardRecentOrderLimit = 4;
}

const _dashboardLogName = 'AdminDashboard';
const _orderCreationLogName = 'OrderCreation';
const _debugLoggingEnabled = !bool.fromEnvironment('dart.vm.product');

void _dashboardLog(
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  if (!_debugLoggingEnabled) return;
  developer.log(
    message,
    name: _dashboardLogName,
    error: error,
    stackTrace: stackTrace,
  );
}

void _orderCreationLog(
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  if (!_debugLoggingEnabled) return;
  developer.log(
    message,
    name: _orderCreationLogName,
    error: error,
    stackTrace: stackTrace,
  );
}

DateTime _dateOnly(DateTime date) {
  final localDate = date.toLocal();
  return DateTime(localDate.year, localDate.month, localDate.day);
}

String? _normalizedStatusFilter(String status) {
  final trimmed = status.trim();
  if (trimmed.isEmpty) return null;
  final normalized = OrderStatus.normalize(trimmed);
  return OrderStatus.values.contains(normalized) ? normalized : null;
}
