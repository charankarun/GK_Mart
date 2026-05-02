import 'product.dart';

class WishlistItem {
  const WishlistItem({
    required this.productId,
    required this.name,
    required this.price,
    this.unit = '',
    this.imageUrl = '',
  });

  final String productId;
  final String name;
  final double price;
  final String unit;
  final String imageUrl;

  factory WishlistItem.fromProduct(Product product) {
    return WishlistItem(
      productId: product.id,
      name: product.name,
      price: product.sellingPrice,
      unit: product.unit,
      imageUrl: product.imageUrl,
    );
  }
}
