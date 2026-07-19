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
import '../providers/notification_provider.dart';
import '../widgets/app_cached_network_image.dart';
import '../widgets/customer_support_sheet.dart';
import '../widgets/product_card.dart';
import 'address_screen.dart';
import 'category_products_screen.dart';
import 'orders_screen.dart';
import 'notifications_screen.dart';
import 'product_detail_screen.dart';
import 'search_results_screen.dart';
import '../providers/store_providers.dart';

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
    final activeAddress = ref.watch(activeAddressProvider);
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
              address: activeAddress.isNotEmpty ? activeAddress : (profile?.address ?? ''),
              onAddressTap: _openAddress,
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SearchSection(
                      onTap: _openSearchResults,
                    ),
                    const _StoreStatusBanner(),
                    _PromoBanner(onShopNow: _scrollToProducts),
                    const _CouponSection(),
                    _TopOffersHorizontalSection(
                      productsAsync: productsAsync,
                      cartQtyById: cartQtyById,
                      wishlistedProductIds: wishlistedProductIds,
                      wishlistPendingProductIds: wishlistPendingProductIds,
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
                    _CategorySection(
                      categoriesAsync: categoriesAsync,
                      onCategorySelected: _openCategoryProducts,
                      onRetry: () => ref.invalidate(categoriesStreamProvider),
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
    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    final profile = ref.read(currentUserProfileProvider).value;
    if (profile == null) return;

    final addresses = profile.savedAddresses;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final activeAddress = ref.watch(activeAddressProvider);
            final currentActive = activeAddress.isNotEmpty ? activeAddress : profile.address.trim();

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Delivery Address',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (addresses.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            'No saved addresses yet.',
                            style: TextStyle(
                              color: AppColors.mutedText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: addresses.length,
                          itemBuilder: (context, index) {
                            final addr = addresses[index];
                            final isSelected = addr.trim() == currentActive.trim();
                            final parsed = ParsedAddress.from(addr);

                            return InkWell(
                              onTap: () {
                                ref.read(activeAddressProvider.notifier).selectAddress(addr);
                                Navigator.pop(context);
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.softGreen : AppColors.background,
                                  borderRadius: BorderRadius.circular(AppRadii.md),
                                  border: Border.all(
                                    color: isSelected ? AppColors.primary : AppColors.border,
                                    width: isSelected ? 2.0 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.radio_button_off_rounded,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.mutedText,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            parsed.address,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.text,
                                            ),
                                          ),
                                          if (parsed.landmark.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Landmark: ${parsed.landmark}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.mutedText,
                                              ),
                                            ),
                                          ],
                                          if (parsed.pincode.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Pincode: ${parsed.pincode}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.mutedText,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.md),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AddressScreen()),
                          );
                        },
                        icon: const Icon(Icons.add_location_alt_rounded, color: Colors.white),
                        label: const Text(
                          'Add / Manage Addresses',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
}
class _HomeTopBar extends ConsumerWidget {
  const _HomeTopBar({
    required this.cartCount,
    required this.onCartTap,
    required this.address,
    required this.onAddressTap,
  });

