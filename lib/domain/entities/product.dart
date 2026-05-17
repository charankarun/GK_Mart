class Product {
  const Product({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.price,
    this.discountPrice = 0,
    this.imageUrl = '',
    this.isAvailable = true,
    this.unit = '',
    this.stockQuantity,
    this.lowStockThreshold = 5,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String categoryId;
  final double price;
  final double discountPrice;
  final String imageUrl;
  final bool isAvailable;
  final String unit;
  final int? stockQuantity;
  final int lowStockThreshold;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get category => categoryId;

  bool get outOfStock => !isAvailable;

  bool get isStockTracked => stockQuantity != null;

  bool get isLowStock {
    final quantity = stockQuantity;
    if (quantity == null) return false;
    return quantity > 0 && quantity <= lowStockThreshold;
  }

  bool get isStockEmpty {
    final quantity = stockQuantity;
    if (quantity == null) return false;
    return quantity <= 0;
  }

  double get sellingPrice {
    if (discountPrice > 0 && discountPrice < price) return discountPrice;
    return price;
  }

  Product copyWith({
    String? id,
    String? name,
    String? categoryId,
    double? price,
    double? discountPrice,
    String? imageUrl,
    bool? isAvailable,
    bool? outOfStock,
    String? unit,
    int? stockQuantity,
    bool clearStockQuantity = false,
    int? lowStockThreshold,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      price: price ?? this.price,
      discountPrice: discountPrice ?? this.discountPrice,
      imageUrl: imageUrl ?? this.imageUrl,
      isAvailable:
          isAvailable ?? (outOfStock == null ? this.isAvailable : !outOfStock),
      unit: unit ?? this.unit,
      stockQuantity:
          clearStockQuantity ? null : stockQuantity ?? this.stockQuantity,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
