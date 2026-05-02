import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/entities/cart_item.dart';
import '../../domain/entities/product.dart';

final cartControllerProvider =
    StateNotifierProvider<CartController, List<CartItem>>((ref) {
  return CartController();
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

class CartController extends StateNotifier<List<CartItem>> {
  CartController() : super(const <CartItem>[]);

  void addProduct(Product product) {
    final existingIndex = state.indexWhere((item) {
      return item.productId == product.id;
    });

    if (existingIndex == -1) {
      state = [
        ...state,
        CartItem.fromProduct(product),
      ];
      return;
    }

    final nextItems = [...state];
    final existingItem = nextItems[existingIndex];
    nextItems[existingIndex] = existingItem.copyWith(
      price: product.price,
      discountPrice: product.discountPrice,
      imageUrl: product.imageUrl,
      quantity: existingItem.quantity + 1,
    );
    state = nextItems;
  }

  void increment(String productId) {
    state = [
      for (final item in state)
        if (item.productId == productId)
          item.copyWith(quantity: item.quantity + 1)
        else
          item,
    ];
  }

  void decrement(String productId) {
    state = [
      for (final item in state)
        if (item.productId != productId)
          item
        else if (item.quantity > 1)
          item.copyWith(quantity: item.quantity - 1),
    ];
  }

  void remove(String productId) {
    state = [
      for (final item in state)
        if (item.productId != productId) item,
    ];
  }

  void clear() {
    state = const <CartItem>[];
  }
}
