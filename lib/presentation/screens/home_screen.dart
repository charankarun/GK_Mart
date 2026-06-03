import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error_handler.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../navigation/customer_navigation_scope.dart';
import '../providers/auth_providers.dart';
import '../providers/catalog_providers.dart';
import '../providers/commerce_providers.dart';
import '../providers/wishlist_provider.dart';
import '../widgets/app_cached_network_image.dart';
import '../widgets/customer_support_sheet.dart';
import '../widgets/product_card.dart';
import 'address_screen.dart';
import 'category_products_screen.dart';
import 'orders_screen.dart';
import 'product_detail_screen.dart';
import 'search_results_screen.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _scrollController = ScrollController();
  bool _didPrecacheBanner = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecacheBanner) return;

    _didPrecacheBanner = true;
    precacheImage(
      const AssetImage(HomeText.bannerAsset),
      context,
      onError: (_, __) {},
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.extentAfter > HomeConfig.loadMoreExtent) return;

    _loadMoreProducts(showErrors: false);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final profile = ref.watch(currentUserProfileProvider).maybeWhen(
          data: (user) => user,
          orElse: () => null,
        );
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final productListAsync = ref.watch(catalogProductListProvider);
    final productsAsync = productListAsync.whenData((state) => state.products);
    final productListState = productListAsync.maybeWhen(
      data: (state) => state,
      orElse: () => null,
    );
    final cartItems = ref.watch(cartItemsProvider);
    final cartCount = ref.watch(cartItemCountProvider);
    final cartQtyById = {
      for (final item in cartItems) item.productId: item.quantity,
    };
    final wishlistedProductIds = ref.watch(
      wishlistProductIdSetProvider(session.uid),
    );
    final wishlistPendingProductIds = ref.watch(
      wishlistPendingProductIdsProvider(session.uid),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const _HomeDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _HomeTopBar(
              cartCount: cartCount,
              onCartTap: _openCart,
              onNotificationTap: _showNoNotifications,
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DeliveryLocation(
                      address: profile?.address ?? '',
                      onTap: _openAddress,
                    ),
                    _SearchSection(
                      onTap: _openSearchResults,
                    ),
                    _PromoBanner(onShopNow: _scrollToProducts),
                    const _HomeOfferStrip(),
                    _CategorySection(
                      categoriesAsync: categoriesAsync,
                      onCategorySelected: _openCategoryProducts,
                      onRetry: () => ref.invalidate(categoriesStreamProvider),
                    ),
                    _ProductsAsyncSection(
                      title: HomeText.topOffersTitle,
                      emptyMessage: HomeText.noOffers,
                      productsAsync: productsAsync,
                      cartQtyById: cartQtyById,
                      wishlistedProductIds: wishlistedProductIds,
                      wishlistPendingProductIds: wishlistPendingProductIds,
                      onlyDiscounted: true,
                      maxProducts: HomeConfig.topOfferLimit,
                      onRetry: () {
                        ref
                            .read(catalogProductListProvider.notifier)
                            .loadInitial();
                      },
                      onOpen: _openProductDetail,
                      onAdd: _addProduct,
                      onIncrement: _incrementProduct,
                      onDecrement: _decrementProduct,
                      onToggleWishlist: (product) {
                        _toggleWishlist(
                          userId: session.uid,
                          product: product,
                          isWishlisted:
                              wishlistedProductIds.contains(product.id),
                        );
                      },
                    ),
                    _ProductsAsyncSection(
                      title: HomeText.productsTitle,
                      emptyMessage: HomeText.noProducts,
                      productsAsync: productsAsync,
                      cartQtyById: cartQtyById,
                      wishlistedProductIds: wishlistedProductIds,
                      wishlistPendingProductIds: wishlistPendingProductIds,
                      onRetry: () {
                        ref
                            .read(catalogProductListProvider.notifier)
                            .loadInitial();
                      },
                      isLoadingMore: productListState?.isLoadingMore ?? false,
                      hasMore: productListState?.hasMore ?? false,
                      onLoadMore: () => _loadMoreProducts(showErrors: true),
                      onOpen: _openProductDetail,
                      onAdd: _addProduct,
                      onIncrement: _incrementProduct,
                      onDecrement: _decrementProduct,
                      onToggleWishlist: (product) {
                        _toggleWishlist(
                          userId: session.uid,
                          product: product,
                          isWishlisted:
                              wishlistedProductIds.contains(product.id),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCart() {
    CustomerNavigationScope.openCart(context);
  }

  void _openAddress() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddressScreen()),
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

  void _openSearchResults() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SearchResultsScreen(),
      ),
    );
  }

  void _openCategoryProducts(Category category) {
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
        fallbackMessage: HomeText.wishlistUpdateError,
      );
    }
  }

  Future<void> _loadMoreProducts({required bool showErrors}) async {
    try {
      await ref.read(catalogProductListProvider.notifier).loadNext();
    } catch (error) {
      if (!mounted || !showErrors) return;

      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: HomeText.productsError,
      );
    }
  }

  void _scrollToProducts() {
    _scrollController.animateTo(
      HomeConfig.productsScrollOffset,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _showNoNotifications() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(HomeText.noNotifications)),
    );
  }
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({
    required this.cartCount,
    required this.onCartTap,
    required this.onNotificationTap,
  });

  final int cartCount;
  final VoidCallback onCartTap;
  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Row(
        children: [
          Builder(
            builder: (context) {
              return _IconButtonSurface(
                tooltip: HomeText.menu,
                icon: Icons.menu_rounded,
                onTap: () => Scaffold.of(context).openDrawer(),
              );
            },
          ),
          const Expanded(child: Center(child: _BrandLockup())),
          _BadgeIconButton(
            tooltip: HomeText.notifications,
            icon: Icons.notifications_none_rounded,
            count: 0,
            onTap: onNotificationTap,
          ),
          const SizedBox(width: 8),
          _BadgeIconButton(
            tooltip: HomeText.cart,
            icon: Icons.shopping_cart_outlined,
            count: cartCount,
            onTap: onCartTap,
          ),
        ],
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            HomeText.logoAsset,
            width: compact ? 34 : 40,
            height: compact ? 34 : 40,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) {
              return const _GkLogoFallback();
            },
          ),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'GK ',
                    style: TextStyle(color: AppColors.primary),
                  ),
                  TextSpan(
                    text: 'MART',
                    style: TextStyle(color: AppColors.accent),
                  ),
                ],
              ),
              maxLines: 1,
              style: TextStyle(
                fontSize: 18,
                height: 1,
                letterSpacing: 0,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 3),
              const Text(
                HomeText.supermarket,
                maxLines: 1,
                style: TextStyle(
                  color: AppColors.mutedText,
                  fontSize: 9,
                  height: 1,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _IconButtonSurface extends StatelessWidget {
  const _IconButtonSurface({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
        ),
      ),
    );
  }
}

