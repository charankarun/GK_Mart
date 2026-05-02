import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/entities/product.dart';
import '../../domain/entities/product_image_upload.dart';
import '../../domain/entities/product_page.dart';
import 'repository_providers.dart';

final adminProductListProvider = StateNotifierProvider.autoDispose<
    AdminProductListController, AsyncValue<AdminProductListState>>((ref) {
  return AdminProductListController(ref)..loadInitial();
});

class AdminProductListController
    extends StateNotifier<AsyncValue<AdminProductListState>> {
  AdminProductListController(this._ref) : super(const AsyncLoading());

  final Ref _ref;

  Future<void> loadInitial() async {
    state = const AsyncLoading();

    try {
      final page = await _ref.read(productRepositoryProvider).fetchProductsPage(
            limit: ProductProviderConfig.pageSize,
          );
      state = AsyncData(AdminProductListState.fromPage(page));
    } catch (error, stackTrace) {
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
      final page = await _ref.read(productRepositoryProvider).fetchProductsPage(
            limit: ProductProviderConfig.pageSize,
            cursor: currentState.nextCursor,
          );

      state = AsyncData(
        currentState.copyWith(
          products: [...currentState.products, ...page.products],
          nextCursor: page.nextCursor,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncData(currentState.copyWith(isLoadingMore: false));
      rethrow;
    }
  }

  Future<void> saveProduct(AdminProductInput input) async {
    final imageUrl = await _resolveImageUrl(input);
    final product = Product(
      id: input.productId ?? '',
      name: input.name,
      categoryId: input.categoryId,
      price: input.price,
      discountPrice: input.discountPrice,
      imageUrl: imageUrl,
      isAvailable: input.isAvailable,
    );

    final repository = _ref.read(productRepositoryProvider);
    if (input.isEditing) {
      await repository.updateProduct(product);
    } else {
      await repository.addProduct(product);
    }

    await loadInitial();
  }

  Future<void> updateAvailability({
    required String productId,
    required bool isAvailable,
  }) async {
    final currentState = _currentState;
    if (currentState == null) return;

    final optimisticState = currentState.replaceProduct(
      productId,
      (product) => product.copyWith(isAvailable: isAvailable),
    );
    state = AsyncData(optimisticState);

    try {
      await _ref.read(productRepositoryProvider).updateProductAvailability(
            productId: productId,
            isAvailable: isAvailable,
          );
    } catch (_) {
      state = AsyncData(currentState);
      rethrow;
    }
  }

  AdminProductListState? get _currentState {
    return state.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
  }

  Future<String> _resolveImageUrl(AdminProductInput input) async {
    final imageBytes = input.imageBytes;
    if (imageBytes == null) {
      final existingImageUrl = input.existingImageUrl.trim();
      if (existingImageUrl.isEmpty) {
        throw ArgumentError('Product image is required');
      }
      return existingImageUrl;
    }

    return _ref.read(productRepositoryProvider).uploadProductImage(
          ProductImageUpload(
            bytes: imageBytes,
            fileName:
                input.imageFileName ?? ProductProviderConfig.imageFileName,
            contentType: input.imageContentType,
          ),
        );
  }
}

class AdminProductListState {
  const AdminProductListState({
    required this.products,
    required this.hasMore,
    this.nextCursor,
    this.isLoadingMore = false,
  });

  final List<Product> products;
  final ProductPageCursor? nextCursor;
  final bool hasMore;
  final bool isLoadingMore;

  factory AdminProductListState.fromPage(ProductPage page) {
    return AdminProductListState(
      products: page.products,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  AdminProductListState copyWith({
    List<Product>? products,
    ProductPageCursor? nextCursor,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return AdminProductListState(
      products: products ?? this.products,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  AdminProductListState replaceProduct(
    String productId,
    Product Function(Product product) replace,
  ) {
    return copyWith(
      products: [
        for (final product in products)
          if (product.id == productId) replace(product) else product,
      ],
    );
  }
}

class AdminProductInput {
  const AdminProductInput({
    required this.name,
    required this.categoryId,
    required this.price,
    required this.discountPrice,
    required this.existingImageUrl,
    required this.isAvailable,
    this.productId,
    this.imageBytes,
    this.imageFileName,
    this.imageContentType = ProductProviderConfig.defaultImageContentType,
  });

  final String? productId;
  final String name;
  final String categoryId;
  final double price;
  final double discountPrice;
  final String existingImageUrl;
  final bool isAvailable;
  final Uint8List? imageBytes;
  final String? imageFileName;
  final String imageContentType;

  bool get isEditing => productId != null && productId!.trim().isNotEmpty;
}

class ProductProviderConfig {
  const ProductProviderConfig._();

  static const pageSize = 20;
  static const imageFileName = 'product_image.jpg';
  static const defaultImageContentType = 'image/jpeg';
}
