import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../providers/auth_providers.dart';
import '../providers/catalog_providers.dart';
import '../providers/commerce_providers.dart';
import '../providers/search_provider.dart';
import '../providers/wishlist_provider.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final searchFocusNode = FocusNode();
  final searchController = TextEditingController();
  String? selectedCategoryId;
  _ProductViewMode viewMode = _ProductViewMode.grid;

  @override
  void initState() {
    super.initState();
    searchFocusNode.addListener(_handleSearchFocusChanged);
  }

  @override
  void dispose() {
    searchFocusNode.removeListener(_handleSearchFocusChanged);
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSearchFocusChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final profile = ref.watch(currentUserProfileProvider).maybeWhen(
          data: (user) => user,
          orElse: () => null,
        );
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final productsAsync = ref.watch(productsStreamProvider);
    final cartItems = ref.watch(cartItemsProvider);
    final cartCount = ref.watch(cartItemCountProvider);
    final cartQtyById = {
      for (final item in cartItems) item.productId: item.quantity,
    };
    final wishlistedProductIds = ref.watch(
      wishlistProductIdSetProvider(session.uid),
    );
    final categories = categoriesAsync.maybeWhen(
      data: (items) => items,
      orElse: () => const <Category>[],
    );
    final selectedCategory = _selectedCategory(categories);

    return SafeArea(
      child: Container(
        color: const Color(0xFFF7F8FA),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HomeHeader(
              displayName: profile?.displayName ?? HomeText.defaultGreetingName,
              address: profile?.address ?? '',
              cartCount: cartCount,
              onCartTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                );
              },
            ),
            _SearchSection(
              controller: searchController,
              focusNode: searchFocusNode,
              isFocused: searchFocusNode.hasFocus,
              onProductSelected: _openProductDetail,
            ),
            const SizedBox(height: 12),
            _CategoryStrip(
              categoriesAsync: categoriesAsync,
              selectedCategoryId: selectedCategoryId,
              onCategorySelected: (categoryId) {
                setState(() => selectedCategoryId = categoryId);
              },
            ),
            const SizedBox(height: 10),
            _ProductsHeader(
              title: selectedCategory?.name ?? HomeText.allProducts,
              viewMode: viewMode,
              onViewModeChanged: (mode) {
                setState(() => viewMode = mode);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _ProductsBody(
                productsAsync: productsAsync,
                selectedCategoryId: selectedCategoryId,
                selectedCategory: selectedCategory,
                cartQtyById: cartQtyById,
                wishlistedProductIds: wishlistedProductIds,
                viewMode: viewMode,
                onOpen: _openProductDetail,
                onAdd: (product) {
                  ref.read(cartControllerProvider.notifier).addProduct(
                        product,
                      );
                },
                onIncrement: (product) {
                  ref.read(cartControllerProvider.notifier).increment(
                        product.id,
                      );
                },
                onDecrement: (product) {
                  ref.read(cartControllerProvider.notifier).decrement(
                        product.id,
                      );
                },
                onToggleWishlist: (product) {
                  _toggleWishlist(
                    userId: session.uid,
                    product: product,
                    isWishlisted: wishlistedProductIds.contains(product.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openProductDetail(Product product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(product: product),
      ),
    );
  }

  Category? _selectedCategory(List<Category> categories) {
    final categoryId = selectedCategoryId;
    if (categoryId == null) return null;

    for (final category in categories) {
      if (category.id == categoryId) return category;
    }

    return null;
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
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(HomeText.wishlistUpdateError)),
      );
    }
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.displayName,
    required this.address,
    required this.cartCount,
    required this.onCartTap,
  });

  final String displayName;
  final String address;
  final int cartCount;
  final VoidCallback onCartTap;

  @override
  Widget build(BuildContext context) {
    final visibleAddress = address.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${HomeText.greetingPrefix} $displayName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (visibleAddress.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 15,
                        color: Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          visibleAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF111827),
                ),
                icon: const Icon(Icons.shopping_cart),
                onPressed: onCartTap,
              ),
              if (cartCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      cartCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchSection extends ConsumerWidget {
  const _SearchSection({
    required this.controller,
    required this.focusNode,
    required this.isFocused,
    required this.onProductSelected,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isFocused;
  final ValueChanged<Product> onProductSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasQuery = ref.watch(
      productSearchQueryProvider.select((query) => query.trim().isNotEmpty),
    );
    final suggestionsAsync = isFocused && hasQuery
        ? ref.watch(productSearchSuggestionsProvider)
        : const AsyncData(<Product>[]);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SearchBar(
          controller: controller,
          focusNode: focusNode,
          hasQuery: hasQuery,
          onChanged: (value) {
            ref.read(productSearchQueryProvider.notifier).state = value;
          },
          onClear: () {
            controller.clear();
            ref.read(productSearchQueryProvider.notifier).state = '';
            focusNode.requestFocus();
          },
        ),
        if (isFocused && hasQuery)
          _SearchSuggestionsDropdown(
            suggestionsAsync: suggestionsAsync,
            onProductSelected: (product) {
              focusNode.unfocus();
              onProductSelected(product);
            },
          ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.hasQuery,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _SearchUi.barHeight,
      margin: const EdgeInsets.symmetric(horizontal: _SearchUi.sideMargin),
      padding: const EdgeInsets.symmetric(horizontal: _SearchUi.barPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_SearchUi.radius),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        decoration: InputDecoration(
          icon: Icon(Icons.search, color: Colors.grey.shade700),
          hintText: HomeText.searchHint,
          border: InputBorder.none,
          suffixIcon: hasQuery
              ? IconButton(
                  tooltip: HomeText.clearSearch,
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                )
              : null,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _SearchSuggestionsDropdown extends StatelessWidget {
  const _SearchSuggestionsDropdown({
    required this.suggestionsAsync,
    required this.onProductSelected,
  });

  final AsyncValue<List<Product>> suggestionsAsync;
  final ValueChanged<Product> onProductSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        _SearchUi.sideMargin,
        _SearchUi.dropdownTopGap,
        _SearchUi.sideMargin,
        0,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_SearchUi.radius),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_SearchUi.radius),
        child: suggestionsAsync.when(
          data: (products) {
            if (products.isEmpty) {
              return const _SearchMessage(message: HomeText.noSearchResults);
            }

            return ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: _SearchUi.maxDropdownHeight,
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: products.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: Colors.grey.shade200,
                ),
                itemBuilder: (context, index) {
                  final product = products[index];

                  return _SearchSuggestionTile(
                    product: product,
                    onTap: () => onProductSelected(product),
                  );
                },
              ),
            );
          },
          loading: () => const _SearchMessage(
            message: HomeText.searchingProducts,
            showProgress: true,
          ),
          error: (_, __) => const _SearchMessage(
            message: HomeText.searchError,
          ),
        ),
      ),
    );
  }
}

