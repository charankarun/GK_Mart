import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supermarket_app/domain/entities/cart_item.dart';
import 'package:supermarket_app/domain/entities/product.dart';
import 'package:supermarket_app/domain/repositories/cart_repository.dart';
import 'package:supermarket_app/domain/entities/auth_session.dart';
import 'package:supermarket_app/presentation/providers/commerce_providers.dart';
import 'package:supermarket_app/presentation/providers/repository_providers.dart';
import 'package:supermarket_app/presentation/providers/auth_providers.dart';

import 'package:supermarket_app/presentation/providers/catalog_providers.dart';

void main() {
  test('Product stock state behaves correctly based on trackStock toggle', () {
    const pNoTrack = Product(
      id: 'p-1',
      name: 'Bread',
      categoryId: 'bakery',
      price: 40,
      trackStock: false,
      stockQuantity: 0,
    );
    expect(pNoTrack.isStockTracked, false);
    expect(pNoTrack.isStockEmpty, false);
    expect(pNoTrack.isLowStock, false);

    const pTrackEmpty = Product(
      id: 'p-2',
      name: 'Milk',
      categoryId: 'dairy',
      price: 25,
      trackStock: true,
      stockQuantity: 0,
    );
    expect(pTrackEmpty.isStockTracked, true);
    expect(pTrackEmpty.isStockEmpty, true);
    expect(pTrackEmpty.isLowStock, false);

    const pTrackLow = Product(
      id: 'p-3',
      name: 'Butter',
      categoryId: 'dairy',
      price: 50,
      trackStock: true,
      stockQuantity: 4,
      lowStockThreshold: 5,
    );
    expect(pTrackLow.isStockTracked, true);
    expect(pTrackLow.isStockEmpty, false);
    expect(pTrackLow.isLowStock, true);
  });

  test('CartController blocks add and increment beyond stock quantity when trackStock is true', () async {
    final cartRepo = _FakeCartRepository();
    const product = Product(
      id: 'p-track-limit',
      name: 'Eggs',
      categoryId: 'dairy',
      price: 6,
      trackStock: true,
      stockQuantity: 2,
    );

    final container = ProviderContainer(
      overrides: [
        currentSessionProvider.overrideWithValue(
          const AuthSession(uid: 'user-1'),
        ),
        cartRepositoryProvider.overrideWithValue(cartRepo),
        productsByIdsProvider.overrideWith((ref, request) async {
          if (request.ids.contains(product.id)) {
            return [product];
          }
          return [];
        }),
      ],
    );
    addTearDown(container.dispose);

    // Keep productsByIdsProvider active so that it hydrates its value
    final sub = container.listen(productsByIdsProvider(ProductIdsRequest([product.id])), (_, __) {});
    addTearDown(sub.close);

    final cartController = container.read(cartControllerProvider.notifier);

    // Initial state
    expect(container.read(cartControllerProvider), isEmpty);

    // 1st add -> quantity = 1
    cartController.addProduct(product);
    expect(container.read(cartControllerProvider).first.quantity, 1);

    // 2nd add -> quantity = 2
    cartController.addProduct(product);
    expect(container.read(cartControllerProvider).first.quantity, 2);

    // 3rd add -> blocked! quantity remains 2
    cartController.addProduct(product);
    expect(container.read(cartControllerProvider).first.quantity, 2);

    // Pump the event loop to ensure productsByIdsProvider hydraton completes
    await Future<void>.delayed(Duration.zero);

    // increment -> blocked! quantity remains 2
    cartController.increment('p-track-limit');
    expect(container.read(cartControllerProvider).first.quantity, 2);
  });
}

class _FakeCartRepository implements CartRepository {
  @override
  Stream<List<CartItem>> watchCart(String userId) => Stream.empty();

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
