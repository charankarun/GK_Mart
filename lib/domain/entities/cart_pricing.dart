import 'cart_item.dart';

class CartPricingSummary {
  const CartPricingSummary({
    required this.originalAmount,
    required this.productSavings,
    required this.cartDiscount,
    required this.deliveryFee,
  });

  final double originalAmount;
  final double productSavings;
  final double cartDiscount;
  final double deliveryFee;

  double get finalPayable => originalAmount - cartDiscount + deliveryFee;

  double get totalSavings => productSavings + cartDiscount;

  bool get hasFreeDelivery => originalAmount >= CartPricingRules.freeDeliveryAt;

  bool get hasCartDiscount => cartDiscount > 0;

  factory CartPricingSummary.fromCartItems(List<CartItem> items) {
    return CartPricingSummary.fromAmounts(
      originalAmount: items.fold<double>(
        0,
        (total, item) => total + item.lineTotal,
      ),
      productSavings: items.fold<double>(
        0,
        (total, item) => total + item.lineSavings,
      ),
    );
  }

  factory CartPricingSummary.fromAmounts({
    required double originalAmount,
    double productSavings = 0,
  }) {
    final safeOriginalAmount = originalAmount < 0 ? 0.0 : originalAmount;
    final safeProductSavings = productSavings < 0 ? 0.0 : productSavings;

    return CartPricingSummary(
      originalAmount: safeOriginalAmount,
      productSavings: safeProductSavings,
      cartDiscount: CartPricingRules.cartDiscountFor(safeOriginalAmount),
      deliveryFee: CartPricingRules.deliveryFeeFor(safeOriginalAmount),
    );
  }
}

class CartPricingRules {
  const CartPricingRules._();

  static const freeDeliveryAt = 699.0;
  static const deliveryFee = 50.0;

  static double cartDiscountFor(double amount) {
    if (amount >= 4000) return 150;
    if (amount >= 3000) return 100;
    if (amount >= 2000) return 50;
    return 0;
  }

  static double deliveryFeeFor(double amount) {
    return amount >= freeDeliveryAt ? 0 : deliveryFee;
  }
}