class _SearchSuggestionTile extends StatelessWidget {
  const _SearchSuggestionTile({
    required this.product,
    required this.onTap,
  });

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _SearchUi.tileHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _SearchUi.tileHorizontalPadding,
            vertical: _SearchUi.tileVerticalPadding,
          ),
          child: Row(
            children: [
              _SearchSuggestionImage(imageUrl: product.imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\u20B9${_formatPrice(product.sellingPrice)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF166534),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.north_east,
                size: 17,
                color: Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchSuggestionImage extends StatelessWidget {
  const _SearchSuggestionImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: _SearchUi.imageSize,
      height: _SearchUi.imageSize,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(_SearchUi.imageRadius),
      ),
      child: const Icon(Icons.image, color: Colors.black45, size: 20),
    );

    if (imageUrl.trim().isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(_SearchUi.imageRadius),
      child: Image.network(
        imageUrl,
        width: _SearchUi.imageSize,
        height: _SearchUi.imageSize,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
    required this.message,
    this.showProgress = false,
  });

  final String message;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _SearchUi.messageHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showProgress) ...[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchUi {
  const _SearchUi._();

  static const sideMargin = 14.0;
  static const radius = 8.0;
  static const barHeight = 48.0;
  static const barPadding = 12.0;
  static const dropdownTopGap = 8.0;
  static const maxVisibleTiles = 5;
  static const tileHeight = 66.0;
  static const maxDropdownHeight = tileHeight * maxVisibleTiles;
  static const tileHorizontalPadding = 12.0;
  static const tileVerticalPadding = 8.0;
  static const imageSize = 48.0;
  static const imageRadius = 8.0;
  static const messageHeight = 82.0;
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categoriesAsync,
    required this.selectedCategoryId,
    required this.onCategorySelected,
  });

  final AsyncValue<List<Category>> categoriesAsync;
  final String? selectedCategoryId;
  final ValueChanged<String?> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: categoriesAsync.when(
        data: (categories) {
          if (categories.isEmpty) {
            return const Center(child: Text(HomeText.noCategories));
          }

          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: categories.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _CategoryTile(
                  label: HomeText.allCategories,
                  imageUrl: '',
                  isSelected: selectedCategoryId == null,
                  onTap: () => onCategorySelected(null),
                );
              }

              final category = categories[index - 1];
              return _CategoryTile(
                label: category.name,
                imageUrl: category.imageUrl,
                isSelected: selectedCategoryId == category.id,
                onTap: () => onCategorySelected(category.id),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text(HomeText.categoriesError)),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.imageUrl,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String imageUrl;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isSelected ? const Color(0xFF16A34A) : Colors.grey.shade200;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 82,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
        ),
        child: Column(
          children: [
            _CategoryImage(imageUrl: imageUrl, isSelected: isSelected),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.15,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? const Color(0xFF166534)
                    : const Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryImage extends StatelessWidget {
  const _CategoryImage({
    required this.imageUrl,
    required this.isSelected,
  });

  final String imageUrl;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: isSelected ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.category,
        color: isSelected ? Colors.green.shade700 : Colors.grey.shade600,
      ),
    );

    if (imageUrl.trim().isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}

class _ProductsHeader extends StatelessWidget {
  const _ProductsHeader({
    required this.title,
    required this.viewMode,
    required this.onViewModeChanged,
  });

  final String title;
  final _ProductViewMode viewMode;
  final ValueChanged<_ProductViewMode> onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _ViewModeButton(
            icon: Icons.grid_view,
            tooltip: HomeText.gridView,
            isSelected: viewMode == _ProductViewMode.grid,
            onTap: () => onViewModeChanged(_ProductViewMode.grid),
          ),
          const SizedBox(width: 6),
          _ViewModeButton(
            icon: Icons.view_list,
            tooltip: HomeText.listView,
            isSelected: viewMode == _ProductViewMode.list,
            onTap: () => onViewModeChanged(_ProductViewMode.list),
          ),
        ],
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  const _ViewModeButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFDCFCE7) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  isSelected ? const Color(0xFF16A34A) : Colors.grey.shade200,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected ? const Color(0xFF166534) : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

class _ProductsBody extends StatelessWidget {
  const _ProductsBody({
    required this.productsAsync,
    required this.selectedCategoryId,
    required this.selectedCategory,
    required this.cartQtyById,
    required this.wishlistedProductIds,
    required this.viewMode,
    required this.onOpen,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    required this.onToggleWishlist,
  });

  final AsyncValue<List<Product>> productsAsync;
  final String? selectedCategoryId;
  final Category? selectedCategory;
  final Map<String, int> cartQtyById;
  final Set<String> wishlistedProductIds;
  final _ProductViewMode viewMode;
  final ValueChanged<Product> onOpen;
  final ValueChanged<Product> onAdd;
  final ValueChanged<Product> onIncrement;
  final ValueChanged<Product> onDecrement;
  final ValueChanged<Product> onToggleWishlist;

  @override
  Widget build(BuildContext context) {
    return productsAsync.when(
      data: (products) {
        final filteredProducts = products.where(_matchesCategory).toList();

        if (filteredProducts.isEmpty) {
          return const Center(child: Text(HomeText.noProducts));
        }

        if (viewMode == _ProductViewMode.list) {
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            itemCount: filteredProducts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final product = filteredProducts[index];
              return _ProductListCard(
                product: product,
                quantity: cartQtyById[product.id] ?? 0,
                isWishlisted: wishlistedProductIds.contains(product.id),
                onOpen: () => onOpen(product),
                onAdd: () => onAdd(product),
                onIncrement: () => onIncrement(product),
                onDecrement: () => onDecrement(product),
                onToggleWishlist: () => onToggleWishlist(product),
              );
            },
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth >= 720 ? 3 : 2;

            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              itemCount: filteredProducts.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: constraints.maxWidth >= 720 ? 0.78 : 0.66,
              ),
              itemBuilder: (context, index) {
                final product = filteredProducts[index];
                return _ProductGridCard(
                  product: product,
                  quantity: cartQtyById[product.id] ?? 0,
                  isWishlisted: wishlistedProductIds.contains(product.id),
                  onOpen: () => onOpen(product),
                  onAdd: () => onAdd(product),
                  onIncrement: () => onIncrement(product),
                  onDecrement: () => onDecrement(product),
                  onToggleWishlist: () => onToggleWishlist(product),
                );
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text(HomeText.productsError)),
    );
  }

  bool _matchesCategory(Product product) {
    final categoryId = selectedCategoryId;
    if (categoryId == null) return true;

    final productCategory = product.categoryId.trim().toLowerCase();
    if (productCategory == categoryId.trim().toLowerCase()) return true;

    final categoryName = selectedCategory?.name.trim().toLowerCase();
    return categoryName != null &&
        categoryName.isNotEmpty &&
        productCategory == categoryName;
  }
}

class _ProductGridCard extends StatelessWidget {
  const _ProductGridCard({
    required this.product,
    required this.quantity,
    required this.isWishlisted,
    required this.onOpen,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    required this.onToggleWishlist,
  });

  final Product product;
  final int quantity;
  final bool isWishlisted;
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onToggleWishlist;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProductImage(
                imageUrl: product.imageUrl,
                isAvailable: product.isAvailable,
                discountPercent: _discountPercent(product),
                isWishlisted: isWishlisted,
                onToggleWishlist: onToggleWishlist,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      if (product.unit.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          product.unit,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const Spacer(),
                      _ProductPrice(product: product),
                      const SizedBox(height: 8),
                      _CartAction(
                        isAvailable: product.isAvailable,
                        quantity: quantity,
                        onAdd: onAdd,
                        onIncrement: onIncrement,
                        onDecrement: onDecrement,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductListCard extends StatelessWidget {
  const _ProductListCard({
    required this.product,
    required this.quantity,
    required this.isWishlisted,
    required this.onOpen,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    required this.onToggleWishlist,
  });

  final Product product;
  final int quantity;
  final bool isWishlisted;
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onToggleWishlist;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 92,
                child: _ProductImage(
                  imageUrl: product.imageUrl,
                  isAvailable: product.isAvailable,
                  discountPercent: _discountPercent(product),
                  isWishlisted: isWishlisted,
                  onToggleWishlist: onToggleWishlist,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (product.unit.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        product.unit,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: _ProductPrice(product: product)),
                        const SizedBox(width: 10),
                        _CartAction(
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
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({
    required this.imageUrl,
    required this.isAvailable,
    required this.discountPercent,
    required this.isWishlisted,
    required this.onToggleWishlist,
  });

  final String imageUrl;
  final bool isAvailable;
  final int discountPercent;
  final bool isWishlisted;
  final VoidCallback onToggleWishlist;

  @override
  Widget build(BuildContext context) {
    final placeholder = AspectRatio(
      aspectRatio: 1.18,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
        child: const Center(child: Icon(Icons.image)),
      ),
    );

    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          child: imageUrl.trim().isEmpty
              ? placeholder
              : AspectRatio(
                  aspectRatio: 1.18,
                  child: Image.network(
                    imageUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => placeholder,
                  ),
                ),
        ),
        if (discountPercent > 0)
          Positioned(
            left: 6,
            top: 6,
            child: _DiscountBadge(discountPercent: discountPercent),
          ),
        if (!isAvailable)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.58),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    HomeText.outOfStock,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          right: 6,
          top: 6,
          child: Tooltip(
            message: isWishlisted
                ? HomeText.removeFromWishlist
                : HomeText.addToWishlist,
            child: Material(
              color: Colors.white.withValues(alpha: 0.94),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onToggleWishlist,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(
                    isWishlisted ? Icons.favorite : Icons.favorite_border,
                    color: isWishlisted
                        ? const Color(0xFFE11D48)
                        : Colors.grey.shade700,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge({required this.discountPercent});

  final int discountPercent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFF97316)),
      ),
      child: Text(
        '$discountPercent% ${HomeText.off}',
        style: const TextStyle(
          color: Color(0xFFC2410C),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ProductPrice extends StatelessWidget {
  const _ProductPrice({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final hasDiscount = _discountPercent(product) > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u20B9${_formatPrice(product.sellingPrice)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF166534),
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        if (hasDiscount)
          Text(
            '\u20B9${_formatPrice(product.price)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              decoration: TextDecoration.lineThrough,
            ),
          ),
      ],
    );
  }
}

String _formatPrice(double price) {
  return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
}

class _CartAction extends StatelessWidget {
  const _CartAction({
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
        height: 32,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          HomeText.notAvailable,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (quantity <= 0) {
      return SizedBox(
        height: 32,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF15803D),
            side: const BorderSide(color: Color(0xFF16A34A)),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
          ),
          onPressed: onAdd,
          child: const Text(HomeText.add),
        ),
      );
    }

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFF16A34A),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QuantityButton(icon: Icons.remove, onTap: onDecrement),
          SizedBox(
            width: 28,
            child: Text(
              quantity.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _QuantityButton(icon: Icons.add, onTap: onIncrement),
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
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: SizedBox(
        width: 30,
        height: 32,
        child: Icon(icon, color: Colors.white, size: 17),
      ),
    );
  }
}

int _discountPercent(Product product) {
  if (product.discountPrice <= 0 || product.discountPrice >= product.price) {
    return 0;
  }

  return (((product.price - product.discountPrice) / product.price) * 100)
      .round();
}

enum _ProductViewMode { grid, list }

class HomeText {
  const HomeText._();

  static const defaultGreetingName = 'there';
  static const greetingPrefix = 'Hello,';
  static const searchHint = 'Search products';
  static const clearSearch = 'Clear search';
  static const searchingProducts = 'Searching products';
  static const noSearchResults = 'No products found';
  static const searchError = 'Unable to search products';
  static const allCategories = 'All';
  static const allProducts = 'All Products';
  static const noCategories = 'No categories added';
  static const categoriesError = 'Unable to load categories';
  static const noProducts = 'No products found';
  static const productsError = 'Unable to load products';
  static const gridView = 'Grid view';
  static const listView = 'List view';
  static const outOfStock = 'Out of Stock';
  static const notAvailable = 'NA';
  static const add = 'ADD';
  static const off = 'OFF';
  static const addToWishlist = 'Add to wishlist';
  static const removeFromWishlist = 'Remove from wishlist';
  static const wishlistUpdateError = 'Unable to update wishlist';
}
