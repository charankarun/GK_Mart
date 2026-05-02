class Category {
  const Category({
    required this.id,
    required this.name,
    this.imageUrl = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String imageUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Category copyWith({
    String? id,
    String? name,
    String? imageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
