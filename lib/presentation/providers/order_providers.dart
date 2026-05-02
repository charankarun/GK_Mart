import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/entities/order.dart';
import 'repository_providers.dart';

final userOrdersProvider =
    StreamProvider.family<List<Order>, String>((ref, userId) {
  return ref.watch(orderRepositoryProvider).watchUserOrders(userId);
});

final ordersStreamProvider = StreamProvider<List<Order>>((ref) {
  return ref.watch(orderRepositoryProvider).watchAllOrders();
});

final adminOrdersProvider = ordersStreamProvider;

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

  Future<String> createOrder(CreateOrderRequest request) async {
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
