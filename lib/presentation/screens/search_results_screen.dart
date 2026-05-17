import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error_handler.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/product.dart';
import '../providers/auth_providers.dart';
import '../providers/catalog_providers.dart';
import '../providers/commerce_providers.dart';
import '../providers/wishlist_provider.dart';
import '../widgets/app_state_widgets.dart';
import '../widgets/product_card.dart';
import 'product_detail_screen.dart';

class SearchResultsScreen extends ConsumerWidget {
  const SearchResultsScreen({
    super.key,
    required this.query,
  });

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchQuery = query.trim();
    final productListAsync =
        ref.watch(productSearchResultsProvider(searchQuery));
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
      appBar: AppBar(title: const Text(SearchResultsText.title)),
      body: productsAsync.when(
        data: (products) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SearchResultsHeader(
                query: searchQuery,
                resultCount: products.length,
              ),
              Expanded(
                child: products.isEmpty
                    ? const _ScreenState(
                        icon: Icons.search_off_rounded,
                        message: SearchResultsText.empty,
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: _ProductGrid(
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
                                        SearchResultsText.loginRequired,
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
                              context: context,
                              ref: ref,
                              query: searchQuery,
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
          title: SearchResultsText.error,
          message: AppErrorHandler.messageFor(
            error,
            fallback: SearchResultsText.errorSubtitle,
          ),
          onRetry: () {
            ref
                .read(productSearchResultsProvider(searchQuery).notifier)
                .loadInitial();
          },
        ),
      ),
    );
  }

  static void _openProductDetail(BuildContext context, Product product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(product: product),
      ),
    );
  }

  static Future<void> _toggleWishlist({
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
        fallbackMessage: SearchResultsText.wishlistUpdateError,
      );
    }
  }

  static Future<void> _loadMore({
    required BuildContext context,
    required WidgetRef ref,
    required String query,
  }) async {
    try {
      await ref.read(productSearchResultsProvider(query).notifier).loadNext();
    } catch (error) {
      if (!context.mounted) return;

      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: SearchResultsText.errorSubtitle,
      );
    }
  }
}

class _SearchResultsHeader extends StatelessWidget {
  const _SearchResultsHeader({
    required this.query,
    required this.resultCount,
  });

  final String query;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '"$query"',
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
                  _resultLabel(resultCount),
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

  static String _resultLabel(int count) {
    if (count == 1) return SearchResultsText.singleResult;
    return '$count ${SearchResultsText.multipleResults}';
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspectRatio = constraints.maxWidth >= 720 ? 0.98 : 0.78;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
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
          SearchResultsText.endOfList,
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
        label: const Text(SearchResultsText.loadMore),
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

class SearchResultsText {
  const SearchResultsText._();

  static const title = 'Search Results';
  static const loginRequired = 'Please login to update wishlist';
  static const empty = 'No matching products found';
  static const error = 'Unable to load search results';
  static const errorSubtitle = 'Please try again in a moment.';
  static const loadMore = 'Load more';
  static const endOfList = 'All loaded products are visible';
  static const wishlistUpdateError = 'Unable to update wishlist';
  static const singleResult = '1 matching product';
  static const multipleResults = 'matching products';
}
