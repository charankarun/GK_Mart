import 'product.dart';

class ProductPage {
  const ProductPage({
    required this.products,
    required this.hasMore,
    this.nextCursor,
  });

  final List<Product> products;
  final bool hasMore;
  final ProductPageCursor? nextCursor;
}

class ProductPageCursor {
  const ProductPageCursor({
    required this.id,
    required this.name,
    this.source,
  });

  final String id;
  final String name;
  final String? source;
}
