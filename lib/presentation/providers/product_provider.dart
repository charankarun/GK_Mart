import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/repository_exception.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_image_upload.dart';
import '../../domain/entities/product_page.dart';
import '../../domain/entities/product_stats.dart';
import 'repository_providers.dart';
import 'role_provider.dart';

final dashboardInventoryStatsProvider =
    FutureProvider.autoDispose<ProductStats>((ref) async {
  final permissions = ref.watch(userPermissionsProvider);
  if (!permissions.canManageInventory) {
    throw const RepositoryException('Access denied. Insufficient permissions.');
  }
  _dashboardLog(
    'Inventory query start via fetchInventoryStats()',
  );
  try {
    final stats = await ref
        .watch(productRepositoryProvider)
        .fetchInventoryStats()
        .timeout(AppDurations.dashboardTimeout);
    _dashboardLog('Inventory stats fetched totalProducts=${stats.totalProducts}');
    return stats;
  } catch (error, stackTrace) {
    _dashboardLog(
      'Riverpod dashboardInventoryStatsProvider exception',
      error: error,
      stackTrace: stackTrace,
    );
    Error.throwWithStackTrace(error, stackTrace);
  }
});

final adminProductListProvider = StateNotifierProvider.autoDispose<
    AdminProductListController, AsyncValue<AdminProductListState>>((ref) {
  final permissions = ref.watch(userPermissionsProvider);
  if (!permissions.canManageProducts) {
    throw const RepositoryException('Access denied. Insufficient permissions.');
  }
  return AdminProductListController(ref)..loadInitial();
});


