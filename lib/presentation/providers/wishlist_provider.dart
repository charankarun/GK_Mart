import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/product.dart';
import 'repository_providers.dart';

final wishlistProductIdsProvider =
    StreamProvider.family<List<String>, String>((ref, userId) {
  return ref.watch(wishlistRepositoryProvider).watchWishlistProductIds(userId);
});

final wishlistProductIdSetProvider = Provider.family<Set<String>, String>(
  (ref, userId) {
    return ref.watch(wishlistProductIdsProvider(userId)).maybeWhen(
          data: (productIds) => productIds.toSet(),
          orElse: () => const <String>{},
        );
  },
);

final wishlistCountProvider = Provider.family<int, String>((ref, userId) {
  return ref.watch(wishlistProductIdsProvider(userId)).maybeWhen(
        data: (productIds) => productIds.length,
        orElse: () => 0,
      );
});

final wishlistProductsProvider =
    Provider.family<AsyncValue<List<Product>>, String>((ref, userId) {
  final productIdsAsync = ref.watch(wishlistProductIdsProvider(userId));

  return productIdsAsync.when(
    data: (productIds) {
      if (productIds.isEmpty) {
        return const AsyncData(<Product>[]);
      }

      return ref.watch(
        _productsByIdsProvider(_ProductIdsRequest(productIds)),
      );
    },
    loading: () => const AsyncLoading<List<Product>>(),
    error: (error, stackTrace) => AsyncError<List<Product>>(error, stackTrace),
  );
});

typedef SetProductWishlisted = Future<void> Function({
  required String userId,
  required String productId,
  required bool wishlisted,
});

final setProductWishlistedProvider = Provider<SetProductWishlisted>((ref) {
  return ({
    required String userId,
    required String productId,
    required bool wishlisted,
  }) {
    return ref.read(wishlistRepositoryProvider).setWishlisted(
          userId: userId,
          productId: productId,
          wishlisted: wishlisted,
        );
  };
});

typedef RemoveWishlistProduct = Future<void> Function({
  required String userId,
  required String productId,
});

final removeWishlistProductProvider = Provider<RemoveWishlistProduct>((ref) {
  return ({
    required String userId,
    required String productId,
  }) {
    return ref.read(wishlistRepositoryProvider).removeProduct(
          userId: userId,
          productId: productId,
        );
  };
});

final _productsByIdsProvider =
    StreamProvider.family<List<Product>, _ProductIdsRequest>((ref, request) {
  return ref.watch(productRepositoryProvider).watchProductsByIds(request.ids);
});

class _ProductIdsRequest {
  _ProductIdsRequest(List<String> ids) : ids = List.unmodifiable(ids);

  final List<String> ids;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _ProductIdsRequest || ids.length != other.ids.length) {
      return false;
    }

    for (var index = 0; index < ids.length; index += 1) {
      if (ids[index] != other.ids[index]) return false;
    }

    return true;
  }

  @override
  int get hashCode => Object.hashAll(ids);
}
