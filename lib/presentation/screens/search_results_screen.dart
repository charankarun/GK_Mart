import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error_handler.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../providers/auth_providers.dart';
import '../providers/catalog_providers.dart';
import '../providers/commerce_providers.dart';
import '../providers/search_provider.dart';
import '../providers/wishlist_provider.dart';
import '../widgets/app_cached_network_image.dart';
import 'category_products_screen.dart';
import 'product_detail_screen.dart';

class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({
    super.key,
    this.query = '',
  });

  final String query;

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;
  String _query = '';
  List<Category> _latestCategorySuggestions = const <Category>[];

  @override
  void initState() {
    super.initState();
    _query = widget.query.trim();
    _controller = TextEditingController(text: _query);
    _focusNode = FocusNode();
    _scrollController = ScrollController();
    _controller.addListener(_handleQueryChanged);
    _scrollController.addListener(_handleScroll);
    ref.read(productSearchQueryProvider.notifier).state = _query;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_handleQueryChanged);
    _scrollController.removeListener(_handleScroll);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    final nextQuery = _controller.text.trim();
    if (nextQuery == _query) {
      if (mounted) setState(() {});
      return;
    }

    setState(() => _query = nextQuery);
    ref.read(productSearchQueryProvider.notifier).state = nextQuery;
  }

  void _clearQuery() {
    _controller.clear();
    _focusNode.requestFocus();
  }

  void _handleSubmitted(String value) {
    final normalizedQuery = value.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return;

    for (final category in _latestCategorySuggestions) {
      final categoryName = category.name.trim().toLowerCase();
      if (categoryName == normalizedQuery ||
          categoryName.startsWith(normalizedQuery)) {
        _openCategoryProducts(category);
        return;
      }
    }

    _focusNode.unfocus();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > SearchConfig.loadMoreExtent) {
      return;
    }

    _loadMoreProducts(showErrors: false);
  }

  @override
  Widget build(BuildContext context) {
    final debouncedQueryAsync = ref.watch(debouncedSearchQueryProvider);
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
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          tooltip: SearchResultsText.back,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: _SearchField(
          controller: _controller,
          focusNode: _focusNode,
          onClear: _clearQuery,
          onSubmitted: _handleSubmitted,
        ),
      ),
      body: _query.isEmpty
          ? const _SearchStartState()
          : debouncedQueryAsync.when(
              data: (searchQuery) {
                if (searchQuery.isEmpty) return const _SearchLoadingList();

                final categorySuggestionsAsync = ref.watch(
                  categorySearchSuggestionsProvider(searchQuery),
                );
                final productListAsync = ref.watch(
                  productSearchResultsProvider(searchQuery),
                );
                final productListState = productListAsync.maybeWhen(
                  data: (state) => state,
                  orElse: () => null,
                );
                final categories = categorySuggestionsAsync.maybeWhen(
                  data: (categories) => categories,
                  orElse: () => const <Category>[],
                );
                _latestCategorySuggestions = categories;

                return productListAsync.when(
                  data: (state) {
                    final products = state.products;
                    if (products.isEmpty && categories.isEmpty) {
                      return _SearchState(
                        icon: Icons.search_off_rounded,
                        title: SearchResultsText.emptyTitle,
                        subtitle: SearchResultsText.emptySubtitle,
                        query: searchQuery,
                      );
                    }

                    return _SearchResultsList(
                      controller: _scrollController,
                      query: searchQuery,
                      categories: categories,
                      isLoadingCategories: categorySuggestionsAsync.isLoading,
                      products: products,
                      isLoadingMore: productListState?.isLoadingMore ?? false,
                      hasMore: productListState?.hasMore ?? false,
                      onLoadMore: () => _loadMoreProducts(showErrors: true),
                      cartQtyById: cartQtyById,
                      wishlistedProductIds: wishlistedProductIds,
                      wishlistPendingProductIds: wishlistPendingProductIds,
                      onOpenCategory: _openCategoryProducts,
                      onOpen: _openProductDetail,
                      onAdd: _addProduct,
                      onIncrement: _incrementProduct,
                      onDecrement: _decrementProduct,
                      onToggleWishlist: (product) {
                        final currentSession = session;
                        if (currentSession == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(SearchResultsText.loginRequired),
                            ),
                          );
                          return;
                        }

                        _toggleWishlist(
                          userId: currentSession.uid,
                          product: product,
                          isWishlisted: wishlistedProductIds.contains(
                            product.id,
                          ),
                        );
                      },
                    );
                  },
                  loading: () {
                    if (categories.isNotEmpty) {
                      return _SearchResultsList(
                        controller: _scrollController,
                        query: searchQuery,
                        categories: categories,
                        isLoadingCategories: categorySuggestionsAsync.isLoading,
                        products: const <Product>[],
                        isLoadingMore: true,
                        hasMore: false,
                        onLoadMore: () {},
                        cartQtyById: const <String, int>{},
                        wishlistedProductIds: const <String>{},
                        wishlistPendingProductIds: const <String>{},
                        onOpenCategory: _openCategoryProducts,
                        onOpen: (_) {},
                        onAdd: (_) {},
                        onIncrement: (_) {},
                        onDecrement: (_) {},
                        onToggleWishlist: (_) {},
                      );
                    }
                    return const _SearchLoadingList();
                  },
                  error: (error, _) => _SearchState(
                    icon: Icons.error_outline_rounded,
                    title: SearchResultsText.error,
                    subtitle: AppErrorHandler.messageFor(
                      error,
                      fallback: SearchResultsText.errorSubtitle,
                    ),
                    onRetry: () {
                      ref
                          .read(
                            productSearchResultsProvider(searchQuery).notifier,
                          )
                          .loadInitial();
                    },
                  ),
                );
              },
              loading: () => const _SearchLoadingList(),
              error: (error, _) => _SearchState(
                icon: Icons.error_outline_rounded,
                title: SearchResultsText.error,
                subtitle: AppErrorHandler.messageFor(
                  error,
                  fallback: SearchResultsText.errorSubtitle,
                ),
                onRetry: () {
                  ref.invalidate(debouncedSearchQueryProvider);
                },
              ),
            ),
    );
  }

  void _openProductDetail(Product product) {
    _focusNode.unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(product: product),
      ),
    );
  }

  void _openCategoryProducts(Category category) {
    _focusNode.unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryProductsScreen(category: category),
      ),
    );
  }

  void _addProduct(Product product) {
    ref.read(cartControllerProvider.notifier).addProduct(product);
  }

  void _incrementProduct(Product product) {
    ref.read(cartControllerProvider.notifier).increment(product.id);
  }

  void _decrementProduct(Product product) {
    ref.read(cartControllerProvider.notifier).decrement(product.id);
  }

  Future<void> _toggleWishlist({
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
      if (!mounted) return;

      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: SearchResultsText.wishlistUpdateError,
      );
    }
  }

  Future<void> _loadMoreProducts({required bool showErrors}) async {
    final searchQuery = ref.read(debouncedSearchQueryProvider).maybeWhen(
          data: (query) => query,
          orElse: () => '',
        );
    if (searchQuery.trim().isEmpty) return;

    try {
      await ref
          .read(productSearchResultsProvider(searchQuery).notifier)
          .loadNext();
    } catch (error) {
      if (!mounted || !showErrors) return;

      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: SearchResultsText.errorSubtitle,
      );
    }
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onClear,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        height: 46,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            enableSuggestions: true,
            onSubmitted: onSubmitted,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: SearchResultsText.searchHint,
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.mutedText, size: 20),
              suffixIcon: controller.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: SearchResultsText.clearSearch,
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: onClear,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({
    required this.controller,
    required this.query,
    required this.categories,
    required this.isLoadingCategories,
    required this.products,
    required this.isLoadingMore,
    required this.hasMore,
    required this.onLoadMore,
    required this.cartQtyById,
    required this.wishlistedProductIds,
    required this.wishlistPendingProductIds,
    required this.onOpenCategory,
    required this.onOpen,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    required this.onToggleWishlist,
  });

  final ScrollController controller;
  final String query;
  final List<Category> categories;
  final bool isLoadingCategories;
  final List<Product> products;
  final bool isLoadingMore;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final Map<String, int> cartQtyById;
  final Set<String> wishlistedProductIds;
  final Set<String> wishlistPendingProductIds;
  final ValueChanged<Category> onOpenCategory;
  final ValueChanged<Product> onOpen;
  final ValueChanged<Product> onAdd;
  final ValueChanged<Product> onIncrement;
  final ValueChanged<Product> onDecrement;
  final ValueChanged<Product> onToggleWishlist;

  @override
  Widget build(BuildContext context) {
    final hasCategoryBlock = categories.isNotEmpty || isLoadingCategories;
    final hasProductFooter = products.isNotEmpty || isLoadingMore;
    final itemCount = 1 +
        (hasCategoryBlock ? 1 : 0) +
        products.length +
        (hasProductFooter ? 1 : 0);

    return ListView.separated(
      controller: controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: itemCount,
      separatorBuilder: (_, index) {
        return SizedBox(height: index == 0 ? 10 : 12);
      },
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SearchResultHeader(
            query: query,
            productCount: products.length,
            categoryCount: categories.length,
          );
        }

        var productIndex = index - 1;
        if (hasCategoryBlock) {
          if (productIndex == 0) {
            return _CategorySuggestionsSection(
              categories: categories,
              isLoading: isLoadingCategories,
              onOpenCategory: onOpenCategory,
            );
          }
          productIndex -= 1;
        }

        if (productIndex >= products.length && hasProductFooter) {
          return _ProductListFooter(
            isLoading: isLoadingMore,
            hasMore: hasMore,
            onLoadMore: onLoadMore,
          );
        }

        final product = products[productIndex];
        return _SearchProductTile(
          product: product,
          quantity: cartQtyById[product.id] ?? 0,
          isWishlisted: wishlistedProductIds.contains(product.id),
          isWishlistUpdating: wishlistPendingProductIds.contains(product.id),
          onOpen: () => onOpen(product),
          onAdd: () => onAdd(product),
          onIncrement: () => onIncrement(product),
          onDecrement: () => onDecrement(product),
          onToggleWishlist: () => onToggleWishlist(product),
        );
      },
    );
  }
}