class AdminProductListController
    extends StateNotifier<AsyncValue<AdminProductListState>> {
  AdminProductListController(this._ref) : super(const AsyncLoading());

  final Ref _ref;
  bool _isSavingProduct = false;
  String _searchQuery = '';

  Future<void> loadInitial({String? searchQuery}) async {
    if (searchQuery != null) _searchQuery = searchQuery.trim();
    state = const AsyncLoading();

    try {
      final repository = _ref.read(productRepositoryProvider);
      final page = _searchQuery.isEmpty
          ? await repository.fetchProductsPage(
              limit: ProductProviderConfig.pageSize,
            )
          : await repository.fetchProductSearchPage(
              query: _searchQuery,
              limit: ProductProviderConfig.pageSize,
            );
      if (!mounted) return;
      state = AsyncData(
        AdminProductListState.fromPage(page).copyWith(
          searchQuery: _searchQuery,
        ),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> search(String query) {
    return loadInitial(searchQuery: query);
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
      final repository = _ref.read(productRepositoryProvider);
      final page = _searchQuery.isEmpty
          ? await repository.fetchProductsPage(
              limit: ProductProviderConfig.pageSize,
              cursor: currentState.nextCursor,
            )
          : await repository.fetchProductSearchPage(
              query: _searchQuery,
              limit: ProductProviderConfig.pageSize,
              cursor: currentState.nextCursor,
            );

      if (!mounted) return;
      state = AsyncData(
        currentState.copyWith(
          products: _mergeProducts(currentState.products, page.products),
          nextCursor: page.nextCursor,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      state = AsyncData(currentState.copyWith(isLoadingMore: false));
      rethrow;
    }
  }

  Future<void> saveProduct(AdminProductInput input) async {
    if (_isSavingProduct) return;

    _isSavingProduct = true;
    final previousState = state;
    state = const AsyncLoading();

    try {
      final imageUrl = await _resolveImageUrl(input);
      final product = Product(
        id: input.productId ?? '',
        name: input.name,
        categoryId: input.categoryId,
        price: input.price,
        discountPrice: input.discountPrice,
        imageUrl: imageUrl,
        isAvailable: input.isAvailable,
        unit: input.unit,
        barcode: input.barcode,
        brand: input.brand,
        stockQuantity: input.stockQuantity,
        trackStock: input.trackStock,
        lowStockThreshold: input.lowStockThreshold,
        quantityValue: input.quantityValue,
      );

      final repository = _ref.read(productRepositoryProvider);
      if (input.isEditing) {
        await repository.updateProduct(product);
      } else {
        await repository.addProduct(product);
      }
      _ref.invalidate(dashboardInventoryStatsProvider);
      await loadInitial();
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = previousState.hasValue
          ? previousState
          : AsyncError(error, stackTrace);
      rethrow;
    } finally {
      _isSavingProduct = false;
    }
  }

  Future<void> updateAvailability({
    required String productId,
    required bool isAvailable,
  }) async {
    final currentState = _currentState;
    if (currentState == null) return;
    if (currentState.pendingAvailabilityProductIds.contains(productId)) return;

    final optimisticState = currentState
        .replaceProduct(
      productId,
      (product) => product.copyWith(isAvailable: isAvailable),
    )
        .copyWith(
      pendingAvailabilityProductIds: {
        ...currentState.pendingAvailabilityProductIds,
        productId,
      },
    );
    state = AsyncData(optimisticState);

    try {
      await _ref.read(productRepositoryProvider).updateProductAvailability(
            productId: productId,
            isAvailable: isAvailable,
          );
      _ref.invalidate(dashboardInventoryStatsProvider);
      final latestState = _currentState;
      if (latestState == null) return;
      if (!mounted) return;
      state = AsyncData(
        latestState.copyWith(
          pendingAvailabilityProductIds: {
            for (final pendingProductId
                in latestState.pendingAvailabilityProductIds)
              if (pendingProductId != productId) pendingProductId,
          },
        ),
      );
    } catch (_) {
      if (!mounted) return;
      state = AsyncData(currentState);
      rethrow;
    }
  }

  Future<void> updateStock({
    required String productId,
    required int stockQuantity,
  }) async {
    if (stockQuantity < 0) {
      throw ArgumentError.value(
        stockQuantity,
        'stockQuantity',
        'Must not be negative',
      );
    }

    final currentState = _currentState;
    if (currentState == null) return;
    if (currentState.pendingStockProductIds.contains(productId)) return;

    final optimisticState = currentState
        .replaceProduct(
      productId,
      (product) => product.copyWith(
        stockQuantity: stockQuantity,
        isAvailable: stockQuantity > 0,
      ),
    )
        .copyWith(
      pendingStockProductIds: {
        ...currentState.pendingStockProductIds,
        productId,
      },
    );
    state = AsyncData(optimisticState);

    try {
      await _ref.read(productRepositoryProvider).updateProductStock(
            productId: productId,
            stockQuantity: stockQuantity,
          );
      _ref.invalidate(dashboardInventoryStatsProvider);
      final latestState = _currentState;
      if (latestState == null) return;
      if (!mounted) return;
      state = AsyncData(
        latestState.copyWith(
          pendingStockProductIds: {
            for (final pendingProductId in latestState.pendingStockProductIds)
              if (pendingProductId != productId) pendingProductId,
          },
        ),
      );
    } catch (_) {
      if (!mounted) return;
      state = AsyncData(currentState);
      rethrow;
    }
  }

  Future<void> deleteProduct(String productId) async {
    final currentState = _currentState;
    if (currentState == null) return;
    if (currentState.pendingDeleteProductIds.contains(productId)) return;

    state = AsyncData(
      currentState.copyWith(
        pendingDeleteProductIds: {
          ...currentState.pendingDeleteProductIds,
          productId,
        },
      ),
    );

    try {
      await _ref.read(productRepositoryProvider).deleteProduct(productId);
      _ref.invalidate(dashboardInventoryStatsProvider);
      await loadInitial();
    } catch (_) {
      if (!mounted) return;
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

List<Product> _mergeProducts(
  List<Product> currentProducts,
  List<Product> nextProducts,
) {
  final productsById = <String, Product>{
    for (final product in currentProducts) product.id: product,
  };
  for (final product in nextProducts) {
    productsById[product.id] = product;
  }
  return productsById.values.toList();
}

class AdminProductListState {
  const AdminProductListState({
    required this.products,
    required this.hasMore,
    this.nextCursor,
    this.isLoadingMore = false,
    this.pendingAvailabilityProductIds = const <String>{},
    this.pendingStockProductIds = const <String>{},
    this.pendingDeleteProductIds = const <String>{},
    this.searchQuery = '',
  });

  final List<Product> products;
  final ProductPageCursor? nextCursor;
  final bool hasMore;
  final bool isLoadingMore;
  final Set<String> pendingAvailabilityProductIds;
  final Set<String> pendingStockProductIds;
  final Set<String> pendingDeleteProductIds;
  final String searchQuery;

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
    Set<String>? pendingAvailabilityProductIds,
    Set<String>? pendingStockProductIds,
    Set<String>? pendingDeleteProductIds,
    String? searchQuery,
  }) {
    return AdminProductListState(
      products: products ?? this.products,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      pendingAvailabilityProductIds:
          pendingAvailabilityProductIds ?? this.pendingAvailabilityProductIds,
      pendingStockProductIds:
          pendingStockProductIds ?? this.pendingStockProductIds,
      pendingDeleteProductIds:
          pendingDeleteProductIds ?? this.pendingDeleteProductIds,
      searchQuery: searchQuery ?? this.searchQuery,
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
    required this.unit,
    required this.barcode,
    required this.brand,
    required this.trackStock,
    required this.stockQuantity,
    required this.lowStockThreshold,
    this.quantityValue,
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
  final String unit;
  final String barcode;
  final String brand;
  final bool trackStock;
  final int? stockQuantity;
  final int lowStockThreshold;
  final double? quantityValue;
  final Uint8List? imageBytes;
  final String? imageFileName;
  final String imageContentType;

  bool get isEditing => productId != null && productId!.trim().isNotEmpty;
}

class ProductProviderConfig {
  const ProductProviderConfig._();

  static const pageSize = 20;
  static const inventoryStatsLimit = 60;
  static const imageFileName = 'product_image.jpg';
  static const defaultImageContentType = 'image/jpeg';
}

const _dashboardLogName = 'AdminDashboard';
const _debugLoggingEnabled = !bool.fromEnvironment('dart.vm.product');

void _dashboardLog(
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  if (!_debugLoggingEnabled) return;
  developer.log(
    message,
    name: _dashboardLogName,
    error: error,
    stackTrace: stackTrace,
  );
}