class _GkLogoFallback extends StatelessWidget {
  const _GkLogoFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Text(
          'GK',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1,
            letterSpacing: 0,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _BadgeIconButton extends StatelessWidget {
  const _BadgeIconButton({
    required this.tooltip,
    required this.icon,
    required this.count,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _IconButtonSurface(tooltip: tooltip, icon: icon, onTap: onTap),
        if (count > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.card, width: 2),
              ),
              child: Text(
                count > 99 ? '99+' : count.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DeliveryLocation extends StatelessWidget {
  const _DeliveryLocation({
    required this.address,
    required this.onTap,
  });

  final String address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visibleAddress = address.trim();

    return Material(
      color: AppColors.card,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppColors.softGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Flexible(
                          child: Text(
                            HomeText.deliverToHome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.mutedText,
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      visibleAddress.isEmpty
                          ? HomeText.addDeliveryAddress
                          : visibleAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: visibleAddress.isEmpty
                            ? AppColors.accent
                            : AppColors.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.mutedText),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchSection extends StatelessWidget {
  const _SearchSection({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            onTap: onTap,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: AppColors.border),
                boxShadow: AppShadows.soft,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: const Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      HomeText.searchHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.mutedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.mutedText,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.onShopNow});

  final VoidCallback onShopNow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 360;

          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              boxShadow: AppShadows.card,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: isCompact ? 1.45 : 1.75,
                    child: Image.asset(
                      HomeText.bannerAsset,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      cacheWidth: HomeConfig.bannerImageCacheWidth,
                      errorBuilder: (_, __, ___) {
                        return const _BannerImagePlaceholder();
                      },
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.98),
                            Colors.white.withValues(alpha: 0.82),
                            Colors.white.withValues(alpha: 0.16),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.all(isCompact ? 12 : 18),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isCompact ? 200 : 235,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                HomeText.bannerTitle,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: isCompact ? 16 : 21,
                                  height: 1.1,
                                  letterSpacing: 0,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: isCompact ? 4 : 8),
                              Text(
                                HomeText.bannerSubtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.mutedText,
                                  fontSize: isCompact ? 11 : 12,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: isCompact ? 8 : 12),
                              SizedBox(
                                height: isCompact ? 32 : 36,
                                child: ElevatedButton.icon(
                                  onPressed: onShopNow,
                                  style: ElevatedButton.styleFrom(
                                    padding: isCompact
                                        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 0)
                                        : null,
                                    textStyle: TextStyle(
                                      fontSize: isCompact ? 11 : 12,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  icon: Icon(
                                    Icons.shopping_bag_rounded,
                                    size: isCompact ? 15 : 17,
                                  ),
                                  label: const Text(HomeText.shopNow),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.categoriesAsync,
    required this.onCategorySelected,
    required this.onRetry,
  });

  final AsyncValue<List<Category>> categoriesAsync;
  final ValueChanged<Category> onCategorySelected;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: HomeText.categoriesTitle,
      child: SizedBox(
        height: 116,
        child: categoriesAsync.when(
          data: (categories) {
            if (categories.isEmpty) {
              return const _InlineState(
                icon: Icons.category_outlined,
                message: HomeText.noCategories,
              );
            }

            return ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final category = categories[index];

                return _CategoryTile(
                  label: category.name,
                  imageUrl: category.imageUrl,
                  icon: _categoryIconFor(category.name),
                  isSelected: false,
                  onTap: () => onCategorySelected(category),
                );
              },
            );
          },
          loading: () => const _HorizontalLoadingTiles(),
          error: (_, __) => _InlineState(
            icon: Icons.error_outline_rounded,
            message: HomeText.categoriesError,
            onRetry: onRetry,
          ),
        ),
      ),
    );
  }
}

class _HomeOfferStrip extends StatelessWidget {
  const _HomeOfferStrip();

  static const _offers = [
    _HomeOffer(
      title: '\u20B950 OFF',
      subtitle: 'Above \u20B92000',
      icon: Icons.local_offer_rounded,
      color: AppColors.primary,
    ),
    _HomeOffer(
      title: '\u20B9100 OFF',
      subtitle: 'Above \u20B93000',
      icon: Icons.savings_rounded,
      color: AppColors.accent,
    ),
    _HomeOffer(
      title: '\u20B9150 OFF',
      subtitle: 'Above \u20B94000',
      icon: Icons.workspace_premium_rounded,
      color: AppColors.info,
    ),
    _HomeOffer(
      title: 'Free Delivery',
      subtitle: 'Above \u20B9699',
      icon: Icons.local_shipping_rounded,
      color: AppColors.success,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
        itemCount: _offers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return _OfferCard(offer: _offers[index]);
        },
      ),
    );
  }
}

class _HomeOffer {
  const _HomeOffer({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer});

