import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_app/domain/entities/app_user.dart';
import 'package:supermarket_app/domain/entities/auth_session.dart';
import 'package:supermarket_app/domain/entities/cart_item.dart';
import 'package:supermarket_app/domain/entities/product.dart';
import 'package:supermarket_app/domain/entities/product_page.dart';
import 'package:supermarket_app/domain/entities/product_image_upload.dart';
import 'package:supermarket_app/domain/entities/product_stats.dart';
import 'package:supermarket_app/domain/repositories/cart_repository.dart';
import 'package:supermarket_app/domain/repositories/product_repository.dart';
import 'package:supermarket_app/domain/repositories/user_repository.dart';
import 'package:supermarket_app/domain/repositories/wishlist_repository.dart';
import 'package:supermarket_app/presentation/providers/auth_providers.dart';
import 'package:supermarket_app/presentation/providers/commerce_providers.dart';
import 'package:supermarket_app/presentation/providers/wishlist_provider.dart';
import 'package:supermarket_app/presentation/providers/repository_providers.dart';

void main() {
  test('activeAddressProvider hydrates from profile and updates on selection', () async {
    final userRepo = _FakeUserRepository(
      user: const AppUser(
        uid: 'user-1',
        address: '123 Main St',
        addresses: ['123 Main St', '456 Oak Rd'],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        currentSessionProvider.overrideWithValue(
          const AuthSession(uid: 'user-1', email: 'user@example.com'),
        ),
        userRepositoryProvider.overrideWithValue(userRepo),
      ],
    );
    addTearDown(container.dispose);

    // Keep activeAddressProvider and profile active by listening
    final subProfile = container.listen(currentUserProfileProvider, (_, __) {});
    final subAddress = container.listen(activeAddressProvider, (_, __) {});

    // Wait for stream to emit value
    for (int i = 0; i < 50; i++) {
      if (container.read(activeAddressProvider) == '123 Main St') break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // Initial state should load from user profile address
    expect(container.read(activeAddressProvider), '123 Main St');

    // Selecting a new address updates the provider state and calls upsertUser
    container.read(activeAddressProvider.notifier).selectAddress('456 Oak Rd');
    expect(container.read(activeAddressProvider), '456 Oak Rd');
    expect(userRepo.lastUpsertedUser?.address, '456 Oak Rd');

    subProfile.close();
    subAddress.close();
  });

  test('cart and wishlist filter out deleted catalog products', () async {
    final userRepo = _FakeUserRepository(
      user: const AppUser(uid: 'user-1'),
    );
    final productRepo = _FakeProductRepository(
      existingProducts: [_productA], // Only product-a exists, product-b is deleted/missing
    );
    final wishlistRepo = _FakeWishlistRepository(
      productIds: ['product-a', 'product-b'],
    );
    final cartRepo = _FakeCartRepository(
      items: [
        CartItem.fromProduct(_productA, quantity: 1),
        CartItem.fromProduct(_productB, quantity: 2),
      ],
    );

    final container = ProviderContainer(
      overrides: [
        currentSessionProvider.overrideWithValue(
          const AuthSession(uid: 'user-1'),
        ),
        userRepositoryProvider.overrideWithValue(userRepo),
        productRepositoryProvider.overrideWithValue(productRepo),
        wishlistRepositoryProvider.overrideWithValue(wishlistRepo),
        cartRepositoryProvider.overrideWithValue(cartRepo),
      ],
    );
    addTearDown(container.dispose);

    // Listen to activate the lazy providers and stream pipelines
    final subProfile = container.listen(currentUserProfileProvider, (_, __) {});
    final subCart = container.listen(cartItemsProvider, (_, __) {});
    final subWishlist = container.listen(wishlistProductIdSetProvider('user-1'), (_, __) {});

    // Wait for profile to load
    for (int i = 0; i < 50; i++) {
      if (container.read(currentUserProfileProvider).hasValue) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // Wait for cart controller to hydrate
    while (container.read(cartControllerProvider).isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // Wait for cart items provider to apply the catalog filter (from 2 down to 1 item)
    for (int i = 0; i < 50; i++) {
      if (container.read(cartItemsProvider).length == 1) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // Cart items should only contain product-a, not product-b
    final cartItems = container.read(cartItemsProvider);
    expect(cartItems.length, 1);
    expect(cartItems.first.productId, 'product-a');
    expect(container.read(cartItemCountProvider), 1);

    // Wishlist set should only contain product-a, not product-b
    final wishlistSet = container.read(wishlistProductIdSetProvider('user-1'));
    expect(wishlistSet, {'product-a'});
    expect(container.read(wishlistCountProvider('user-1')), 1);

    subProfile.close();
    subCart.close();
    subWishlist.close();
  });
}

const _productA = Product(
  id: 'product-a',
  name: 'Apple',
  price: 50,
  categoryId: 'fruits',
);

const _productB = Product(
  id: 'product-b',
  name: 'Banana',
  price: 30,
  categoryId: 'fruits',
);

class _FakeUserRepository implements UserRepository {
  _FakeUserRepository({AppUser? user}) : _user = user;

  final AppUser? _user;
  AppUser? lastUpsertedUser;

  @override
  Stream<AppUser?> watchUser(String uid) {
    late StreamController<AppUser?> controller;
    controller = StreamController<AppUser?>(
      onListen: () {
        controller.add(_user);
      },
    );
    return controller.stream;
  }

  @override
  Future<AppUser?> getUser(String uid) async => _user;

  @override
  Future<void> upsertUser(AppUser user) async {
    lastUpsertedUser = user;
  }

  @override
  Future<void> updateProfile({required String uid, required String name, required String phone}) async {}

  @override
  Future<void> updateAddress({required String uid, required String address}) async {}
}

class _FakeProductRepository implements ProductRepository {
  _FakeProductRepository({required List<Product> existingProducts})
      : _products = existingProducts;

  final List<Product> _products;

  @override
  Stream<List<Product>> watchProducts({int limit = 40}) {
    late StreamController<List<Product>> controller;
    controller = StreamController<List<Product>>(
      onListen: () {
        controller.add(_products);
      },
    );
    return controller.stream;
  }

  @override
  Future<List<Product>> fetchProductsByIds(List<String> productIds) async {
    return _products.where((p) => productIds.contains(p.id)).toList();
  }

  @override
  Future<ProductPage> fetchProductsPage({required int limit, ProductPageCursor? cursor}) async {
    return ProductPage(products: _products, hasMore: false);
  }

  @override
  Future<ProductPage> fetchProductsByCategoryPage({
    required String categoryId,
    String? categoryName,
    required int limit,
    ProductPageCursor? cursor,
  }) async {
    return ProductPage(products: _products, hasMore: false);
  }

  @override
  Future<ProductPage> fetchProductSearchPage({
    required String query,
    required int limit,
    ProductPageCursor? cursor,
  }) async {
    return ProductPage(products: _products, hasMore: false);
  }

  @override
  Future<void> addProduct(Product product) async {}

  @override
  Future<void> updateProduct(Product product) async {}

  @override
  Future<void> updateProductAvailability({required String productId, required bool isAvailable}) async {}

  @override
  Future<void> updateProductStock({required String productId, required int stockQuantity}) async {}

  @override
  Future<String> uploadProductImage(ProductImageUpload upload) async => '';

  @override
  Future<void> deleteProduct(String productId) async {}

  @override
  Future<ProductStats> fetchInventoryStats() async {
    return ProductStats.fromProducts(_products);
  }
}

class _FakeWishlistRepository implements WishlistRepository {
  _FakeWishlistRepository({required List<String> productIds}) : _productIds = productIds;

  final List<String> _productIds;

  @override
  Stream<List<String>> watchWishlistProductIds(String userId) {
    late StreamController<List<String>> controller;
    controller = StreamController<List<String>>(
      onListen: () {
        controller.add(_productIds);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> addProduct({required String userId, required String productId}) async {}

  @override
  Future<void> removeProduct({required String userId, required String productId}) async {}

  @override
  Future<void> setWishlisted({required String userId, required String productId, required bool wishlisted}) async {}
}

class _FakeCartRepository implements CartRepository {
  _FakeCartRepository({required List<CartItem> items}) : _items = items;

  final List<CartItem> _items;

  @override
  Stream<List<CartItem>> watchCart(String userId) {
    late StreamController<List<CartItem>> controller;
    controller = StreamController<List<CartItem>>(
      onListen: () {
        controller.add(_items);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> addProduct({required String userId, required Product product}) async {}

  @override
  Future<void> setQuantity({required String userId, required CartItem item, required int quantity}) async {}

  @override
  Future<void> incrementItem({required String userId, required String productId}) async {}

  @override
  Future<void> decrementItem({required String userId, required String productId}) async {}

  @override
  Future<void> removeItem({required String userId, required String productId}) async {}

  @override
  Future<void> clearCart(String userId) async {}
}
