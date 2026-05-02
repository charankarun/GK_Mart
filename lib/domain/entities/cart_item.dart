import 'product.dart';

class CartItem {
  const CartItem({
    required this.productId,
    required this.name,
    required this.price,
    this.discountPrice = 0,
    required this.quantity,
    this.unit = '',
    this.imageUrl = '',
  });

  final String productId;
  final String name;
  final double price;
  final double discountPrice;
  final int quantity;
  final String unit;
  final String imageUrl;

  double get effectivePrice {
    if (discountPrice > 0 && discountPrice < price) return discountPrice;
    return price;
  }

  double get lineTotal => effectivePrice * quantity;

  double get lineSavings => (price - effectivePrice) * quantity;

  factory CartItem.fromProduct(Product product, {int quantity = 1}) {
    return CartItem(
      productId: product.id,
      name: product.name,
      price: product.price,
      discountPrice: product.discountPrice,
      quantity: quantity,
      unit: product.unit,
      imageUrl: product.imageUrl,
    );
  }

  CartItem copyWith({
    String? productId,
    String? name,
    double? price,
    double? discountPrice,
    int? quantity,
    String? unit,
    String? imageUrl,
  }) {
    return CartItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      price: price ?? this.price,
      discountPrice: discountPrice ?? this.discountPrice,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}
