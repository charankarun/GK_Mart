import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/cart_pricing.dart';
import '../navigation/customer_navigation_scope.dart';
import '../providers/auth_providers.dart';
import '../providers/catalog_providers.dart';
import '../providers/commerce_providers.dart';
import '../widgets/app_cached_network_image.dart';
import '../widgets/app_state_widgets.dart';
import 'checkout_screen.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cartSyncProvider.notifier).syncCart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(CartText.title)),
        body: const Center(child: Text(CartText.loginRequired)),
      );
    }

    final cartItems = ref.watch(cartItemsProvider);
    final pricing = ref.watch(cartPricingSummaryProvider);
    final cartController = ref.read(cartControllerProvider.notifier);
    final syncState = ref.watch(cartSyncProvider);

    final displayedItems = syncState.recalculatedItems ?? cartItems;
    final displayedPricing = syncState.recalculatedPricing ?? pricing;
    final hasUnavailable = syncState.unavailableProductIds.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text(CartText.title)),
      body: displayedItems.isEmpty
          ? const _EmptyCart()
          : Column(
              children: [
                if (syncState.syncMessage != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _SyncWarningBanner(message: syncState.syncMessage!),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _FreeDeliveryProgressBar(
                    originalAmount: displayedPricing.originalAmount,
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    itemCount: displayedItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = displayedItems[index];
                      final isPriceChanged = syncState.priceChangedProductIds.contains(item.productId);
                      final isUnavailable = syncState.unavailableProductIds.contains(item.productId);
                      final oldPrice = syncState.oldPrices[item.productId];
                      final newPrice = syncState.newPrices[item.productId];

                      final productAsync = ref.watch(productStreamProvider(item.productId));
                      
                      return productAsync.when(
                        data: (product) {
                          final isMax = product != null && product.trackStock && item.quantity >= (product.stockQuantity ?? 0);
                          
                          return _CartItemCard(
                            item: item,
                            isPriceChanged: isPriceChanged,
                            oldPrice: oldPrice,
                            newPrice: newPrice,
                            isUnavailable: isUnavailable,
                            onIncrement: (isMax || isUnavailable) ? null : () {
                              cartController.increment(item.productId);
                            },
                            onDecrement: isUnavailable ? null : () {
                              cartController.decrement(item.productId);
                            },
                            onRemove: () {
                              cartController.remove(item.productId);
                            },
                          );
                        },
                        loading: () => const _CartItemSkeleton(),
                        error: (_, __) => _CartItemCard(
                          item: item,
                          isPriceChanged: isPriceChanged,
                          oldPrice: oldPrice,
                          newPrice: newPrice,
                          isUnavailable: isUnavailable,
                          onIncrement: null,
                          onDecrement: isUnavailable ? null : () {
                            cartController.decrement(item.productId);
                          },
                          onRemove: () {
                            cartController.remove(item.productId);
                          },
                        ),
                      );
                    },
                  ),
                ),
                _CartSummary(
                  pricing: displayedPricing,
                  onCheckout: hasUnavailable
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CheckoutScreen()),
                          );
                        },
                ),
              ],
            ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  const _CartItemCard({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    this.isPriceChanged = false,
    this.oldPrice,
    this.newPrice,
    this.isUnavailable = false,
  });

  final CartItem item;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback onRemove;
  final bool isPriceChanged;
  final double? oldPrice;
  final double? newPrice;
  final bool isUnavailable;

  @override
  Widget build(BuildContext context) {
    final hasSavings = item.lineSavings > 0;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(
            color: isUnavailable
                ? AppColors.danger
                : isPriceChanged
                    ? AppColors.accent
                    : AppColors.border,
            width: (isUnavailable || isPriceChanged) ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CartItemImage(imageUrl: item.imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (item.unit.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.unit,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.mutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '\u20B9${_formatPrice(item.effectivePrice)}',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (hasSavings) ...[
                        const SizedBox(width: 6),
                        Text(
                          '\u20B9${_formatPrice(item.price)}',
                          style: const TextStyle(
                            color: AppColors.mutedText,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.softGreen,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '\u20B9${_formatPrice(item.lineSavings)} OFF',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (isUnavailable) ...[
                    const SizedBox(height: 8),
                    const Text(
                      "This product is no longer available.",
                      style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  if (isPriceChanged && oldPrice != null && newPrice != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.warning_rounded, color: AppColors.accent, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            "⚠ Price Updated (Old: ₹${_formatPrice(oldPrice!)}, New: ₹${_formatPrice(newPrice!)})",
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _QuantityStepper(
                        quantity: item.quantity,
                        onIncrement: onIncrement,
                        onDecrement: onDecrement,
                      ),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: onRemove,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.mutedText,
                          size: 18,
                        ),
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemImage extends StatelessWidget {
  const _CartItemImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = imageUrl.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: SizedBox(
        width: 96,
        height: 96,
        child: AppCachedNetworkImage(
          imageUrl: trimmedUrl,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          memCacheWidth: CartConfig.itemImageCacheWidth,
          memCacheHeight: CartConfig.itemImageCacheHeight,
          maxWidthDiskCache: CartConfig.itemImageDiskCacheWidth,
          maxHeightDiskCache: CartConfig.itemImageDiskCacheHeight,
          placeholder: const AppSkeletonPulse(width: 96, height: 96, borderRadius: AppRadii.md),
          errorPlaceholder: const _ImageErrorPlaceholder(),
        ),
      ),
    );
  }
}

class _ImageErrorPlaceholder extends StatelessWidget {
  const _ImageErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: AppColors.background),
      child: Center(
        child: Icon(
          Icons.local_grocery_store_rounded,
          color: AppColors.mutedText,
          size: 24,
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int quantity;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadii.md),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QuantityButton(icon: Icons.remove_rounded, onTap: onDecrement),
          Container(
            alignment: Alignment.center,
            width: 28,
            child: Text(
              quantity.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
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
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(
          icon,
          color: onTap == null ? Colors.white.withValues(alpha: 0.4) : Colors.white,
          size: 16,
        ),
      ),
    );
  }
}

class _CartSummary extends StatelessWidget {
  const _CartSummary({
    required this.pricing,
    this.onCheckout,
  });

  final CartPricingSummary pricing;
  final VoidCallback? onCheckout;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 8,
              offset: Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CompactSummaryRow(
              label: 'Subtotal',
              value: '\u20B9${_formatPrice(pricing.originalAmount)}',
            ),
            if (pricing.totalSavings > 0) ...[
              const SizedBox(height: 4),
              _CompactSummaryRow(
                label: 'Savings',
                value: '-\u20B9${_formatPrice(pricing.totalSavings)}',
                valueColor: AppColors.primary,
              ),
            ],
            const SizedBox(height: 4),
            _CompactSummaryRow(
              label: 'Delivery',
              value: pricing.deliveryFee > 0
                  ? '\u20B9${_formatPrice(pricing.deliveryFee)}'
                  : 'Free',
              valueColor: pricing.deliveryFee > 0 ? null : AppColors.primary,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: AppColors.border),
            ),
            _CompactSummaryRow(
              label: 'Total',
              value: '\u20B9${_formatPrice(pricing.finalPayable)}',
              isStrong: true,
            ),
            if (pricing.totalSavings > 0) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.softGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🎉', style: TextStyle(fontSize: 10)),
                      const SizedBox(width: 4),
                      Text(
                        'Saved \u20B9${_formatPrice(pricing.totalSavings)}',
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  elevation: 0,
                ),
                onPressed: onCheckout,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.shopping_bag_outlined, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Proceed to Checkout \u2022 \u20B9${_formatPrice(pricing.finalPayable)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FreeDeliveryProgressBar extends StatelessWidget {
  const _FreeDeliveryProgressBar({required this.originalAmount});

  final double originalAmount;

  @override
  Widget build(BuildContext context) {
    const threshold = CartPricingRules.freeDeliveryAt;
    final isFree = originalAmount >= threshold;
    final remaining = threshold - originalAmount;
    final progress = (originalAmount / threshold).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isFree ? AppColors.softGreen.withValues(alpha: 0.5) : AppColors.softOrange.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: isFree ? AppColors.primary.withValues(alpha: 0.2) : AppColors.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isFree ? Icons.local_shipping_rounded : Icons.info_outline_rounded,
                color: isFree ? AppColors.primary : AppColors.accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isFree
                      ? 'Yay! Free delivery applied to this order 🎉'
                      : 'Add \u20B9${_formatPrice(remaining)} more for FREE delivery',
                  style: TextStyle(
                    color: isFree ? AppColors.primaryDark : AppColors.accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.black.withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation<Color>(
                isFree ? AppColors.primary : AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItemSkeleton extends StatelessWidget {
  const _CartItemSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSkeletonPulse(width: 96, height: 96, borderRadius: AppRadii.md),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSkeletonPulse(width: 140, height: 16),
                const SizedBox(height: 6),
                const AppSkeletonPulse(width: 60, height: 12),
                const SizedBox(height: 12),
                Row(
                  children: const [
                    AppSkeletonPulse(width: 50, height: 20),
                    SizedBox(width: 8),
                    AppSkeletonPulse(width: 40, height: 14),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    AppSkeletonPulse(width: 90, height: 32, borderRadius: AppRadii.md),
                    AppSkeletonPulse(width: 32, height: 32, borderRadius: 8),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactSummaryRow extends StatelessWidget {
  const _CompactSummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isStrong = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool isStrong;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isStrong ? AppColors.text : AppColors.mutedText,
            fontSize: isStrong ? 14 : 12.5,
            fontWeight: isStrong ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.text,
            fontSize: isStrong ? 15 : 12.5,
            fontWeight: isStrong ? FontWeight.w900 : FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.softGreen,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  '🛒',
                  style: TextStyle(fontSize: 40),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Your cart is empty',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Browse products and start shopping.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.mutedText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 200,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
                onPressed: () => CustomerNavigationScope.openHome(context),
                child: const Text(
                  'Continue Shopping',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
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

class CartColors {
  const CartColors._();

  static const remove = Color(0xFFDC2626);
}

class CartConfig {
  const CartConfig._();

  static const itemImageCacheWidth = 190;
  static const itemImageCacheHeight = 210;
  static const itemImageDiskCacheWidth = 260;
  static const itemImageDiskCacheHeight = 300;
}

class CartText {
  const CartText._();

  static const title = 'My Cart';
  static const loginRequired = 'Please login to view your cart';
  static const emptyCart = 'Your cart is empty';
  static const addItems = 'Add Items';
  static const checkout = 'Proceed to Checkout';
  static const items = 'Items';
  static const originalAmount = 'Original Amount';
  static const productSavings = 'Product Savings';
  static const cartDiscount = 'Cart Discount';
  static const deliveryFee = 'Delivery Fee';
  static const finalPayable = 'Final Payable';
  static const free = 'Free';
  static const freeDeliveryApplied = 'Free delivery applied';
  static const deliveryHint = 'Add items worth \u20B9699 for free delivery';
  static const saved = 'Saved';
  static const remove = 'Remove item';
}
class _SyncWarningBanner extends StatelessWidget {
  const _SyncWarningBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.softOrange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
