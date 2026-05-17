import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/entities/product.dart';
import 'repository_providers.dart';

final wishlistProductIdsProvider =
    StreamProvider.family<List<String>, String>((ref, userId) {
  return ref.watch(wishlistRepositoryProvider).watchWishlistProductIds(userId);
});

final _wishlistOptimisticChangesProvider =
    StateProvider.family<Map<String, bool>, String>((ref, userId) {
  return const <String, bool>{};
});

final wishlistPendingProductIdsProvider =
    StateProvider.family<Set<String>, String>((ref, userId) {
  return const <String>{};
});

final wishlistProductIdSetProvider = Provider.family<Set<String>, String>(
  (ref, userId) {
    final productIds = ref.watch(wishlistProductIdsProvider(userId)).maybeWhen(
          data: (productIds) => productIds.toSet(),
          orElse: () => <String>{},
        );
    final optimisticChanges = ref.watch(
      _wishlistOptimisticChangesProvider(userId),
    );

    for (final change in optimisticChanges.entries) {
      if (change.value) {
        productIds.add(change.key);
      } else {
        productIds.remove(change.key);
      }
    }

    return productIds;
  },
);

final wishlistCountProvider = Provider.family<int, String>((ref, userId) {
  return ref.watch(wishlistProductIdSetProvider(userId)).length;
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
  }) async {
    final normalizedProductId = productId.trim();
    if (normalizedProductId.isEmpty) {
      throw ArgumentError.value(productId, 'productId', 'Required');
    }

    final pendingProvider = wishlistPendingProductIdsProvider(userId);
    final pendingProductIds = ref.read(pendingProvider);
    if (pendingProductIds.contains(normalizedProductId)) return;

    ref.read(pendingProvider.notifier).state = {
      ...pendingProductIds,
      normalizedProductId,
    };

    final changesProvider = _wishlistOptimisticChangesProvider(userId);
    final previousChanges = ref.read(changesProvider);
    ref.read(changesProvider.notifier).state = {
      ...previousChanges,
      normalizedProductId: wishlisted,
    };

    var didWrite = false;

    try {
      await ref.read(wishlistRepositoryProvider).setWishlisted(
            userId: userId,
            productId: normalizedProductId,
            wishlisted: wishlisted,
          );
      didWrite = true;
    } catch (_) {
      _restoreOptimisticChange(
        ref: ref,
        provider: changesProvider,
        productId: normalizedProductId,
        desiredWishlisted: wishlisted,
        previousChanges: previousChanges,
      );
      rethrow;
    } finally {
      if (didWrite) {
        _clearOptimisticChange(
          ref: ref,
          provider: changesProvider,
          productId: normalizedProductId,
          desiredWishlisted: wishlisted,
        );
      }
      _clearPendingProduct(
        ref: ref,
        provider: pendingProvider,
        productId: normalizedProductId,
      );
    }
  };
});

void _restoreOptimisticChange({
  required Ref ref,
  required StateProvider<Map<String, bool>> provider,
  required String productId,
  required bool desiredWishlisted,
  required Map<String, bool> previousChanges,
}) {
  final currentChanges = ref.read(provider);
  if (currentChanges[productId] != desiredWishlisted) return;

  final restoredChanges = {...currentChanges};
  final previousValue = previousChanges[productId];
  if (previousValue == null) {
    restoredChanges.remove(productId);
  } else {
    restoredChanges[productId] = previousValue;
  }

  ref.read(provider.notifier).state = restoredChanges;
}

void _clearOptimisticChange({
  required Ref ref,
  required StateProvider<Map<String, bool>> provider,
  required String productId,
  required bool desiredWishlisted,
}) {
  final currentChanges = ref.read(provider);
  if (currentChanges[productId] != desiredWishlisted) return;

  final nextChanges = {...currentChanges}..remove(productId);
  ref.read(provider.notifier).state = nextChanges;
}

void _clearPendingProduct({
  required Ref ref,
  required StateProvider<Set<String>> provider,
  required String productId,
}) {
  final currentProductIds = ref.read(provider);
  if (!currentProductIds.contains(productId)) return;

  ref.read(provider.notifier).state = {
    for (final currentProductId in currentProductIds)
      if (currentProductId != productId) currentProductId,
  };
}

typedef RemoveWishlistProduct = Future<void> Function({
  required String userId,
  required String productId,
});

final removeWishlistProductProvider = Provider<RemoveWishlistProduct>((ref) {
  return ({
    required String userId,
    required String productId,
  }) {
    return ref.read(setProductWishlistedProvider)(
      userId: userId,
      productId: productId,
      wishlisted: false,
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
