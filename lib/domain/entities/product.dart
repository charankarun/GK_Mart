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
    this.barcode = '',
    this.brand = '',
    this.stockQuantity,
    this.trackStock = false,
    this.lowStockThreshold = 5,
    this.quantityValue,
    this.description,
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
  final String barcode;
  final String brand;
  final int? stockQuantity;
  final bool trackStock;
  final int lowStockThreshold;
  final double? quantityValue;
  final String? description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get category => categoryId;

  bool get outOfStock => !isAvailable;

  bool get isStockTracked => trackStock;

  bool get isLowStock {
    if (!isAvailable) return false;
    if (!trackStock) return false;
    final quantity = stockQuantity;
    if (quantity == null) return false;
    return quantity > 0 && quantity <= lowStockThreshold;
  }

  bool get isStockEmpty {
    if (!trackStock) return false;
    final quantity = stockQuantity;
    if (quantity == null) return false;
    return quantity <= 0;
  }

  double get sellingPrice {
    if (discountPrice > 0 && discountPrice < price) return discountPrice;
    return price;
  }

  String get formattedQuantityUnit {
    if (quantityValue == null || unit.trim().isEmpty) return '';
    final qty = quantityValue!;
    final qtyStr = qty == qty.toInt() ? qty.toInt().toString() : qty.toString();
    final u = unit.trim();
    final uLower = u.toLowerCase();
    if (qty > 1) {
      if (uLower == 'piece') return '$qtyStr Pieces';
      if (uLower == 'pack') return '$qtyStr Packs';
      if (uLower == 'packet') return '$qtyStr Packets';
      if (uLower == 'bottle') return '$qtyStr Bottles';
      if (uLower == 'box') return '$qtyStr Boxes';
      if (uLower == 'dozen') return '$qtyStr Dozens';
    }
    return '$qtyStr $u';
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
    String? barcode,
    String? brand,
    int? stockQuantity,
    bool? trackStock,
    bool clearStockQuantity = false,
    int? lowStockThreshold,
    double? quantityValue,
    bool clearQuantityValue = false,
    String? description,
    bool clearDescription = false,
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
      barcode: barcode ?? this.barcode,
      brand: brand ?? this.brand,
      stockQuantity:
          clearStockQuantity ? null : stockQuantity ?? this.stockQuantity,
      trackStock: trackStock ?? this.trackStock,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      quantityValue:
          clearQuantityValue ? null : quantityValue ?? this.quantityValue,
      description: clearDescription ? null : description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
