import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/product.dart';
import '../mappers/firestore_value_parser.dart';

class ProductModel extends Product {
  const ProductModel({
    required super.id,
    required super.name,
    required super.categoryId,
    required super.price,
    super.discountPrice,
    super.imageUrl,
    super.isAvailable,
    super.unit,
    super.stockQuantity,
    super.lowStockThreshold,
    super.createdAt,
    super.updatedAt,
  });

  factory ProductModel.fromEntity(Product product) {
    return ProductModel(
      id: product.id,
      name: product.name,
      categoryId: product.categoryId,
      price: product.price,
      discountPrice: product.discountPrice,
      imageUrl: product.imageUrl,
      isAvailable: product.isAvailable,
      unit: product.unit,
      stockQuantity: product.stockQuantity,
      lowStockThreshold: product.lowStockThreshold,
      createdAt: product.createdAt,
      updatedAt: product.updatedAt,
    );
  }

  factory ProductModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};

    return ProductModel(
      id: doc.id,
      name: readString(data, ProductField.name, fallback: 'Product'),
      categoryId: _readCategoryId(data),
      price: readDouble(data[ProductField.price]),
      discountPrice: readDouble(data[ProductField.discountPrice]),
      imageUrl: _readImageUrl(data),
      isAvailable: _readAvailability(data),
      unit: readString(data, ProductField.unit),
      stockQuantity: _readStockQuantity(data),
      lowStockThreshold: _readLowStockThreshold(data),
      createdAt: readDateTime(data[ProductField.createdAt]),
      updatedAt: readDateTime(data[ProductField.updatedAt]),
    );
  }

  Map<String, dynamic> toFirestore({
    required bool includeCreatedAt,
    bool includeDeletes = false,
  }) {
    final normalizedName = name.trim();

    return {
      ProductField.name: normalizedName,
      ProductField.searchName: normalizedName.toLowerCase(),
      ProductField.searchTokens: _searchTokens([
        normalizedName,
        categoryId,
        unit,
      ]),
      ProductField.categoryId: categoryId.trim(),
      ProductField.price: price,
      ProductField.discountPrice: discountPrice,
      ProductField.imageUrl: imageUrl.trim(),
      ProductField.isAvailable: isAvailable,
      if (unit.trim().isNotEmpty) ProductField.unit: unit.trim(),
      if (stockQuantity != null) ...{
        ProductField.stockQuantity: stockQuantity,
        ProductField.lowStockThreshold: lowStockThreshold,
      } else if (includeDeletes) ...{
        ProductField.stockQuantity: FieldValue.delete(),
        ProductField.lowStockThreshold: FieldValue.delete(),
      },
      if (includeCreatedAt)
        ProductField.createdAt: FieldValue.serverTimestamp(),
      ProductField.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  static String _readCategoryId(Map<String, dynamic> data) {
    return readString(
      data,
      ProductField.categoryId,
      fallback: readString(data, ProductField.legacyCategory),
    );
  }

  static String _readImageUrl(Map<String, dynamic> data) {
    return readString(
      data,
      ProductField.imageUrl,
      fallback: readString(data, ProductField.legacyImage),
    );
  }

  static bool _readAvailability(Map<String, dynamic> data) {
    final isAvailable = data[ProductField.isAvailable];
    if (isAvailable is bool) return isAvailable;

    final outOfStock = data[ProductField.legacyOutOfStock];
    if (outOfStock is bool) return !outOfStock;

    return true;
  }

  static int? _readStockQuantity(Map<String, dynamic> data) {
    final value = data[ProductField.stockQuantity];
    if (value == null) return null;
    final quantity = readInt(value);
    return quantity < 0 ? 0 : quantity;
  }

  static int _readLowStockThreshold(Map<String, dynamic> data) {
    final value = data[ProductField.lowStockThreshold];
    if (value == null) return 5;
    final threshold = readInt(value);
    return threshold < 0 ? 5 : threshold;
  }

  static List<String> _searchTokens(Iterable<String> values) {
    final tokens = <String>{};

    for (final value in values) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) continue;

      final words = normalized
          .split(RegExp(r'[^a-z0-9]+'))
          .where((word) => word.isNotEmpty);
      for (final word in words) {
        final maxLength = word.length > 24 ? 24 : word.length;
        for (var index = 1; index <= maxLength; index += 1) {
          tokens.add(word.substring(0, index));
        }
      }
    }

    return tokens.take(80).toList()..sort();
  }
}

class ProductField {
  const ProductField._();

  static const name = 'name';
  static const searchName = 'searchName';
  static const searchTokens = 'searchTokens';
  static const categoryId = 'categoryId';
  static const price = 'price';
  static const discountPrice = 'discountPrice';
  static const imageUrl = 'imageUrl';
  static const isAvailable = 'isAvailable';
  static const unit = 'unit';
  static const stockQuantity = 'stockQuantity';
  static const lowStockThreshold = 'lowStockThreshold';
  static const createdAt = 'createdAt';
  static const updatedAt = 'updatedAt';

  static const legacyCategory = 'category';
  static const legacyImage = 'image';
  static const legacyOutOfStock = 'outOfStock';
}
