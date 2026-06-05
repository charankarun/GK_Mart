import 'product.dart';

class ProductStats {
  const ProductStats({
    required this.totalProducts,
    required this.availableProducts,
    required this.outOfStockProducts,
    required this.lowStockProducts,
    this.totalCategories = 0,
  });

  final int totalProducts;
  final int availableProducts;
  final int outOfStockProducts;
  final int lowStockProducts;
  final int totalCategories;

  factory ProductStats.fromProducts(Iterable<Product> products, {int? totalCategories}) {
    var totalProducts = 0;
    var availableProducts = 0;
    var lowStockProducts = 0;

    for (final product in products) {
      totalProducts += 1;
      if (product.isAvailable && !product.isStockEmpty) availableProducts += 1;
      if (product.isLowStock) lowStockProducts += 1;
    }

    final computedCategories = totalCategories ?? products.map((p) => p.categoryId).toSet().length;

    return ProductStats(
      totalProducts: totalProducts,
      availableProducts: availableProducts,
      outOfStockProducts: totalProducts - availableProducts,
      lowStockProducts: lowStockProducts,
      totalCategories: computedCategories,
    );
  }
}
