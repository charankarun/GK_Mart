import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/cart_pricing.dart';
import '../navigation/customer_navigation_scope.dart';
import '../providers/auth_providers.dart';
import '../providers/commerce_providers.dart';
import '../widgets/app_cached_network_image.dart';
import 'checkout_screen.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text(CartText.title)),
      body: cartItems.isEmpty
          ? const _EmptyCart()
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    itemCount: cartItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = cartItems[index];

                      return _CartItemCard(
                        item: item,
                        onIncrement: () {
                          cartController.increment(item.productId);
                        },
                        onDecrement: () {
                          cartController.decrement(item.productId);
                        },
                        onRemove: () {
                          cartController.remove(item.productId);
                        },
                      );
                    },
                  ),
                ),
                _CartSummary(
                  itemCount: cartItems.fold<int>(
                    0,
                    (count, item) => count + item.quantity,
                  ),
                  pricing: pricing,
                  onCheckout: () {
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
  });

  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

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
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
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
                      fontSize: 15,
                      height: 1.18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (item.unit.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      item.unit,
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
                        '\u20B9${_formatPrice(item.effectivePrice)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (hasSavings)
                        Text(
                          '\u20B9${_formatPrice(item.price)}',
                          style: const TextStyle(
                            color: AppColors.mutedText,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                    ],
                  ),
                  if (hasSavings) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${CartText.saved} \u20B9${_formatPrice(item.lineSavings)}',
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
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
                      Tooltip(
                        message: CartText.remove,
                        child: IconButton.outlined(
                          visualDensity: VisualDensity.compact,
                          onPressed: onRemove,
                          icon: const Icon(Icons.delete_outline_rounded),
                          color: CartColors.remove,
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
        width: 92,
        height: 102,
        child: AppCachedNetworkImage(
          imageUrl: trimmedUrl,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          memCacheWidth: CartConfig.itemImageCacheWidth,
          memCacheHeight: CartConfig.itemImageCacheHeight,
          maxWidthDiskCache: CartConfig.itemImageDiskCacheWidth,
          maxHeightDiskCache: CartConfig.itemImageDiskCacheHeight,
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

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadii.md),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QuantityButton(icon: Icons.remove_rounded, onTap: onDecrement),
          SizedBox(
            width: 34,
            child: Text(
              quantity.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: SizedBox(
        width: 34,
        height: 36,
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _CartSummary extends StatelessWidget {
  const _CartSummary({
    required this.itemCount,
    required this.pricing,
    required this.onCheckout,
  });

  final int itemCount;
  final CartPricingSummary pricing;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 18,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SummaryRow(
              label: CartText.items,
              value: '$itemCount',
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              label: CartText.originalAmount,
              value: '\u20B9${_formatPrice(pricing.originalAmount)}',
            ),
            if (pricing.productSavings > 0) ...[
              const SizedBox(height: 8),
              _SummaryRow(
                label: CartText.productSavings,
                value: '-\u20B9${_formatPrice(pricing.productSavings)}',
                valueColor: AppColors.primaryDark,
              ),
            ],
            const SizedBox(height: 8),
            _SummaryRow(
              label: CartText.cartDiscount,
              value: pricing.cartDiscount > 0
                  ? '-\u20B9${_formatPrice(pricing.cartDiscount)}'
                  : '\u20B90',
              valueColor: AppColors.primaryDark,
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              label: CartText.deliveryFee,
              value: pricing.deliveryFee > 0
                  ? '\u20B9${_formatPrice(pricing.deliveryFee)}'
                  : CartText.free,
              valueColor:
                  pricing.deliveryFee > 0 ? null : AppColors.primaryDark,
            ),
            const SizedBox(height: 8),
            _DeliveryMessage(isFree: pricing.hasFreeDelivery),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: AppColors.border),
            ),
            _SummaryRow(
              label: CartText.finalPayable,
              value: '\u20B9${_formatPrice(pricing.finalPayable)}',
              isStrong: true,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                ),
                onPressed: onCheckout,
                icon: const Icon(Icons.lock_rounded, size: 18),
                label: const Text(CartText.checkout),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryMessage extends StatelessWidget {
  const _DeliveryMessage({required this.isFree});

  final bool isFree;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isFree ? AppColors.softGreen : AppColors.softOrange,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Icon(
            isFree
                ? Icons.local_shipping_rounded
                : Icons.info_outline_rounded,
            color: isFree ? AppColors.primary : AppColors.accent,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isFree ? CartText.freeDeliveryApplied : CartText.deliveryHint,
              style: TextStyle(
                color: isFree ? AppColors.primaryDark : AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
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
            fontSize: isStrong ? 16 : 13,
            fontWeight: isStrong ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.text,
            fontSize: isStrong ? 18 : 14,
            fontWeight: FontWeight.w900,
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
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _EmptyCartIcon(),
            const SizedBox(height: 16),
            const Text(
              CartText.emptyCart,
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
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: const Text(CartText.addItems),
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

class _EmptyCartIcon extends StatelessWidget {
  const _EmptyCartIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: const BoxDecoration(
        color: AppColors.softGreen,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.shopping_cart_outlined,
        color: AppColors.primary,
        size: 34,
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