  final _HomeOffer offer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 178,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: offer.color.withValues(alpha: 0.18)),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: offer.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(offer.icon, color: offer.color, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  offer.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.imageUrl,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String imageUrl;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 72,
              height: 72,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.card,
                shape: BoxShape.circle,
                boxShadow: AppShadows.soft,
              ),
              child: ClipOval(
                child: imageUrl.trim().isEmpty
                    ? _CategoryIcon(icon: icon, isSelected: isSelected)
                    : AppCachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                        memCacheWidth: HomeConfig.categoryImageCacheExtent,
                        memCacheHeight: HomeConfig.categoryImageCacheExtent,
                        maxWidthDiskCache:
                            HomeConfig.categoryImageDiskCacheExtent,
                        maxHeightDiskCache:
                            HomeConfig.categoryImageDiskCacheExtent,
                        placeholder:
                            _CategoryIcon(icon: icon, isSelected: isSelected),
                        errorPlaceholder:
                            _CategoryIcon(icon: icon, isSelected: isSelected),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.text,
                fontSize: 12,
                height: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({
    required this.icon,
    required this.isSelected,
  });

  final IconData icon;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isSelected ? AppColors.card : AppColors.softGreen,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: AppColors.primary, size: 30),
    );
  }
}

class _BannerImagePlaceholder extends StatelessWidget {
  const _BannerImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const AppImagePlaceholder(
      icon: Icons.local_grocery_store_rounded,
      iconSize: 40,
    );
  }
}

