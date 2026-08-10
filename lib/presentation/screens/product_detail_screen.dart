import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/product.dart';
import '../providers/auth_providers.dart';
import '../providers/commerce_providers.dart';
import '../widgets/app_cached_network_image.dart';

import '../providers/catalog_providers.dart';
import '../providers/wishlist_provider.dart';
import '../../core/errors/app_error_handler.dart';
import '../navigation/customer_navigation_scope.dart';
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({
    super.key,
    required this.product,
  });

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);

    final realTimeProduct = ref.watch(productStreamProvider(product.id)).maybeWhen(
          data: (p) => p,
          orElse: () => null,
        ) ??
        product;

    final formattedQty = realTimeProduct.formattedQuantityUnit;

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: Text(realTimeProduct.name)),
        body: const Center(child: Text('Please login to add products')),
      );
    }

    final cartItems = ref.watch(cartItemsProvider);
    CartItem? cartItem;
    for (final item in cartItems) {
      if (item.productId == realTimeProduct.id) {
        cartItem = item;
        break;
      }
    }
    final quantity = cartItem?.quantity ?? 0;
    final cartController = ref.read(cartControllerProvider.notifier);

    final wishlistedProductIds = ref.watch(wishlistProductIdSetProvider(session.uid));
    final wishlistPendingProductIds = ref.watch(wishlistPendingProductIdsProvider(session.uid));
    
    final isWishlisted = wishlistedProductIds.contains(realTimeProduct.id);
    final isWishlistUpdating = wishlistPendingProductIds.contains(realTimeProduct.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(realTimeProduct.name),
        actions: [
          IconButton(
            icon: Icon(
              isWishlisted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isWishlisted ? AppColors.danger : null,
            ),
            onPressed: isWishlistUpdating ? null : () async {
              try {
                await ref.read(setProductWishlistedProvider)(
                  userId: session.uid,
                  productId: realTimeProduct.id,
                  wishlisted: !isWishlisted,
                );
              } catch (error) {
                if (!context.mounted) return;
                AppErrorHandler.showErrorSnackBar(
                  context,
                  error,
                  fallbackMessage: 'Could not update wishlist',
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 250,
            width: double.infinity,
            color: AppColors.softGreen,
            child: AppCachedNetworkImage(
              imageUrl: realTimeProduct.imageUrl,
              fit: BoxFit.cover,
              memCacheWidth: ProductDetailConfig.imageCacheWidth,
              maxWidthDiskCache: ProductDetailConfig.imageDiskCacheWidth,
              placeholder: const _ProductDetailImagePlaceholder(
                isLoading: true,
              ),
              errorPlaceholder: const _ProductDetailImagePlaceholder(),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    realTimeProduct.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '\u20B9${_formatPrice(realTimeProduct.sellingPrice)}',
                    style: const TextStyle(
                      fontSize: 18,
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (formattedQty.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      formattedQty,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                  if (realTimeProduct.isLowStock) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Only ${realTimeProduct.stockQuantity} left!',
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.danger,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Fresh and high quality product. Delivered fast to your home.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  if (quantity > 0)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: () {
                            cartController.decrement(realTimeProduct.id);
                          },
                        ),
                        Text(
                          '$quantity',
                          style: const TextStyle(fontSize: 16),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: (realTimeProduct.trackStock &&
                                  quantity >= (realTimeProduct.stockQuantity ?? 0))
                              ? null
                              : () {
                                  cartController.increment(realTimeProduct.id);
                                },
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: (!realTimeProduct.isAvailable || realTimeProduct.isStockEmpty)
                  ? null
                  : quantity > 0
                      ? () {
                          CustomerNavigationScope.openCart(context);
                        }
                      : () {
                          cartController.addProduct(realTimeProduct);
                        },
              child: Text(
                (!realTimeProduct.isAvailable || realTimeProduct.isStockEmpty)
                    ? 'Out of Stock'
                    : quantity > 0
                        ? '🛒 Go to Cart'
                        : 'Add to Cart',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrice(double price) {
    return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
  }
}

class _ProductDetailImagePlaceholder extends StatelessWidget {
  const _ProductDetailImagePlaceholder({this.isLoading = false});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.softGreen,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Icon(
                isLoading
                    ? Icons.local_grocery_store_rounded
                    : Icons.image_outlined,
                color: AppColors.primary,
                size: 34,
              ),
            ),
            const SizedBox(height: 12),
            if (isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.primary,
                ),
              )
            else
              const Text(
                'Image coming soon',
                style: TextStyle(
                  color: AppColors.mutedText,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ProductDetailConfig {
  const ProductDetailConfig._();

  static const imageCacheWidth = 900;
  static const imageDiskCacheWidth = 1200;
}
