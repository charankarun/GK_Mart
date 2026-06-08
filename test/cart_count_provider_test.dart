import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_app/domain/entities/auth_session.dart';
import 'package:supermarket_app/domain/entities/cart_item.dart';
import 'package:supermarket_app/domain/entities/product.dart';
import 'package:supermarket_app/domain/repositories/cart_repository.dart';
import 'package:supermarket_app/presentation/providers/auth_providers.dart';
import 'package:supermarket_app/presentation/providers/commerce_providers.dart';
import 'package:supermarket_app/presentation/providers/repository_providers.dart';
import 'package:supermarket_app/services/analytics_service.dart';

void main() {
  test('cart count updates immediately after addProduct calls', () async {
    final repository = _FakeCartRepository();
    final container = ProviderContainer(
      overrides: [
        currentSessionProvider.overrideWith((ref) {
          return const AuthSession(uid: 'customer-1');
        }),
        cartRepositoryProvider.overrideWith((ref) => repository),
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(cartItemCountProvider), 0);

    container.read(cartControllerProvider.notifier).addProduct(_productA);
    expect(container.read(cartItemCountProvider), 1);

    container.read(cartControllerProvider.notifier).addProduct(_productA);
    expect(container.read(cartItemCountProvider), 2);

    container.read(cartControllerProvider.notifier).addProduct(_productB);
    expect(container.read(cartItemCountProvider), 3);

    await repository.flushPendingWrites();
    expect(repository.persistedQuantities, {
      'product-a': 2,
      'product-b': 1,
    });
  });

  test('cart count hydrates from persisted cart stream on startup', () async {
    final repository = _FakeCartRepository(
      seededCart: {
        'product-a': CartItem.fromProduct(_productA, quantity: 2),
        'product-b': CartItem.fromProduct(_productB, quantity: 1),
      },
    );
    final container = ProviderContainer(
      overrides: [
        currentSessionProvider.overrideWith((ref) {
          return const AuthSession(uid: 'customer-1');
        }),
        cartRepositoryProvider.overrideWith((ref) => repository),
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(cartItemCountProvider), 0);

    await Future<void>.delayed(Duration.zero);

    expect(container.read(cartItemCountProvider), 3);
  });
}

const _productA = Product(
  id: 'product-a',
  name: 'Rice',
  categoryId: 'grocery',
  price: 100,
  unit: '1 kg',
);

const _productB = Product(
  id: 'product-b',
  name: 'Dal',
  categoryId: 'grocery',
  price: 80,
  unit: '1 kg',
);

class _FakeCartRepository implements CartRepository {
  _FakeCartRepository({Map<String, CartItem>? seededCart})
      : _seededCart = seededCart ?? const <String, CartItem>{};

  final Map<String, CartItem> _seededCart;
  final Map<String, int> persistedQuantities = <String, int>{};
  final List<Future<void>> _pendingWrites = <Future<void>>[];

  @override
  Stream<List<CartItem>> watchCart(String userId) {
    return Stream<List<CartItem>>.value(_seededCart.values.toList());
  }

  @override
  Future<void> addProduct({
    required String userId,
    required Product product,
  }) {
    final write = Future<void>.microtask(() {
      persistedQuantities.update(
        product.id,
        (quantity) => quantity + 1,
        ifAbsent: () => 1,
      );
    });
    _pendingWrites.add(write);
    return write;
  }

  Future<void> flushPendingWrites() async {
    await Future.wait(_pendingWrites);
  }

  @override
  Future<void> clearCart(String userId) async {
    persistedQuantities.clear();
  }

  @override
  Future<void> decrementItem({
    required String userId,
    required String productId,
  }) async {
    final quantity = persistedQuantities[productId] ?? 0;
    if (quantity <= 1) {
      persistedQuantities.remove(productId);
      return;
    }
    persistedQuantities[productId] = quantity - 1;
  }

  @override
  Future<void> incrementItem({
    required String userId,
    required String productId,
  }) async {
    persistedQuantities.update(
      productId,
      (quantity) => quantity + 1,
      ifAbsent: () => 1,
    );
  }

  @override
  Future<void> removeItem({
    required String userId,
    required String productId,
  }) async {
    persistedQuantities.remove(productId);
  }

  @override
  Future<void> setQuantity({
    required String userId,
    required CartItem item,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      persistedQuantities.remove(item.productId);
      return;
    }
    persistedQuantities[item.productId] = quantity;
  }
}

class FakeAnalyticsService implements AnalyticsService {
  @override
  dynamic get _analytics => throw UnimplementedError();

  @override
  Future<void> logLogin(String method) async {}

  @override
  Future<void> logAddToCart({
    required String itemId,
    required String itemName,
    required double price,
    required int quantity,
  }) async {}

  @override
  Future<void> logRemoveFromCart({
    required String itemId,
    required String itemName,
    required double price,
    required int quantity,
  }) async {}

  @override
  Future<void> logBeginCheckout({
    required double value,
    required int totalItems,
  }) async {}

  @override
  Future<void> logPurchaseAttempt({
    required String orderId,
    required double value,
  }) async {}
}
