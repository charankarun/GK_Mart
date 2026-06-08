import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/entities/product.dart';
import '../../domain/entities/product_page.dart';
export 'category_provider.dart';
import 'repository_providers.dart';

final productsStreamProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(productRepositoryProvider).watchProducts();
});

final productsProvider = productsStreamProvider;

final catalogProductListProvider = StateNotifierProvider.autoDispose<
    ProductPageListController, AsyncValue<ProductListState>>((ref) {
  return ProductPageListController(
    loadPage: ({required limit, cursor}) {
      return ref.read(productRepositoryProvider).fetchProductsPage(
            limit: limit,
            cursor: cursor,
          );
    },
  )..loadInitial();
});

final categoryProductListProvider = StateNotifierProvider.autoDispose.family<
    ProductPageListController,
    AsyncValue<ProductListState>,
    CategoryProductsRequest>((ref, request) {
  return ProductPageListController(
    loadPage: ({required limit, cursor}) {
      return ref.read(productRepositoryProvider).fetchProductsByCategoryPage(
            categoryId: request.categoryId,
            categoryName: request.categoryName,
            limit: limit,
            cursor: cursor,
          );
    },
  )..loadInitial();
});

final productSearchResultsProvider = StateNotifierProvider.autoDispose
    .family<ProductPageListController, AsyncValue<ProductListState>, String>(
  (ref, query) {
    return ProductPageListController(
      loadPage: ({required limit, cursor}) {
        return ref.read(productRepositoryProvider).fetchProductSearchPage(
              query: query,
              limit: limit,
              cursor: cursor,
            );
      },
    )..loadInitial();
  },
);

final addProductProvider = Provider<Future<void> Function(Product)>((ref) {
  return (product) {
    return ref.read(productRepositoryProvider).addProduct(product);
  };
});

final updateProductProvider = Provider<Future<void> Function(Product)>((ref) {
  return (product) {
    return ref.read(productRepositoryProvider).updateProduct(product);
  };
});

typedef ProductPageLoader = Future<ProductPage> Function({
  required int limit,
  ProductPageCursor? cursor,
});

class ProductPageListController
    extends StateNotifier<AsyncValue<ProductListState>> {
  ProductPageListController({
    required ProductPageLoader loadPage,
  })  : _loadPage = loadPage,
        super(const AsyncLoading());

  final ProductPageLoader _loadPage;

  Future<void> loadInitial() async {
    state = const AsyncLoading();

    try {
      final page =
          await _loadPage(limit: CatalogProviderConfig.productPageSize);
      if (!mounted) return;
      state = AsyncData(ProductListState.fromPage(page));
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> loadNext() async {
    final currentState = _currentState;
    if (currentState == null ||
        currentState.isLoadingMore ||
        !currentState.hasMore) {
      return;
    }

    state = AsyncData(currentState.copyWith(isLoadingMore: true));

    try {
      final page = await _loadPage(
        limit: CatalogProviderConfig.productPageSize,
        cursor: currentState.nextCursor,
      );
      if (!mounted) return;
      state = AsyncData(currentState.appendPage(page));
    } catch (_) {
      if (!mounted) return;
      state = AsyncData(currentState.copyWith(isLoadingMore: false));
      rethrow;
    }
  }

  ProductListState? get _currentState {
    return state.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
  }
}

class ProductListState {
  const ProductListState({
    required this.products,
    required this.hasMore,
    this.nextCursor,
    this.isLoadingMore = false,
  });

  final List<Product> products;
  final ProductPageCursor? nextCursor;
  final bool hasMore;
  final bool isLoadingMore;

  factory ProductListState.fromPage(ProductPage page) {
    return ProductListState(
      products: page.products,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  ProductListState copyWith({
    List<Product>? products,
    ProductPageCursor? nextCursor,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return ProductListState(
      products: products ?? this.products,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  ProductListState appendPage(ProductPage page) {
    final productsById = <String, Product>{
      for (final product in products) product.id: product,
    };
    for (final product in page.products) {
      productsById[product.id] = product;
    }

    return ProductListState(
      products: productsById.values.toList(),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }
}

class CategoryProductsRequest {
  const CategoryProductsRequest({
    required this.categoryId,
    required this.categoryName,
  });

  final String categoryId;
  final String categoryName;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CategoryProductsRequest &&
            other.categoryId == categoryId &&
            other.categoryName == categoryName;
  }

  @override
  int get hashCode => Object.hash(categoryId, categoryName);
}

class CatalogProviderConfig {
  const CatalogProviderConfig._();

  static const productPageSize = 20;
}

class ProductIdsRequest {
  ProductIdsRequest(List<String> ids) : ids = List.unmodifiable(ids);

  final List<String> ids;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ProductIdsRequest || ids.length != other.ids.length) {
      return false;
    }

    for (var index = 0; index < ids.length; index += 1) {
      if (ids[index] != other.ids[index]) return false;
    }

    return true;
  }

  @override
  int get hashCode => Object.hashAll(ids);
}

final productsByIdsProvider = FutureProvider.family<List<Product>, ProductIdsRequest>((ref, request) {
  return ref.watch(productRepositoryProvider).fetchProductsByIds(request.ids);
});

final productStreamProvider = StreamProvider.family<Product?, String>((ref, productId) {
  return ref.watch(productRepositoryProvider).watchProduct(productId);
});

