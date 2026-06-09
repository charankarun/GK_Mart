import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/entities/app_user.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/cart_pricing.dart';
import '../../domain/entities/product.dart';
import '../../services/analytics_service.dart';
import 'auth_providers.dart';
import 'catalog_providers.dart';
import 'repository_providers.dart';

final cartControllerProvider =
    StateNotifierProvider<CartController, List<CartItem>>((ref) {
  return CartController(ref);
});

final cartItemsProvider = Provider<List<CartItem>>((ref) {
  final rawItems = ref.watch(cartControllerProvider);
  if (rawItems.isEmpty) return const <CartItem>[];

  final productIds = rawItems.map((item) => item.productId).toList();
  final existingProductsAsync = ref.watch(productsByIdsProvider(ProductIdsRequest(productIds)));

  return existingProductsAsync.maybeWhen(
    data: (products) {
      final existingIds = products.map((p) => p.id).toSet();
      return rawItems.where((item) => existingIds.contains(item.productId)).toList();
    },
    orElse: () => rawItems,
  );
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

class CartSyncState {
  const CartSyncState({
    this.catalogProducts = const {},
    this.priceChangedProductIds = const {},
    this.oldPrices = const {},
    this.newPrices = const {},
    this.unavailableProductIds = const {},
    this.isSyncing = false,
    this.syncMessage,
    this.recalculatedPricing,
    this.recalculatedItems,
  });

  final Map<String, Product> catalogProducts;
  final Set<String> priceChangedProductIds;
  final Map<String, double> oldPrices;
  final Map<String, double> newPrices;
  final Set<String> unavailableProductIds;
  final bool isSyncing;
  final String? syncMessage;
  final CartPricingSummary? recalculatedPricing;
  final List<CartItem>? recalculatedItems;

  CartSyncState copyWith({
    Map<String, Product>? catalogProducts,
    Set<String>? priceChangedProductIds,
    Map<String, double>? oldPrices,
    Map<String, double>? newPrices,
    Set<String>? unavailableProductIds,
    bool? isSyncing,
    String? syncMessage,
    CartPricingSummary? recalculatedPricing,
    List<CartItem>? recalculatedItems,
  }) {
    return CartSyncState(
      catalogProducts: catalogProducts ?? this.catalogProducts,
      priceChangedProductIds: priceChangedProductIds ?? this.priceChangedProductIds,
      oldPrices: oldPrices ?? this.oldPrices,
      newPrices: newPrices ?? this.newPrices,
      unavailableProductIds: unavailableProductIds ?? this.unavailableProductIds,
      isSyncing: isSyncing ?? this.isSyncing,
      syncMessage: syncMessage,
      recalculatedPricing: recalculatedPricing ?? this.recalculatedPricing,
      recalculatedItems: recalculatedItems ?? this.recalculatedItems,
    );
  }
}

class CartSyncNotifier extends StateNotifier<CartSyncState> {
  CartSyncNotifier(this._ref) : super(const CartSyncState()) {
    _ref.listen<List<CartItem>>(
      cartControllerProvider,
      (previous, next) {
        if (state.catalogProducts.isNotEmpty) {
          updateQuantitiesLocal();
        }
      },
      fireImmediately: false,
    );
  }

  final Ref _ref;

  Future<void> syncCart() async {
    final session = _ref.read(currentSessionProvider);
    if (session == null) return;

    final rawItems = _ref.read(cartControllerProvider);
    if (rawItems.isEmpty) {
      state = const CartSyncState();
      return;
    }

    state = state.copyWith(isSyncing: true);

    try {
      final productIds = rawItems.map((item) => item.productId).toList();
      final latestProducts = await _ref.read(productRepositoryProvider).fetchProductsByIds(productIds);
      final latestProductsMap = {for (final p in latestProducts) p.id: p};

      final priceChanged = <String>{};
      final oldPrices = <String, double>{};
      final newPrices = <String, double>{};
      final unavailable = <String>{};
      final recalculatedItems = <CartItem>[];
      bool pricesUpdated = false;

      for (final item in rawItems) {
        final product = latestProductsMap[item.productId];
        if (product == null || !product.isAvailable || (product.trackStock && (product.stockQuantity ?? 0) <= 0)) {
          unavailable.add(item.productId);
          recalculatedItems.add(item);
        } else if (product.trackStock && (product.stockQuantity ?? 0) < item.quantity) {
          unavailable.add(item.productId);
          recalculatedItems.add(item);
        } else {
          final priceDiff = (item.price - product.price).abs() > 0.001 ||
                            (item.discountPrice - product.discountPrice).abs() > 0.001;
          if (priceDiff) {
            priceChanged.add(item.productId);
            oldPrices[item.productId] = item.effectivePrice;

            final updatedItem = item.copyWith(
              price: product.price,
              discountPrice: product.discountPrice,
              name: product.name,
              unit: product.unit,
              imageUrl: product.imageUrl,
            );
            newPrices[item.productId] = updatedItem.effectivePrice;
            recalculatedItems.add(updatedItem);
            pricesUpdated = true;
          } else {
            recalculatedItems.add(item);
          }
        }
      }

      final recalculatedPricing = CartPricingSummary.fromCartItems(recalculatedItems);

      state = CartSyncState(
        catalogProducts: latestProductsMap,
        priceChangedProductIds: priceChanged,
        oldPrices: oldPrices,
        newPrices: newPrices,
        unavailableProductIds: unavailable,
        isSyncing: false,
        syncMessage: pricesUpdated
            ? "Some product prices have changed.\nPlease review your cart before checkout."
            : null,
        recalculatedPricing: recalculatedPricing,
        recalculatedItems: recalculatedItems,
      );
    } catch (e, stack) {
      developer.log("Error syncing cart catalog", error: e, stackTrace: stack);
      state = state.copyWith(isSyncing: false);
    }
  }

  void updateQuantitiesLocal() {
    final rawItems = _ref.read(cartControllerProvider);
    if (rawItems.isEmpty) {
      state = const CartSyncState();
      return;
    }
    if (state.catalogProducts.isEmpty) return;

    final latestProductsMap = state.catalogProducts;
    final priceChanged = <String>{};
    final oldPrices = <String, double>{};
    final newPrices = <String, double>{};
    final unavailable = <String>{};
    final recalculatedItems = <CartItem>[];
    bool pricesUpdated = false;

    for (final item in rawItems) {
      final product = latestProductsMap[item.productId];
      if (product == null || !product.isAvailable || (product.trackStock && (product.stockQuantity ?? 0) <= 0)) {
        unavailable.add(item.productId);
        recalculatedItems.add(item);
      } else if (product.trackStock && (product.stockQuantity ?? 0) < item.quantity) {
        unavailable.add(item.productId);
        recalculatedItems.add(item);
      } else {
        final priceDiff = (item.price - product.price).abs() > 0.001 ||
                          (item.discountPrice - product.discountPrice).abs() > 0.001;
        if (priceDiff) {
          priceChanged.add(item.productId);
          oldPrices[item.productId] = item.effectivePrice;

          final updatedItem = item.copyWith(
            price: product.price,
            discountPrice: product.discountPrice,
            name: product.name,
            unit: product.unit,
            imageUrl: product.imageUrl,
          );
          newPrices[item.productId] = updatedItem.effectivePrice;
          recalculatedItems.add(updatedItem);
          pricesUpdated = true;
        } else {
          recalculatedItems.add(item);
        }
      }
    }

    final recalculatedPricing = CartPricingSummary.fromCartItems(recalculatedItems);

    state = state.copyWith(
      priceChangedProductIds: priceChanged,
      oldPrices: oldPrices,
      newPrices: newPrices,
      unavailableProductIds: unavailable,
      syncMessage: pricesUpdated
          ? "Some product prices have changed.\nPlease review your cart before checkout."
          : null,
      recalculatedPricing: recalculatedPricing,
      recalculatedItems: recalculatedItems,
    );
  }

  void clearMessage() {
    state = state.copyWith(syncMessage: null);
  }
}

final cartSyncProvider = StateNotifierProvider<CartSyncNotifier, CartSyncState>((ref) {
  return CartSyncNotifier(ref);
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
    if (product.trackStock && product.isStockEmpty) return;

    final previousState = state;
    final existingIndex = state.indexWhere((item) {
      return item.productId == product.id;
    });

    if (existingIndex == -1) {
      state = [
        ...state,
        CartItem.fromProduct(product),
      ];
      _ref.read(analyticsServiceProvider).logAddToCart(
        itemId: product.id,
        itemName: product.name,
        price: product.price,
        quantity: 1,
      );
      _persistAddProduct(product, previousState);
      return;
    }

    final nextItems = [...state];
    final existingItem = nextItems[existingIndex];
    if (product.trackStock &&
        existingItem.quantity >= (product.stockQuantity ?? 0)) {
      return;
    }

    nextItems[existingIndex] = existingItem.copyWith(
      name: product.name,
      price: product.price,
      discountPrice: product.discountPrice,
      unit: product.unit,
      imageUrl: product.imageUrl,
      quantity: existingItem.quantity + 1,
    );
    state = nextItems;
    _ref.read(analyticsServiceProvider).logAddToCart(
      itemId: product.id,
      itemName: product.name,
      price: product.price,
      quantity: 1,
    );
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
    final existingItem = _itemById(productId);
    if (existingItem == null) return;

    final productsAsync = _ref.read(
        productsByIdsProvider(ProductIdsRequest([productId])));
    final product = productsAsync.maybeWhen(
      data: (list) {
        final idx = list.indexWhere((p) => p.id == productId);
        return idx != -1 ? list[idx] : null;
      },
      orElse: () => null,
    );

    if (product != null &&
        product.trackStock &&
        existingItem.quantity >= (product.stockQuantity ?? 0)) {
      return;
    }

    state = [
      for (final item in state)
        if (item.productId == productId)
          item.copyWith(quantity: item.quantity + 1)
        else
          item,
    ];
    _ref.read(analyticsServiceProvider).logAddToCart(
      itemId: existingItem.productId,
      itemName: existingItem.name,
      price: existingItem.price,
      quantity: 1,
    );
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

    _ref.read(analyticsServiceProvider).logRemoveFromCart(
      itemId: existingItem.productId,
      itemName: existingItem.name,
      price: existingItem.price,
      quantity: 1,
    );

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
    final existingItem = _itemById(productId);
    state = [
      for (final item in state)
        if (item.productId != productId) item,
    ];
    if (existingItem != null) {
      _ref.read(analyticsServiceProvider).logRemoveFromCart(
        itemId: existingItem.productId,
        itemName: existingItem.name,
        price: existingItem.price,
        quantity: existingItem.quantity,
      );
    }
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

final activeAddressProvider = StateNotifierProvider<ActiveAddressNotifier, String>((ref) {
  return ActiveAddressNotifier(ref);
});

class ActiveAddressNotifier extends StateNotifier<String> {
  ActiveAddressNotifier(this._ref) : super('') {
    _ref.listen<AsyncValue<AppUser?>>(
      currentUserProfileProvider,
      (previous, next) {
        final user = next.value;
        if (user != null) {
          if (state.isEmpty || !user.savedAddresses.contains(state)) {
            state = user.address;
          }
        } else {
          state = '';
        }
      },
      fireImmediately: true,
    );
  }

  final Ref _ref;

  void selectAddress(String address) {
    state = address;
    final session = _ref.read(currentSessionProvider);
    final user = _ref.read(currentUserProfileProvider).value;
    if (session != null && user != null) {
      final updatedUser = user.copyWith(address: address);
      _ref.read(userRepositoryProvider).upsertUser(updatedUser);
    }
  }
}