class _SearchResultHeader extends StatelessWidget {
  const _SearchResultHeader({
    required this.query,
    required this.productCount,
    required this.categoryCount,
  });

  final String query;
  final int productCount;
  final int categoryCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                query,
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
                _resultLabel(
                  productCount: productCount,
                  categoryCount: categoryCount,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.bolt_rounded, color: AppColors.accent),
      ],
    );
  }

  static String _resultLabel({
    required int productCount,
    required int categoryCount,
  }) {
    final productLabel = productCount == 1
        ? SearchResultsText.singleResult
        : '$productCount ${SearchResultsText.multipleResults}';
    if (categoryCount <= 0) return productLabel;
    if (categoryCount == 1) {
      return '$productLabel, ${SearchResultsText.singleCategoryResult}';
    }
    return '$productLabel, $categoryCount ${SearchResultsText.categoryResults}';
  }
}

class _CategorySuggestionsSection extends StatelessWidget {
  const _CategorySuggestionsSection({
    required this.categories,
    required this.isLoading,
    required this.onOpenCategory,
  });

  final List<Category> categories;
  final bool isLoading;
  final ValueChanged<Category> onOpenCategory;

  @override
  Widget build(BuildContext context) {
    if (isLoading && categories.isEmpty) {
      return const _CategorySuggestionSkeleton();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          SearchResultsText.categories,
          style: TextStyle(
            color: AppColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final category = categories[index];
              return _CategorySuggestionTile(
                category: category,
                onTap: () => onOpenCategory(category),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CategorySuggestionTile extends StatelessWidget {
  const _CategorySuggestionTile({
    required this.category,
    required this.onTap,
  });

  final Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 106,
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.soft,
            ),
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: AppCachedNetworkImage(
                      imageUrl: category.imageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: SearchResultsConfig.categoryImageExtent,
                      memCacheHeight: SearchResultsConfig.categoryImageExtent,
                      maxWidthDiskCache:
                          SearchResultsConfig.categoryImageDiskExtent,
                      maxHeightDiskCache:
                          SearchResultsConfig.categoryImageDiskExtent,
                      placeholder: const _ImagePlaceholder(),
                      errorPlaceholder: const _ImagePlaceholder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    category.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 12,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategorySuggestionSkeleton extends StatelessWidget {
  const _CategorySuggestionSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return Container(
            width: 106,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: AppColors.border),
            ),
          );
        },
      ),
    );
  }
}

