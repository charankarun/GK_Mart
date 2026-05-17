import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error_handler.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/product.dart';
import '../navigation/customer_navigation_scope.dart';
import '../providers/auth_providers.dart';
import '../providers/commerce_providers.dart';
import '../providers/wishlist_provider.dart';
import '../widgets/app_cached_network_image.dart';
import '../widgets/app_state_widgets.dart';

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
    final pendingProductIds = ref.watch(
      wishlistPendingProductIdsProvider(session.uid),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text(WishlistText.title)),
      body: wishlistAsync.when(
        data: (products) {
          if (products.isEmpty) {
            return const _EmptyWishlist();
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final product = products[index];
              final isPending = pendingProductIds.contains(product.id);

              return _WishlistProductCard(
                product: product,
                isRemoving: isPending,
                onRemove: isPending
                    ? null
                    : () {
                        _removeProduct(
                          context: context,
                          ref: ref,
                          userId: session.uid,
                          productId: product.id,
                        );
                      },
                onAddToCart: !product.isAvailable
                    ? null
                    : () {
                        _addToCart(
                          context: context,
                          ref: ref,
                          product: product,
                        );
                      },
              );
            },
          );
        },
        loading: () => const AppLoadingState(),
        error: (error, _) => AppRetryState(
          icon: Icons.error_outline_rounded,
          title: WishlistText.loadError,
          message: AppErrorHandler.messageFor(
            error,
            fallback: WishlistText.loadErrorSubtitle,
          ),
          onRetry: () =>
              ref.invalidate(wishlistProductIdsProvider(session.uid)),
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
    } catch (error) {
      if (!context.mounted) return;

      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: WishlistText.removeError,
      );
    }
  }

  void _addToCart({
    required BuildContext context,
    required WidgetRef ref,
    required Product product,
  }) {
    ref.read(cartControllerProvider.notifier).addProduct(product);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(WishlistText.addedToCart)),
    );
  }
}

class _WishlistProductCard extends StatelessWidget {
  const _WishlistProductCard({
    required this.product,
    required this.isRemoving,
    required this.onRemove,
    required this.onAddToCart,
  });

  final Product product;
  final bool isRemoving;
  final VoidCallback? onRemove;
  final VoidCallback? onAddToCart;

  @override
  Widget build(BuildContext context) {
    final hasDiscount =
        product.discountPrice > 0 && product.discountPrice < product.price;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WishlistProductImage(imageUrl: product.imageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 15,
                                height: 1.18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StockBadge(isAvailable: product.isAvailable),
                        ],
                      ),
                      if (product.unit.trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          product.unit,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.mutedText,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 9),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            '\u20B9${_formatPrice(product.sellingPrice)}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (hasDiscount)
                            Text(
                              '\u20B9${_formatPrice(product.price)}',
                              style: const TextStyle(
                                color: AppColors.mutedText,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
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
                  child: SizedBox(
                    height: 42,
                    width: 48,
                    child: OutlinedButton(
                      onPressed: onRemove,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: WishlistColors.remove,
                        side: const BorderSide(color: WishlistColors.remove),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                      ),
                      child: isRemoving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor:
                            AppColors.mutedText.withValues(alpha: 0.22),
                        disabledForegroundColor: AppColors.mutedText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                      ),
                      onPressed: onAddToCart,
                      icon: const Icon(
                        Icons.add_shopping_cart_rounded,
                        size: 18,
                      ),
                      label: Text(
                        onAddToCart == null
                            ? WishlistText.outOfStock
                            : WishlistText.addToCart,
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
    final trimmedUrl = imageUrl.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: SizedBox(
        width: 92,
        height: 92,
        child: AppCachedNetworkImage(
          imageUrl: trimmedUrl,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          memCacheWidth: WishlistConfig.productImageCacheExtent,
          memCacheHeight: WishlistConfig.productImageCacheExtent,
          maxWidthDiskCache: WishlistConfig.productImageDiskCacheExtent,
          maxHeightDiskCache: WishlistConfig.productImageDiskCacheExtent,
          placeholder: const _ImagePlaceholder(),
          errorPlaceholder: const _ImagePlaceholder(),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: AppColors.softGreen),
      child: Center(
        child: Icon(
          Icons.local_grocery_store_rounded,
          color: AppColors.primary,
          size: 30,
        ),
      ),
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.isAvailable});

  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isAvailable ? AppColors.softGreen : WishlistColors.outStockBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isAvailable ? WishlistText.available : WishlistText.outOfStock,
        style: TextStyle(
          color: isAvailable ? AppColors.primary : WishlistColors.outStockText,
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
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
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: AppColors.softGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_border_rounded,
                color: AppColors.primary,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              WishlistText.emptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _openHome(context),
                icon: const Icon(Icons.storefront_rounded),
                label: const Text(WishlistText.browseProducts),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openHome(BuildContext context) {
    CustomerNavigationScope.openHome(context);
  }
}

String _formatPrice(double price) {
  return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
}

class WishlistColors {
  const WishlistColors._();

  static const remove = Color(0xFFDC2626);
  static const outStockBg = Color(0xFFF3F4F6);
  static const outStockText = Color(0xFF4B5563);
}

class WishlistConfig {
  const WishlistConfig._();

  static const productImageCacheExtent = 190;
  static const productImageDiskCacheExtent = 260;
}

class WishlistText {
  const WishlistText._();

  static const title = 'My Wishlist';
  static const loginRequired = 'Please login to view your wishlist';
  static const emptyTitle = 'Your wishlist is empty';
  static const emptySubtitle = 'Products you save will appear here.';
  static const browseProducts = 'Browse Products';
  static const loadError = 'Unable to load wishlist';
  static const loadErrorSubtitle = 'Please try again in a moment.';
  static const remove = 'Remove item';
  static const removeError = 'Unable to remove item';
  static const addToCart = 'Add to Cart';
  static const addedToCart = 'Added to cart';
  static const outOfStock = 'Out of Stock';
  static const available = 'In Stock';
}
