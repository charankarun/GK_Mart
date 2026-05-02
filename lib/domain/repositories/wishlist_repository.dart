abstract class WishlistRepository {
  Stream<List<String>> watchWishlistProductIds(String userId);

  Future<void> addProduct({
    required String userId,
    required String productId,
  });

  Future<void> removeProduct({
    required String userId,
    required String productId,
  });

  Future<void> setWishlisted({
    required String userId,
    required String productId,
    required bool wishlisted,
  });
}