class _SearchProductTile extends StatelessWidget {
  const _SearchProductTile({
    required this.product,
    required this.quantity,
    required this.isWishlisted,
    required this.isWishlistUpdating,
    required this.onOpen,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    required this.onToggleWishlist,
  });

  final Product product;
  final int quantity;
  final bool isWishlisted;
  final bool isWishlistUpdating;
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onToggleWishlist;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.soft,
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SearchProductImage(imageUrl: product.imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          height: 1.18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (product.unit.trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          product.unit,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.mutedText,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 9),
                      _PriceLine(product: product),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _WishlistIconButton(
                    isWishlisted: isWishlisted,
                    isLoading: isWishlistUpdating,
                    onPressed: onToggleWishlist,
                  ),
                  const SizedBox(height: 12),
                  _MiniCartAction(
                    isAvailable: product.isAvailable,
                    quantity: quantity,
                    onAdd: onAdd,
                    onIncrement: onIncrement,
                    onDecrement: onDecrement,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchProductImage extends StatelessWidget {
  const _SearchProductImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: SizedBox(
        width: 76,
        height: 84,
        child: AppCachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          memCacheWidth: SearchResultsConfig.imageCacheWidth,
          memCacheHeight: SearchResultsConfig.imageCacheHeight,
          maxWidthDiskCache: SearchResultsConfig.imageDiskCacheWidth,
          maxHeightDiskCache: SearchResultsConfig.imageDiskCacheHeight,
          placeholder: const _ImagePlaceholder(),
          errorPlaceholder: const _ImagePlaceholder(),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const AppImagePlaceholder(
      icon: Icons.local_grocery_store_rounded,
      iconSize: 28,
    );
  }
}

class _WishlistIconButton extends StatelessWidget {
  const _WishlistIconButton({
    required this.isWishlisted,
    required this.isLoading,
    required this.onPressed,
  });

  final bool isWishlisted;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isWishlisted
          ? SearchResultsText.removeFromWishlist
          : SearchResultsText.addToWishlist,
      child: SizedBox(
        width: 34,
        height: 34,
        child: IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          onPressed: isLoading ? null : onPressed,
          icon: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isWishlisted
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 18,
                ),
          color: isWishlisted ? SearchResultsColors.heart : AppColors.text,
        ),
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final hasDiscount = _discountPercent(product) > 0;

    return Wrap(
      spacing: 7,
      runSpacing: 3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '\u20B9${_formatPrice(product.sellingPrice)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (hasDiscount)
          Text(
            '\u20B9${_formatPrice(product.price)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.lineThrough,
            ),
          ),
      ],
    );
  }
}

