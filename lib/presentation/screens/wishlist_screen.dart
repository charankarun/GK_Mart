import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/product.dart';
import '../providers/auth_providers.dart';
import '../providers/commerce_providers.dart';
import '../providers/wishlist_provider.dart';

class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(WishlistText.title)),
        body: const Center(child: Text(WishlistText.loginRequired)),
      );
    }

    final wishlistAsync = ref.watch(wishlistProductsProvider(session.uid));

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(title: const Text(WishlistText.title)),
      body: wishlistAsync.when(
        data: (products) {
          if (products.isEmpty) {
            return const _EmptyWishlist();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final product = products[index];

              return _WishlistProductCard(
                product: product,
                onRemove: () {
                  _removeProduct(
                    context: context,
                    ref: ref,
                    userId: session.uid,
                    productId: product.id,
                  );
                },
                onMoveToCart: !product.isAvailable
                    ? null
                    : () {
                        _moveToCart(
                          context: context,
                          ref: ref,
                          userId: session.uid,
                          product: product,
                        );
                      },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text(WishlistText.loadError),
        ),
      ),
    );
  }

  Future<void> _removeProduct({
    required BuildContext context,
    required WidgetRef ref,
    required String userId,
    required String productId,
  }) async {
    try {
      await ref.read(removeWishlistProductProvider)(
        userId: userId,
        productId: productId,
      );
    } catch (_) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(WishlistText.removeError)),
      );
    }
  }

  Future<void> _moveToCart({
    required BuildContext context,
    required WidgetRef ref,
    required String userId,
    required Product product,
  }) async {
    ref.read(cartControllerProvider.notifier).addProduct(product);

    try {
      await ref.read(removeWishlistProductProvider)(
        userId: userId,
        productId: product.id,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(WishlistText.movedToCart)),
      );
    } catch (_) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(WishlistText.moveError)),
      );
    }
  }
}

class _WishlistProductCard extends StatelessWidget {
  const _WishlistProductCard({
    required this.product,
    required this.onRemove,
    required this.onMoveToCart,
  });

  final Product product;
  final VoidCallback onRemove;
  final VoidCallback? onMoveToCart;

  @override
  Widget build(BuildContext context) {
    final hasDiscount =
        product.discountPrice > 0 && product.discountPrice < product.price;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                _WishlistProductImage(imageUrl: product.imageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          height: 1.18,
                        ),
                      ),
                      if (product.unit.trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          product.unit,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '\u20B9${_formatPrice(product.sellingPrice)}',
                            style: const TextStyle(
                              color: Color(0xFF166534),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (hasDiscount) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '\u20B9${_formatPrice(product.price)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Tooltip(
                  message: WishlistText.remove,
                  child: IconButton.outlined(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                    color: const Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: onMoveToCart,
                      icon: const Icon(Icons.shopping_cart_checkout, size: 18),
                      label: Text(
                        onMoveToCart == null
                            ? WishlistText.outOfStock
                            : WishlistText.moveToCart,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WishlistProductImage extends StatelessWidget {
  const _WishlistProductImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.image, color: Colors.black45),
    );

    if (imageUrl.trim().isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        width: 82,
        height: 82,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}

class _EmptyWishlist extends StatelessWidget {
  const _EmptyWishlist();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_border,
                color: Color(0xFF2563EB),
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              WishlistText.emptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              WishlistText.emptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatPrice(double price) {
  return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
}

class WishlistText {
  const WishlistText._();

  static const title = 'My Wishlist';
  static const loginRequired = 'Please login to view your wishlist';
  static const emptyTitle = 'Your wishlist is empty';
  static const emptySubtitle = 'Products you save will appear here.';
  static const loadError = 'Unable to load wishlist';
  static const remove = 'Remove item';
  static const removeError = 'Unable to remove item';
  static const moveToCart = 'Move to Cart';
  static const movedToCart = 'Moved to cart';
  static const moveError = 'Added to cart, but could not remove from wishlist';
  static const outOfStock = 'Out of Stock';
}
