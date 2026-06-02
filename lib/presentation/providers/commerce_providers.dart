import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/entities/auth_session.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/cart_pricing.dart';
import '../../domain/entities/product.dart';
import 'auth_providers.dart';
import 'repository_providers.dart';

final cartControllerProvider =
    StateNotifierProvider<CartController, List<CartItem>>((ref) {
  return CartController(ref);
});

final cartItemsProvider = Provider<List<CartItem>>((ref) {
  return ref.watch(cartControllerProvider);
});

final cartItemCountProvider = Provider<int>((ref) {
  return ref.watch(cartItemsProvider).fold<int>(
        0,
        (total, item) => total + item.quantity,
      );
});

final cartTotalProvider = Provider<double>((ref) {
  return ref.watch(cartItemsProvider).fold<double>(
        0,
        (total, item) => total + item.lineTotal,
      );
});

final cartSavingsProvider = Provider<double>((ref) {
  return ref.watch(cartItemsProvider).fold<double>(
        0,
        (total, item) => total + item.lineSavings,
      );
});

final cartPricingSummaryProvider = Provider<CartPricingSummary>((ref) {
  return CartPricingSummary.fromCartItems(ref.watch(cartItemsProvider));
});

class CartController extends StateNotifier<List<CartItem>> {
  CartController(this._ref) : super(const <CartItem>[]) {
    _sessionSubscription = _ref.listen<AuthSession?>(
      currentSessionProvider,
      (_, next) => _watchCart(next?.uid),
      fireImmediately: true,
    );
  }

  final Ref _ref;
  ProviderSubscription<AuthSession?>? _sessionSubscription;
  StreamSubscription<List<CartItem>>? _cartSubscription;
  String? _userId;

  void addProduct(Product product) {
    final previousState = state;
    final existingIndex = state.indexWhere((item) {
      return item.productId == product.id;
    });

    if (existingIndex == -1) {
      state = [
        ...state,
        CartItem.fromProduct(product),
      ];
      _persistAddProduct(product, previousState);
      return;
    }

    final nextItems = [...state];
    final existingItem = nextItems[existingIndex];
    nextItems[existingIndex] = existingItem.copyWith(
      name: product.name,
      price: product.price,
      discountPrice: product.discountPrice,
      unit: product.unit,
      imageUrl: product.imageUrl,
      quantity: existingItem.quantity + 1,
    );
    state = nextItems;
    _persistAddProduct(product, previousState);
  }

  void _persistAddProduct(Product product, List<CartItem> previousState) {
    _persist(
      action: () {
        final userId = _requireUserId();
        return _ref.read(cartRepositoryProvider).addProduct(
              userId: userId,
              product: product,
            );
      },
      previousState: previousState,
    );
  }

  void increment(String productId) {
    final previousState = state;
    if (_itemById(productId) == null) return;

    state = [
      for (final item in state)
        if (item.productId == productId)
          item.copyWith(quantity: item.quantity + 1)
        else
          item,
    ];
    _persist(
      action: () {
        final userId = _requireUserId();
        return _ref.read(cartRepositoryProvider).incrementItem(
              userId: userId,
              productId: productId,
            );
      },
      previousState: previousState,
    );
  }

  void decrement(String productId) {
    final previousState = state;
    final existingItem = _itemById(productId);
    state = [
      for (final item in state)
        if (item.productId != productId)
          item
        else if (item.quantity > 1)
          item.copyWith(quantity: item.quantity - 1),
    ];
    if (existingItem == null) return;

    _persist(
      action: () {
        final userId = _requireUserId();
        return _ref.read(cartRepositoryProvider).decrementItem(
              userId: userId,
              productId: productId,
            );
      },
      previousState: previousState,
    );
  }

  void remove(String productId) {
    final previousState = state;
    state = [
      for (final item in state)
        if (item.productId != productId) item,
    ];
    _persist(
      action: () {
        final userId = _requireUserId();
        return _ref.read(cartRepositoryProvider).removeItem(
              userId: userId,
              productId: productId,
            );
      },
      previousState: previousState,
    );
  }

  void clear() {
    final previousState = state;
    state = const <CartItem>[];
    _persist(
      action: () {
        final userId = _requireUserId();
        return _ref.read(cartRepositoryProvider).clearCart(userId);
      },
      previousState: previousState,
    );
  }

  void _watchCart(String? userId) {
    if (_userId == userId) return;

    _userId = userId;
    unawaited(_cartSubscription?.cancel());
    _cartSubscription = null;

    if (userId == null || userId.trim().isEmpty) {
      state = const <CartItem>[];
      return;
    }

    _cartSubscription =
        _ref.read(cartRepositoryProvider).watchCart(userId).listen(
      (items) {
        state = _sortCartItems(items);
      },
      onError: (Object error, StackTrace stackTrace) {
        _logCartError('Unable to sync cart.', error, stackTrace);
      },
    );
  }

  CartItem? _itemById(String productId) {
    for (final item in state) {
      if (item.productId == productId) return item;
    }
    return null;
  }

  String _requireUserId() {
    final userId = _userId?.trim();
    if (userId == null || userId.isEmpty) {
      throw StateError('Cannot update cart without an active user session.');
    }
    return userId;
  }

  void _persist({
    required Future<void> Function() action,
    required List<CartItem> previousState,
  }) {
    unawaited(
      action().catchError((Object error, StackTrace stackTrace) {
        state = previousState;
        _logCartError('Unable to persist cart update.', error, stackTrace);
      }),
    );
  }

  @override
  void dispose() {
    _sessionSubscription?.close();
    unawaited(_cartSubscription?.cancel());
    super.dispose();
  }
}

List<CartItem> _sortCartItems(List<CartItem> items) {
  return [...items]..sort((a, b) => a.name.compareTo(b.name));
}

void _logCartError(String message, Object error, StackTrace stackTrace) {
  developer.log(
    message,
    name: 'CartController',
    error: error,
    stackTrace: stackTrace,
  );
}