class _ProductsAsyncSection extends StatelessWidget {
  const _ProductsAsyncSection({
    required this.title,
    required this.emptyMessage,
    required this.productsAsync,
    required this.cartQtyById,
    required this.wishlistedProductIds,
    required this.wishlistPendingProductIds,
    required this.onRetry,
    required this.onOpen,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    required this.onToggleWishlist,
    this.onlyDiscounted = false,
    this.maxProducts,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.onLoadMore,
  });

  final String title;
  final String emptyMessage;
  final AsyncValue<List<Product>> productsAsync;
  final Map<String, int> cartQtyById;
  final Set<String> wishlistedProductIds;
  final Set<String> wishlistPendingProductIds;
  final VoidCallback onRetry;
  final ValueChanged<Product> onOpen;
  final ValueChanged<Product> onAdd;
  final ValueChanged<Product> onIncrement;
  final ValueChanged<Product> onDecrement;
  final ValueChanged<Product> onToggleWishlist;
  final bool onlyDiscounted;
  final int? maxProducts;
  final bool isLoadingMore;
  final bool hasMore;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: title,
      child: productsAsync.when(
        data: (products) {
          final visibleProducts = products.where((product) {
            if (onlyDiscounted) return _discountPercent(product) > 0;
            return true;
          }).toList();

          if (onlyDiscounted) {
            visibleProducts.sort((a, b) {
              return _discountPercent(b).compareTo(_discountPercent(a));
            });
          }

          final limitedProducts = maxProducts == null
              ? visibleProducts
              : visibleProducts.take(maxProducts!).toList();

          if (limitedProducts.isEmpty) {
            return _InlineState(
              icon: onlyDiscounted
                  ? Icons.local_offer_outlined
                  : Icons.shopping_basket_outlined,
              message: emptyMessage,
            );
          }

          return Column(
            children: [
              _ProductGrid(
                products: limitedProducts,
                cartQtyById: cartQtyById,
                wishlistedProductIds: wishlistedProductIds,
                wishlistPendingProductIds: wishlistPendingProductIds,
                onOpen: onOpen,
                onAdd: onAdd,
                onIncrement: onIncrement,
                onDecrement: onDecrement,
                onToggleWishlist: onToggleWishlist,
              ),
              if (onLoadMore != null && !onlyDiscounted)
                _ProductLoadMoreFooter(
                  isLoading: isLoadingMore,
                  hasMore: hasMore,
                  onLoadMore: onLoadMore!,
                ),
            ],
          );
        },
        loading: () => const _ProductGridSkeleton(),
        error: (_, __) => _InlineState(
          icon: Icons.error_outline_rounded,
          message: HomeText.productsError,
          onRetry: onRetry,
        ),
      ),
    );
  }
}

class _ProductLoadMoreFooter extends StatelessWidget {
  const _ProductLoadMoreFooter({
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
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Text(
          HomeText.endOfProducts,
          style: TextStyle(
            color: AppColors.mutedText,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: OutlinedButton.icon(
        onPressed: onLoadMore,
        icon: const Icon(Icons.expand_more_rounded),
        label: const Text(HomeText.loadMore),
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({
    required this.products,
    required this.cartQtyById,
    required this.wishlistedProductIds,
    required this.wishlistPendingProductIds,
    required this.onOpen,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    required this.onToggleWishlist,
  });

  final List<Product> products;
  final Map<String, int> cartQtyById;
  final Set<String> wishlistedProductIds;
  final Set<String> wishlistPendingProductIds;
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
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
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

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 19,
                height: 1.15,
                letterSpacing: 0,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _InlineState extends StatelessWidget {
  const _InlineState({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: onRetry,
              child: const Text(HomeText.retry),
            ),
          ],
        ],
      ),
    );
  }
}

class _HorizontalLoadingTiles extends StatelessWidget {
  const _HorizontalLoadingTiles();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        return Container(
          width: 84,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
        );
      },
    );
  }
}

