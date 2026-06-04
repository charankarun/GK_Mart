import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error_handler.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../providers/auth_providers.dart';
import '../providers/catalog_providers.dart';
import '../providers/commerce_providers.dart';
import '../providers/wishlist_provider.dart';
import '../widgets/app_cached_network_image.dart';
import '../widgets/app_state_widgets.dart';
import '../widgets/product_card.dart';
import 'product_detail_screen.dart';

class CategoryProductsScreen extends ConsumerStatefulWidget {
  const CategoryProductsScreen({
    super.key,
    required this.category,
  });

  final Category category;

  @override
  ConsumerState<CategoryProductsScreen> createState() =>
      _CategoryProductsScreenState();
}

class _CategoryProductsScreenState
    extends ConsumerState<CategoryProductsScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter >
        CategoryProductsConfig.loadMoreExtent) {
      return;
    }

    _loadMore(showErrors: false);
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final request = CategoryProductsRequest(
      categoryId: category.id,
      categoryName: category.name,
    );
    final productListAsync = ref.watch(categoryProductListProvider(request));
    final productsAsync = productListAsync.whenData((state) => state.products);
    final productListState = productListAsync.maybeWhen(
      data: (state) => state,
      orElse: () => null,
    );
    final cartItems = ref.watch(cartItemsProvider);
    final cartQtyById = {
      for (final item in cartItems) item.productId: item.quantity,
    };
    final session = ref.watch(currentSessionProvider);
    final wishlistedProductIds = session == null
        ? const <String>{}
        : ref.watch(wishlistProductIdSetProvider(session.uid));
    final wishlistPendingProductIds = session == null
        ? const <String>{}
        : ref.watch(wishlistPendingProductIdsProvider(session.uid));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(category.name)),
      body: productsAsync.when(
        data: (products) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CategoryHeader(
                category: category,
                productCount: products.length,
              ),
              Expanded(
                child: products.isEmpty
                    ? _ScreenState(
                        icon: Icons.shopping_basket_outlined,
                        message:
                            '${CategoryProductsText.empty} ${category.name}',
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: _ProductGrid(
                              controller: _scrollController,
                              products: products,
                              cartQtyById: cartQtyById,
                              wishlistPendingProductIds:
                                  wishlistPendingProductIds,
                              onOpen: (product) => _openProductDetail(
                                context,
                                product,
                              ),
                              onAdd: (product) {
                                ref
                                    .read(cartControllerProvider.notifier)
                                    .addProduct(product);
                              },
                              onIncrement: (product) {
                                ref
                                    .read(cartControllerProvider.notifier)
                                    .increment(product.id);
                              },
                              onDecrement: (product) {
                                ref
                                    .read(cartControllerProvider.notifier)
                                    .decrement(product.id);
                              },
                              wishlistedProductIds: wishlistedProductIds,
                              onToggleWishlist: (product) {
                                final currentSession = session;
                                if (currentSession == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        CategoryProductsText.loginRequired,
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                _toggleWishlist(
                                  context: context,
                                  ref: ref,
                                  userId: currentSession.uid,
                                  product: product,
                                  isWishlisted: wishlistedProductIds.contains(
                                    product.id,
                                  ),
                                );
                              },
                            ),
                          ),
                          _ProductListFooter(
                            isLoading: productListState?.isLoadingMore ?? false,
                            hasMore: productListState?.hasMore ?? false,
                            onLoadMore: () => _loadMore(
                              request: request,
                              showErrors: true,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
        loading: () => const AppLoadingState(),
        error: (error, _) => AppRetryState(
          icon: Icons.error_outline_rounded,
          title: CategoryProductsText.error,
          message: AppErrorHandler.messageFor(
            error,
            fallback: CategoryProductsText.errorSubtitle,
          ),
          onRetry: () {
            ref
                .read(categoryProductListProvider(request).notifier)
                .loadInitial();
          },
        ),
      ),
    );
  }

  void _openProductDetail(BuildContext context, Product product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(product: product),
      ),
    );
  }

  Future<void> _toggleWishlist({
    required BuildContext context,
    required WidgetRef ref,
    required String userId,
    required Product product,
    required bool isWishlisted,
  }) async {
    try {
      await ref.read(setProductWishlistedProvider)(
        userId: userId,
        productId: product.id,
        wishlisted: !isWishlisted,
      );
    } catch (error) {
      if (!context.mounted) return;

      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: CategoryProductsText.wishlistUpdateError,
      );
    }
  }

  Future<void> _loadMore({
    CategoryProductsRequest? request,
    required bool showErrors,
  }) async {
    final effectiveRequest = request ??
        CategoryProductsRequest(
          categoryId: widget.category.id,
          categoryName: widget.category.name,
        );

    try {
      await ref
          .read(categoryProductListProvider(effectiveRequest).notifier)
          .loadNext();
    } catch (error) {
      if (!mounted || !showErrors) return;

      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: CategoryProductsText.errorSubtitle,
      );
    }
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.category,
    required this.productCount,
  });

  final Category category;
  final int productCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Row(
        children: [
          _CategoryImage(imageUrl: category.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _productLabel(productCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _productLabel(int count) {
    if (count == 1) return CategoryProductsText.singleProduct;
    return '$count ${CategoryProductsText.multipleProducts}';
  }
}

class _CategoryImage extends StatelessWidget {
  const _CategoryImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = imageUrl.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: SizedBox(
        width: 56,
        height: 56,
        child: AppCachedNetworkImage(
          imageUrl: trimmedUrl,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          memCacheWidth: CategoryProductsConfig.categoryImageCacheExtent,
          memCacheHeight: CategoryProductsConfig.categoryImageCacheExtent,
          maxWidthDiskCache:
              CategoryProductsConfig.categoryImageDiskCacheExtent,
          maxHeightDiskCache:
              CategoryProductsConfig.categoryImageDiskCacheExtent,
          placeholder: const _CategoryImageFallback(),
          errorPlaceholder: const _CategoryImageFallback(),
        ),
      ),
    );
  }
}

class _CategoryImageFallback extends StatelessWidget {
  const _CategoryImageFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: AppColors.softGreen),
      child: Icon(
        Icons.local_grocery_store_rounded,
        color: AppColors.primary,
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({
    required this.controller,
    required this.products,
    required this.cartQtyById,
    required this.wishlistPendingProductIds,
    required this.wishlistedProductIds,
    required this.onOpen,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    required this.onToggleWishlist,
  });

  final ScrollController controller;
  final List<Product> products;
  final Map<String, int> cartQtyById;
  final Set<String> wishlistPendingProductIds;
  final Set<String> wishlistedProductIds;
  final ValueChanged<Product> onOpen;
  final ValueChanged<Product> onAdd;
  final ValueChanged<Product> onIncrement;
  final ValueChanged<Product> onDecrement;
  final ValueChanged<Product> onToggleWishlist;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final aspectRatio = constraints.maxWidth >= 720
            ? 0.90
            : (0.69 - (textScale - 1.0) * 0.18).clamp(0.52, 0.74);

        return GridView.builder(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          itemCount: products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: aspectRatio,
          ),
          itemBuilder: (context, index) {
            final product = products[index];

            return GkProductCard(
              product: product,
              quantity: cartQtyById[product.id] ?? 0,
              onTap: () => onOpen(product),
              onAdd: () => onAdd(product),
              onIncrement: () => onIncrement(product),
              onDecrement: () => onDecrement(product),
              isWishlisted: wishlistedProductIds.contains(product.id),
              isWishlistUpdating: wishlistPendingProductIds.contains(
                product.id,
              ),
              onToggleWishlist: () => onToggleWishlist(product),
            );
          },
        );
      },
    );
  }
}

