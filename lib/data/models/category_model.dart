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
    return {
      CategoryField.name: name.trim(),
      CategoryField.imageUrl: imageUrl.trim(),
      if (includeCreatedAt)
        CategoryField.createdAt: FieldValue.serverTimestamp(),
      CategoryField.updatedAt: FieldValue.serverTimestamp(),
    };
  }
}

class CategoryField {
  const CategoryField._();

  static const name = 'name';
  static const imageUrl = 'imageUrl';
  static const createdAt = 'createdAt';
  static const updatedAt = 'updatedAt';

  static const legacyImage = 'image';
}
