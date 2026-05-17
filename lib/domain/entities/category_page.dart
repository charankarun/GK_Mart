import 'category.dart';

class CategoryPage {
  const CategoryPage({
    required this.categories,
    required this.hasMore,
    this.nextCursor,
  });

  final List<Category> categories;
  final bool hasMore;
  final CategoryPageCursor? nextCursor;
}

class CategoryPageCursor {
  const CategoryPageCursor({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}
