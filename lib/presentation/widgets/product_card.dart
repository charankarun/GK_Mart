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
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _ProductImage(imageUrl: product.imageUrl),
                  if (hasDiscount)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _DiscountBadge(discountPercent: discountPercent),
                    ),
                  Positioned(
                    right: 8,
                    top: 8,
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
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          height: 1.12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      _PriceRow(product: product),
                      const SizedBox(height: 7),
                      _CartAction(
                        isAvailable: product.isAvailable,
                        quantity: quantity,
                        onAdd: onAdd,
                        onIncrement: onIncrement,
                        onDecrement: onDecrement,
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
    final url = imageUrl.trim().isEmpty
        ? ProductCardAssets.fallbackProductImage
        : imageUrl.trim();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadii.lg),
      ),
      child: AspectRatio(
        aspectRatio: 1.62,
        child: AppCachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          memCacheWidth: ProductCardConfig.imageMemCacheWidth,
          maxWidthDiskCache: ProductCardConfig.imageDiskCacheWidth,
          placeholder: const _ImagePlaceholder(),
          errorPlaceholder: const _ImagePlaceholder(),
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
        color: AppColors.card.withValues(alpha: 0.94),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: isLoading ? null : onPressed,
          child: SizedBox(
            width: 34,
            height: 34,
            child: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isWishlisted
                        ? Icons.favorite_rounded
                        : Icons.favorite_border,
                    color:
                        isWishlisted ? ProductCardColors.heart : AppColors.text,
                    size: 20,
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
          size: 34,
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.26),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        '$discountPercent% OFF',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final hasDiscount = _discountPercent(product) > 0;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 7,
      runSpacing: 2,
      children: [
        Text(
          '\u20B9${_formatPrice(product.sellingPrice)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 15,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (hasDiscount)
          Text(
            '\u20B9${_formatPrice(product.price)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.mutedText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.lineThrough,
            ),
          ),
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
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    if (!isAvailable) {
      return Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: const Text(
          'Out of Stock',
          style: TextStyle(
            color: AppColors.mutedText,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    if (quantity <= 0) {
      return SizedBox(
        width: double.infinity,
        height: 32,
        child: ElevatedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_shopping_cart_rounded, size: 15),
          label: const Text('Add'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _QuantityButton(icon: Icons.remove_rounded, onTap: onDecrement),
          Text(
            quantity.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: SizedBox(
        width: 36,
        height: 32,
        child: Icon(icon, color: Colors.white, size: 17),
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

class ProductCardAssets {
  const ProductCardAssets._();

  static const fallbackProductImage =
      'https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=900&q=85';
}

class ProductCardConfig {
  const ProductCardConfig._();

  static const imageMemCacheWidth = 420;
  static const imageDiskCacheWidth = 640;
}