  final int cartCount;
  final VoidCallback onCartTap;
  final String address;
  final VoidCallback onAddressTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleAddress = address.trim();
    final addressName = visibleAddress.isEmpty
        ? 'Add Address'
        : ParsedAddress.from(visibleAddress).address.split('\n').first;
    final unreadNotificationCount = ref.watch(unreadNotificationCountProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
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
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: onAddressTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Deliver To',
                            style: TextStyle(
                              color: AppColors.mutedText,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  addressName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: AppColors.text,
                                size: 14,
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
          ),
          const SizedBox(width: 8),
          _BadgeIconButton(
            tooltip: 'Notifications',
            icon: Icons.notifications_none_rounded,
            count: unreadNotificationCount,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
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
        color: const Color(0xFFF3F4F6),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, color: AppColors.text, size: 20),
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
              constraints: const BoxConstraints(minWidth: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.card, width: 1.5),
              ),
              child: Text(
                count > 99 ? '99+' : count.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
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

class _SearchSection extends StatelessWidget {
  const _SearchSection({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: AppColors.mutedText,
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    HomeText.searchHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.mutedText,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
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

class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.onShopNow});

  final VoidCallback onShopNow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 6,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bw = constraints.maxWidth;
              final bh = constraints.maxHeight;
              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0C8346), Color(0xFF10B981)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // ── Decorative background circles ──────────────────────
                    Positioned(
                      right: -40,
                      top: -40,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      left: -20,
                      bottom: -20,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),

                    // ── Grocery products — right side, fills full banner height ──
                    Positioned(
                      right: 0,
                      top: 0,
                      width: bw * 0.56,
                      height: bh,
                      child: Image.asset(
                        HomeText.bannerAsset,
                        fit: BoxFit.cover,
                        alignment: Alignment.centerLeft,
                      ),
                    ),

                    // ── Gradient: dark-green → transparent (left → right) ──
                    // Keeps text crisp; products visible on the right
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF0C8346),       // solid green
                              Color(0xFF0C8346),       // hold solid to 40%
                              Color(0x880D9955),       // semi-transparent
                              Color(0x000D9955),       // fully transparent
                            ],
                            stops: [0.0, 0.38, 0.55, 0.70],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),

                    // ── Text content — left side ──────────────────────────
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: bw * 0.52,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'FAST DELIVERY',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Everyday Essentials',
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Best Prices Guaranteed',
                                maxLines: 1,
                                style: TextStyle(
                                  color: AppColors.softGreen,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: onShopNow,
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Shop Now',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        color: AppColors.primary,
                                        size: 9,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
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
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final sectionHeight = (114.0 + (textScale - 1.0) * 24).clamp(114.0, 150.0);

    return _Section(
      title: HomeText.categoriesTitle,
      child: SizedBox(
        height: sectionHeight,
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
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
  final bool isLoadingMore;
  final bool hasMore;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: title,
      child: productsAsync.when(
        data: (products) {
          if (products.isEmpty) {
            return _InlineState(
              icon: Icons.shopping_basket_outlined,
              message: emptyMessage,
            );
          }

          return Column(
            children: [
              _ProductGrid(
                products: products,
                cartQtyById: cartQtyById,
                wishlistedProductIds: wishlistedProductIds,
                wishlistPendingProductIds: wishlistPendingProductIds,
                onOpen: onOpen,
                onAdd: onAdd,
                onIncrement: onIncrement,
                onDecrement: onDecrement,
                onToggleWishlist: onToggleWishlist,
              ),
              if (onLoadMore != null)
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

class _TopOffersHorizontalSection extends StatelessWidget {
  const _TopOffersHorizontalSection({
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
    this.maxProducts,
  });

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
  final int? maxProducts;

  @override
  Widget build(BuildContext context) {
    return productsAsync.when(
      data: (products) {
        final visibleProducts = products.where((product) {
          return _discountPercent(product) > 0;
        }).toList();

        visibleProducts.sort((a, b) {
          return _discountPercent(b).compareTo(_discountPercent(a));
        });

        final limitedProducts = maxProducts == null
            ? visibleProducts
            : visibleProducts.take(maxProducts!).toList();

        if (limitedProducts.isEmpty) {
          return Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.softGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: const _InlineState(
              icon: Icons.local_offer_outlined,
              message: HomeText.noOffers,
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 2, 12, 12),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.softGreen.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_offer_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      HomeText.topOffersTitle,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 225,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: limitedProducts.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final product = limitedProducts[index];

                    return SizedBox(
                      width: 142,
                      child: GkProductCard(
                        product: product,
                        quantity: cartQtyById[product.id] ?? 0,
                        onTap: () => onOpen(product),
                        onAdd: () => onAdd(product),
                        onIncrement: () => onIncrement(product),
                        onDecrement: () => onDecrement(product),
                        isWishlisted: wishlistedProductIds.contains(product.id),
                        isWishlistUpdating: wishlistPendingProductIds.contains(product.id),
                        onToggleWishlist: () => onToggleWishlist(product),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        margin: const EdgeInsets.fromLTRB(12, 2, 12, 12),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.softGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_offer_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    HomeText.topOffersTitle,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 225,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: 4,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return Container(
                    width: 142,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      error: (_, __) => Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.softGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: _InlineState(
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
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final aspectRatio = constraints.maxWidth >= 720
            ? 0.92
            : (0.72 - (textScale - 1.0) * 0.18).clamp(0.55, 0.78);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 18,
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
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
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
              borderRadius: BorderRadius.circular(8),
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        return Container(
          width: 72,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.74,
      ),
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
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

  static const topOfferLimit = 10;
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

class _StoreStatusBanner extends ConsumerWidget {
  const _StoreStatusBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(storeConfigProvider);

    return configAsync.when(
      data: (config) {
        final isOpen = config.isOpen;
        final bgColor = isOpen ? AppColors.softGreen : const Color(0xFFFEE2E2); // soft red
        final textColor = isOpen ? AppColors.success : AppColors.danger;
        final titleText = isOpen ? 'Store Open' : 'Store Closed';
        final detailsText = isOpen
            ? 'Open until ${config.formattedCloseTime}'
            : 'Reopens at ${config.formattedOpenTime}';
        final iconData = isOpen ? Icons.storefront_rounded : Icons.storefront_outlined;

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: textColor.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  iconData,
                  color: textColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleText,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detailsText,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _CouponSection extends StatelessWidget {
  const _CouponSection();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Row(
        children: [
          SizedBox(
            width: 175,
            child: _StaticCouponCard(
              icon: Icons.local_offer_rounded,
              iconColor: Color(0xFF10B981), // Green
              title: '₹50 OFF',
              subtitle: 'Above ₹2000',
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 175,
            child: _StaticCouponCard(
              icon: Icons.savings_rounded,
              iconColor: Color(0xFFF59E0B), // Orange
              title: '₹100 OFF',
              subtitle: 'Above ₹3000',
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 175,
            child: _StaticCouponCard(
              icon: Icons.confirmation_number_rounded,
              iconColor: Color(0xFF8B5CF6), // Purple
              title: '₹150 OFF',
              subtitle: 'Above ₹4000',
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 175,
            child: _StaticCouponCard(
              icon: Icons.local_shipping_rounded,
              iconColor: Color(0xFF3B82F6), // Blue
              title: 'FREE DELIVERY',
              subtitle: 'Above ₹699',
            ),
          ),
        ],
      ),
    );
  }
}

class _StaticCouponCard extends StatelessWidget {
  const _StaticCouponCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 1.5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
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