class _MiniCartAction extends StatelessWidget {
  const _MiniCartAction({
    required this.isAvailable,
    required this.quantity,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
  });

  final bool isAvailable;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    if (!isAvailable) {
      return Container(
        width: 92,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: const Text(
          SearchResultsText.outOfStock,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.mutedText,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    if (quantity <= 0) {
      return SizedBox(
        width: 84,
        height: 34,
        child: FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text(SearchResultsText.add),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 94,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _QuantityButton(icon: Icons.remove_rounded, onTap: onDecrement),
          Text(
            quantity.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          _QuantityButton(icon: Icons.add_rounded, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: SizedBox(
        width: 31,
        height: 34,
        child: Icon(icon, color: Colors.white, size: 17),
      ),
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
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!hasMore) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            SearchResultsText.endOfList,
            style: TextStyle(
              color: AppColors.mutedText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Center(
      child: OutlinedButton.icon(
        onPressed: onLoadMore,
        icon: const Icon(Icons.expand_more_rounded),
        label: const Text(SearchResultsText.loadMore),
      ),
    );
  }
}

class _SearchStartState extends StatelessWidget {
  const _SearchStartState();

  @override
  Widget build(BuildContext context) {
    return const _SearchState(
      icon: Icons.search_rounded,
      title: SearchResultsText.startTitle,
      subtitle: SearchResultsText.startSubtitle,
    );
  }
}

class _SearchState extends StatelessWidget {
  const _SearchState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.query,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? query;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final visibleQuery = query?.trim();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: AppColors.softGreen,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 34),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (visibleQuery != null && visibleQuery.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '"$visibleQuery"',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.mutedText,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(SearchResultsText.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchLoadingList extends StatelessWidget {
  const _SearchLoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Container(
          height: 104,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 76,
                height: 84,
                decoration: BoxDecoration(
                  color: AppColors.softGreen,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SkeletonLine(widthFactor: index.isEven ? 0.78 : 0.62),
                    const SizedBox(height: 10),
                    const _SkeletonLine(widthFactor: 0.42),
                    const SizedBox(height: 14),
                    const _SkeletonLine(widthFactor: 0.34),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 10,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

int _discountPercent(Product product) {
  if (product.discountPrice <= 0 ||
      product.price <= 0 ||
      product.discountPrice >= product.price) {
    return 0;
  }

  return (((product.price - product.discountPrice) / product.price) * 100)
      .round();
}

String _formatPrice(double price) {
  return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
}

class SearchResultsColors {
  const SearchResultsColors._();

  static const heart = Color(0xFFE11D48);
}

class SearchResultsConfig {
  const SearchResultsConfig._();

  static const imageCacheWidth = 160;
  static const imageCacheHeight = 180;
  static const imageDiskCacheWidth = 220;
  static const imageDiskCacheHeight = 250;
  static const categoryImageExtent = 80;
  static const categoryImageDiskExtent = 120;
}

class SearchResultsText {
  const SearchResultsText._();

  static const back = 'Back';
  static const searchHint = 'Search products';
  static const clearSearch = 'Clear search';
  static const loginRequired = 'Please login to update wishlist';
  static const startTitle = 'Find your groceries';
  static const startSubtitle = 'Type a product name to see instant matches.';
  static const emptyTitle = 'No matching products';
  static const emptySubtitle = 'Try another product name or a shorter search.';
  static const error = 'Unable to search products';
  static const errorSubtitle = 'Please try again in a moment.';
  static const retry = 'Retry';
  static const categories = 'Matching categories';
  static const wishlistUpdateError = 'Unable to update wishlist';
  static const addToWishlist = 'Add to wishlist';
  static const removeFromWishlist = 'Remove from wishlist';
  static const add = 'Add';
  static const outOfStock = 'Out';
  static const loadMore = 'Load more';
  static const endOfList = 'All loaded products are visible';
  static const singleResult = '1 instant match';
  static const multipleResults = 'instant matches';
  static const singleCategoryResult = '1 category';
  static const categoryResults = 'categories';
}
