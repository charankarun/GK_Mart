import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/category.dart';
import '../mappers/firestore_value_parser.dart';

class CategoryModel extends Category {
  const CategoryModel({
    required super.id,
    required super.name,
    super.imageUrl,
    super.createdAt,
    super.updatedAt,
  });

  factory CategoryModel.fromEntity(Category category) {
    return CategoryModel(
      id: category.id,
      name: category.name,
      imageUrl: category.imageUrl,
      createdAt: category.createdAt,
      updatedAt: category.updatedAt,
    );
  }

  factory CategoryModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};

    return CategoryModel(
      id: doc.id,
      name: readString(data, CategoryField.name, fallback: 'Category'),
      imageUrl: readString(
        data,
        CategoryField.imageUrl,
        fallback: readString(data, CategoryField.legacyImage),
      ),
      createdAt: readDateTime(data[CategoryField.createdAt]),
      updatedAt: readDateTime(data[CategoryField.updatedAt]),
    );
  }

  Map<String, dynamic> toFirestore({required bool includeCreatedAt}) {
    final normalizedName = name.trim();

    return {
      CategoryField.name: normalizedName,
      CategoryField.searchName: normalizedName.toLowerCase(),
      CategoryField.searchTokens: _searchTokens(normalizedName),
      CategoryField.imageUrl: imageUrl.trim(),
      if (includeCreatedAt)
        CategoryField.createdAt: FieldValue.serverTimestamp(),
      CategoryField.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  static List<String> _searchTokens(String value) {
    final tokens = <String>{};
    final words = value
        .trim()
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.isNotEmpty);

    for (final word in words) {
      final maxLength = word.length > 24 ? 24 : word.length;
      for (var index = 1; index <= maxLength; index += 1) {
        tokens.add(word.substring(0, index));
      }
    }

    return tokens.take(40).toList()..sort();
  }
}

class CategoryField {
  const CategoryField._();

  static const name = 'name';
  static const searchName = 'searchName';
  static const searchTokens = 'searchTokens';
  static const imageUrl = 'imageUrl';
  static const createdAt = 'createdAt';
  static const updatedAt = 'updatedAt';

  static const legacyImage = 'image';
}