class _ProductListFooter extends StatelessWidget {
  const _ProductListFooter({
    required this.isLoading,
    required this.hasMore,
    required this.onLoadMore,
  });

  final bool isLoading;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!hasMore) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: Text(
          CategoryProductsText.endOfList,
          style: TextStyle(
            color: AppColors.mutedText,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: OutlinedButton.icon(
        onPressed: onLoadMore,
        icon: const Icon(Icons.expand_more_rounded),
        label: const Text(CategoryProductsText.loadMore),
      ),
    );
  }
}

class _ScreenState extends StatelessWidget {
  const _ScreenState({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.softGreen,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryProductsText {
  const CategoryProductsText._();

  static const loginRequired = 'Please login to update wishlist';
  static const empty = 'No products found in';
  static const error = 'Unable to load category products';
  static const errorSubtitle = 'Please try again in a moment.';
  static const loadMore = 'Load more';
  static const endOfList = 'All loaded products are visible';
  static const wishlistUpdateError = 'Unable to update wishlist';
  static const singleProduct = '1 product';
  static const multipleProducts = 'products';
}

class CategoryProductsConfig {
  const CategoryProductsConfig._();

  static const categoryImageCacheExtent = 120;
  static const categoryImageDiskCacheExtent = 180;
  static const loadMoreExtent = 420.0;
}