class _ProductGridSkeleton extends StatelessWidget {
  const _ProductGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
          ),
        );
      },
    );
  }
}

class _HomeDrawer extends StatelessWidget {
  const _HomeDrawer();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.card,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: _BrandLockup(compact: true),
            ),
            const Divider(height: 1, color: AppColors.border),
            ListTile(
              leading: const Icon(Icons.home_rounded),
              title: const Text(HomeText.home),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_rounded),
              title: const Text(HomeText.orders),
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute(builder: (_) => const OrdersScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.support_agent_rounded),
              title: const Text(HomeText.customerSupport),
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                showCustomerSupportSheet(navigator.context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

IconData _categoryIconFor(String name) {
  final normalized = name.toLowerCase();

  if (normalized.contains('rice') ||
      normalized.contains('atta') ||
      normalized.contains('grain')) {
    return Icons.rice_bowl_rounded;
  }
  if (normalized.contains('dal') || normalized.contains('pulse')) {
    return Icons.grain_rounded;
  }
  if (normalized.contains('milk') || normalized.contains('dairy')) {
    return Icons.local_drink_rounded;
  }
  if (normalized.contains('oil') || normalized.contains('ghee')) {
    return Icons.water_drop_rounded;
  }
  if (normalized.contains('snack') || normalized.contains('biscuit')) {
    return Icons.cookie_rounded;
  }
  if (normalized.contains('chocolate') || normalized.contains('sweet')) {
    return Icons.cake_rounded;
  }
  if (normalized.contains('beverage') || normalized.contains('drink')) {
    return Icons.local_cafe_rounded;
  }
  if (normalized.contains('care') || normalized.contains('personal')) {
    return Icons.spa_rounded;
  }
  if (normalized.contains('home') || normalized.contains('household')) {
    return Icons.cleaning_services_rounded;
  }
  if (normalized.contains('spice') || normalized.contains('masala')) {
    return Icons.restaurant_rounded;
  }

  return Icons.local_grocery_store_rounded;
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

class HomeConfig {
  const HomeConfig._();

  static const topOfferLimit = 4;
  static const productsScrollOffset = 560.0;
  static const loadMoreExtent = 520.0;
  static const bannerImageCacheWidth = 1200;
  static const categoryImageCacheExtent = 160;
  static const categoryImageDiskCacheExtent = 220;
}

class HomeText {
  const HomeText._();

  static const logoAsset = 'assets/gk_mart_logo.png';
  static const supermarket = 'SUPERMARKET';
  static const menu = 'Menu';
  static const notifications = 'Notifications';
  static const noNotifications = 'No new notifications';
  static const cart = 'Cart';
  static const deliverToHome = 'Deliver to Home';
  static const addDeliveryAddress = 'Add delivery address';
  static const search = 'Search';
  static const searchHint = 'Search for products...';
  static const clearSearch = 'Clear search';
  static const bannerTitle = 'Best Quality. Best Prices. Everyday!';
  static const bannerSubtitle = 'Groceries, dairy, pooja and home essentials.';
  static const bannerAsset = 'assets/home_supermarket_banner.png';
  static const shopNow = 'Shop Now';
  static const categoriesTitle = 'Shop by Category';
  static const noCategories = 'No categories available yet';
  static const categoriesError = 'Unable to load categories';
  static const topOffersTitle = 'Top Offers';
  static const productsTitle = 'Products';
  static const noOffers = 'No active product offers right now';
  static const noProducts = 'No products found';
  static const productsError = 'Unable to load products';
  static const loadMore = 'Load more';
  static const endOfProducts = 'All loaded products are visible';
  static const retry = 'Retry';
  static const wishlistUpdateError = 'Unable to update wishlist';
  static const home = 'Home';
  static const orders = 'Orders';
  static const customerSupport = 'Customer Support';
}
