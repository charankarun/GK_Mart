import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/product.dart';
import 'app_cached_network_image.dart';

class GkProductCard extends StatelessWidget {
  const GkProductCard({
    super.key,
    required this.product,
    required this.quantity,
    required this.onTap,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    required this.isWishlisted,
    required this.onToggleWishlist,
    this.isWishlistUpdating = false,
  });

  final Product product;
  final int quantity;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final bool isWishlisted;
  final VoidCallback onToggleWishlist;
  final bool isWishlistUpdating;

  @override
  Widget build(BuildContext context) {
    final discountPercent = _discountPercent(product);
    final hasDiscount = discountPercent > 0;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _ProductImage(imageUrl: product.imageUrl),
                  if (hasDiscount)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: _DiscountBadge(discountPercent: discountPercent),
                    ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: _WishlistButton(
                      isWishlisted: isWishlisted,
                      isLoading: isWishlistUpdating,
                      onPressed: onToggleWishlist,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 12,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (product.unit.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          product.unit,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.mutedText,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (product.trackStock &&
                          (product.stockQuantity ?? 0) <= 10 &&
                          (product.stockQuantity ?? 0) > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Only ${product.stockQuantity} left!',
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _PriceCol(product: product),
                          ),
                          _CartAction(
                            isAvailable: product.isAvailable && !product.isStockEmpty,
                            quantity: quantity,
                            onAdd: onAdd,
                            onIncrement: (product.trackStock && quantity >= (product.stockQuantity ?? 0)) ? null : onIncrement,
                            onDecrement: onDecrement,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(12),
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Center(
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(12),
          ),
          child: AppCachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            memCacheWidth: ProductCardConfig.imageMemCacheWidth,
            maxWidthDiskCache: ProductCardConfig.imageDiskCacheWidth,
            placeholder: const _ImagePlaceholder(),
            errorPlaceholder: const _ImagePlaceholder(),
          ),
        ),
      ),
    );
  }
}

class _WishlistButton extends StatelessWidget {
  const _WishlistButton({
    required this.isWishlisted,
    required this.isLoading,
    required this.onPressed,
  });

  final bool isWishlisted;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isWishlisted
          ? ProductCardText.removeFromWishlist
          : ProductCardText.addToWishlist,
      child: Material(
        color: Colors.white.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: isLoading ? null : onPressed,
          child: SizedBox(
            width: 28,
            height: 28,
            child: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(7),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isWishlisted
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color:
                        isWishlisted ? ProductCardColors.heart : AppColors.mutedText,
                    size: 16,
                  ),
          ),
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
          size: 28,
        ),
      ),
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge({required this.discountPercent});

  final int discountPercent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$discountPercent% OFF',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _PriceCol extends StatelessWidget {
  const _PriceCol({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final discountPercent = _discountPercent(product);
    final hasDiscount = discountPercent > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '\u20B9${_formatPrice(product.sellingPrice)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 14,
            height: 1.1,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (hasDiscount) ...[
          const SizedBox(height: 2),
          Text(
            '\u20B9${_formatPrice(product.price)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.mutedText,
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ],
      ],
    );
  }
}

class _CartAction extends StatelessWidget {
  const _CartAction({
    required this.isAvailable,
    required this.quantity,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
  });

  final bool isAvailable;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback? onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    if (!isAvailable) {
      return Container(
        width: 68,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: const Text(
          'Out of Stock',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.mutedText,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    if (quantity <= 0) {
      return SizedBox(
        width: 68,
        height: 30,
        child: OutlinedButton(
          onPressed: onAdd,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary, width: 1.2),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            elevation: 1,
            shadowColor: Colors.black.withValues(alpha: 0.1),
          ),
          child: const Text(
            'ADD',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }

    return Container(
      width: 68,
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _QuantityButton(icon: Icons.remove_rounded, onTap: onDecrement),
          Text(
            quantity.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          _QuantityButton(icon: Icons.add_rounded, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 22,
        height: 30,
        child: Icon(
          icon,
          color: onTap == null ? Colors.white.withValues(alpha: 0.4) : Colors.white,
          size: 14,
        ),
      ),
    );
  }
}

class ProductCardColors {
  const ProductCardColors._();

  static const heart = Color(0xFFE11D48);
}

class ProductCardText {
  const ProductCardText._();

  static const addToWishlist = 'Add to wishlist';
  static const removeFromWishlist = 'Remove from wishlist';
}

int _discountPercent(Product product) {
  if (product.discountPrice <= 0 ||
      product.price <= 0 ||
      product.discountPrice >= product.price) {
    return 0;
  }

  return (((product.price - product.discountPrice) / product.price) * 100)
      .round();
}

String _formatPrice(double price) {
  return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
}

class ProductCardConfig {
  const ProductCardConfig._();

  static const imageMemCacheWidth = 420;
  static const imageDiskCacheWidth = 640;
}
