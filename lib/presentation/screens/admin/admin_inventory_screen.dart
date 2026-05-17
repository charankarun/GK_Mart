import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/app_error_handler.dart';
import '../../../core/images/image_upload_processor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/product.dart';
import '../../providers/auth_providers.dart';
import '../../providers/catalog_providers.dart';
import '../../providers/product_provider.dart';
import '../../widgets/app_cached_network_image.dart';
import '../../widgets/app_state_widgets.dart';

class AdminInventoryScreen extends ConsumerStatefulWidget {
  const AdminInventoryScreen({super.key});

  @override
  ConsumerState<AdminInventoryScreen> createState() {
    return _AdminInventoryScreenState();
  }
}

class _AdminInventoryScreenState extends ConsumerState<AdminInventoryScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String? _selectedCategoryFilterId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _searchController.removeListener(_handleSearchChanged);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) setState(() {});
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.extentAfter > ProductManagementConfig.loadMoreExtent) return;

    _loadNextPage(showErrors: false);
  }

  @override
  Widget build(BuildContext context) {
    final isAdminAsync = ref.watch(isCurrentUserAdminProvider);
    final isAdmin = isAdminAsync.maybeWhen(
      data: (value) => value,
      orElse: () => false,
    );

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text(ProductManagementText.title)),
        body: Center(
          child: isAdminAsync.isLoading
              ? const CircularProgressIndicator()
              : const Text(ProductManagementText.adminAccessRequired),
        ),
      );
    }

    final productsAsync = ref.watch(adminProductListProvider);
    final isProductActionBusy = productsAsync.isLoading;
    final categories = ref.watch(categoriesStreamProvider).maybeWhen(
          data: (categories) => categories,
          orElse: () => const <Category>[],
        );
    final categoriesById = {
      for (final category in categories) category.id: category,
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(ProductManagementText.title),
        actions: [
          IconButton(
            tooltip: ProductManagementText.refresh,
            onPressed: () {
              ref.read(adminProductListProvider.notifier).loadInitial();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isProductActionBusy ? null : () => _openProductForm(),
        icon: isProductActionBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text(ProductManagementText.addProduct),
      ),
      body: productsAsync.when(
        data: (state) => _buildProductList(
          state,
          categories,
          categoriesById,
        ),
        loading: () => const AppLoadingState(),
        error: (_, __) => _InventoryError(
          onRetry: () {
            ref.read(adminProductListProvider.notifier).loadInitial();
          },
        ),
      ),
    );
  }

  Widget _buildProductList(
    AdminProductListState state,
    List<Category> categories,
    Map<String, Category> categoriesById,
  ) {
    final products = _visibleProducts(state.products);

    return RefreshIndicator(
      onRefresh: () {
        return ref.read(adminProductListProvider.notifier).loadInitial();
      },
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
        itemCount: products.length + ProductManagementConfig.listExtraItems,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              children: [
                _InventorySummary(products: state.products),
                const SizedBox(height: 12),
                _InventoryFilters(
                  searchController: _searchController,
                  categories: categories,
                  selectedCategoryId: _selectedCategoryFilterId,
                  onCategoryChanged: (categoryId) {
                    setState(() => _selectedCategoryFilterId = categoryId);
                  },
                  onClear: _clearFilters,
                ),
              ],
            );
          }

          final productIndex = index - 1;
          if (productIndex >= products.length) {
            if (products.isEmpty && state.products.isNotEmpty) {
              return _FilteredInventoryEmpty(onClear: _clearFilters);
            }

            return _ProductListFooter(
              state: state,
              onLoadMore: () => _loadNextPage(showErrors: true),
            );
          }

          final product = products[productIndex];
          final isUpdating = state.pendingAvailabilityProductIds.contains(
                product.id,
              ) ||
              state.pendingDeleteProductIds.contains(product.id);
          return _ProductCard(
            product: product,
            categoryName: categoriesById[product.categoryId]?.name,
            isUpdating: isUpdating,
            onEdit: () => _openProductForm(product: product),
            onDelete: () => _confirmDelete(product),
            onAvailabilityChanged: (isAvailable) {
              _updateAvailability(product, isAvailable);
            },
          );
        },
      ),
    );
  }

  Future<void> _openProductForm({Product? product}) async {
    final input = await showDialog<AdminProductInput>(
      context: context,
      builder: (_) => _ProductFormDialog(product: product),
    );

    if (input == null || !mounted) return;

    try {
      await ref.read(adminProductListProvider.notifier).saveProduct(input);
      if (!mounted) return;
      _showMessage(
        product == null
            ? ProductManagementText.addSuccess
            : ProductManagementText.updateSuccess,
      );
    } catch (error) {
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: ProductManagementText.saveError,
      );
    }
  }

  List<Product> _visibleProducts(List<Product> products) {
    final query = _searchController.text.trim().toLowerCase();
    final categoryId = _selectedCategoryFilterId?.trim();

    return products.where((product) {
      if (categoryId != null &&
          categoryId.isNotEmpty &&
          product.categoryId != categoryId) {
        return false;
      }

      if (query.isEmpty) return true;

      return product.name.toLowerCase().contains(query) ||
          product.categoryId.toLowerCase().contains(query) ||
          product.unit.toLowerCase().contains(query);
    }).toList();
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _selectedCategoryFilterId = null;
    });
  }

  Future<void> _updateAvailability(Product product, bool isAvailable) async {
    try {
      await ref.read(adminProductListProvider.notifier).updateAvailability(
            productId: product.id,
            isAvailable: isAvailable,
          );
      if (!mounted) return;
      _showMessage(ProductManagementText.stockUpdateSuccess);
    } catch (error) {
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: ProductManagementText.stockUpdateError,
      );
    }
  }

  Future<void> _confirmDelete(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(ProductManagementText.deleteProduct),
          content: Text(
            '${ProductManagementText.deletePrompt} ${product.name}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(ProductManagementText.cancel),
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade50,
                foregroundColor: Colors.red.shade700,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.delete_outline),
              label: const Text(ProductManagementText.delete),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(adminProductListProvider.notifier).deleteProduct(
            product.id,
          );
      if (!mounted) return;
      _showMessage(ProductManagementText.deleteSuccess);
    } catch (error) {
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: ProductManagementText.deleteError,
      );
    }
  }

  Future<void> _loadNextPage({required bool showErrors}) async {
    try {
      await ref.read(adminProductListProvider.notifier).loadNext();
    } catch (error) {
      if (!mounted || !showErrors) return;
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: ProductManagementText.loadMoreError,
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _InventorySummary extends StatelessWidget {
  const _InventorySummary({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final availableCount = products.where((product) {
      return product.isAvailable;
    }).length;
    final outOfStockCount = products.length - availableCount;
    final lowStockCount =
        products.where((product) => product.isLowStock).length;
    final topOfferCount = products.where(_hasTopOffer).length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            ProductManagementText.dashboardTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ProductManagementText.dashboardSubtitle,
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryMetric(
                label: ProductManagementText.loadedProducts,
                value: products.length.toString(),
                color: AppColors.primary,
              ),
              _SummaryMetric(
                label: ProductManagementText.available,
                value: availableCount.toString(),
                color: AppColors.primary,
              ),
              _SummaryMetric(
                label: ProductManagementText.lowStock,
                value: lowStockCount.toString(),
                color: ProductManagementColors.warning,
              ),
              _SummaryMetric(
                label: ProductManagementText.topOffers,
                value: topOfferCount.toString(),
                color: AppColors.accent,
              ),
              _SummaryMetric(
                label: ProductManagementText.outOfStock,
                value: outOfStockCount.toString(),
                color: AppColors.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ProductManagementConfig.summaryMetricWidth,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryFilters extends StatelessWidget {
  const _InventoryFilters({
    required this.searchController,
    required this.categories,
    required this.selectedCategoryId,
    required this.onCategoryChanged,
    required this.onClear,
  });

  final TextEditingController searchController;
  final List<Category> categories;
  final String? selectedCategoryId;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final effectiveCategoryId = categories.any((category) {
      return category.id == selectedCategoryId;
    })
        ? selectedCategoryId
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useWideLayout = constraints.maxWidth >= 620;
          final search = TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: ProductManagementText.searchProducts,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searchController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: ProductManagementText.clearSearch,
                      onPressed: searchController.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              isDense: true,
            ),
          );
          final categoryFilter = DropdownButtonFormField<String?>(
            initialValue: effectiveCategoryId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: ProductManagementText.filterByCategory,
              prefixIcon: const Icon(Icons.category_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text(ProductManagementText.allCategories),
              ),
              for (final category in categories)
                DropdownMenuItem<String?>(
                  value: category.id,
                  child: Text(category.name),
                ),
            ],
            onChanged: onCategoryChanged,
          );
          final clearButton = OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text(ProductManagementText.clearFilters),
          );

          if (!useWideLayout) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 10),
                categoryFilter,
                const SizedBox(height: 10),
                clearButton,
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 3, child: search),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: categoryFilter),
              const SizedBox(width: 10),
              clearButton,
            ],
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.categoryName,
    required this.isUpdating,
    required this.onEdit,
    required this.onDelete,
    required this.onAvailabilityChanged,
  });

  final Product product;
  final String? categoryName;
  final bool isUpdating;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onAvailabilityChanged;

  @override
  Widget build(BuildContext context) {
    final availabilityStyle = _AvailabilityStyle.resolve(product.isAvailable);
    final stockStyle = _StockStyle.resolve(product);
    final visibleCategory = categoryName?.trim().isNotEmpty == true
        ? categoryName!.trim()
        : product.categoryId.trim();

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProductImage(imageUrl: product.imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.end,
                        children: [
                          if (_hasTopOffer(product))
                            const _ProductMiniChip(
                              label: ProductManagementText.topOffer,
                              color: AppColors.accent,
                              background: AppColors.softOrange,
                            ),
                          _ProductMiniChip(
                            label: availabilityStyle.label,
                            color: availabilityStyle.foreground,
                            background: availabilityStyle.background,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (visibleCategory.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      '${ProductManagementText.categoryPrefix} '
                      '$visibleCategory',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.mutedText),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _PriceRow(product: product),
                  const SizedBox(height: 8),
                  _StockLine(style: stockStyle),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.isAvailable
                              ? ProductManagementText.available
                              : ProductManagementText.outOfStock,
                          style: const TextStyle(color: AppColors.mutedText),
                        ),
                      ),
                      if (isUpdating)
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else
                        Switch(
                          value: product.isAvailable,
                          onChanged: onAvailabilityChanged,
                        ),
                      IconButton(
                        tooltip: ProductManagementText.editProduct,
                        onPressed: isUpdating ? null : onEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: ProductManagementText.deleteProduct,
                        onPressed: isUpdating ? null : onDelete,
                        color: ProductManagementColors.delete,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: ProductManagementConfig.productImageSize,
      height: ProductManagementConfig.productImageSize,
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: const Icon(Icons.image, color: AppColors.primary),
    );

    return AppCachedNetworkImage(
      imageUrl: imageUrl,
      width: ProductManagementConfig.productImageSize,
      height: ProductManagementConfig.productImageSize,
      borderRadius: BorderRadius.circular(AppRadii.md),
      memCacheWidth: ProductManagementConfig.productImageCacheExtent,
      memCacheHeight: ProductManagementConfig.productImageCacheExtent,
      maxWidthDiskCache: ProductManagementConfig.productImageDiskCacheExtent,
      maxHeightDiskCache: ProductManagementConfig.productImageDiskCacheExtent,
      placeholder: placeholder,
      errorPlaceholder: placeholder,
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final hasDiscount =
        product.discountPrice > 0 && product.discountPrice < product.price;

    return Row(
      children: [
        Flexible(
          child: Text(
            '\u20B9${_formatPrice(product.sellingPrice)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (hasDiscount) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '\u20B9${_formatPrice(product.price)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey.shade600,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ProductMiniChip extends StatelessWidget {
  const _ProductMiniChip({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _StockLine extends StatelessWidget {
  const _StockLine({required this.style});

  final _StockStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(style.icon, color: style.color, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            style.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: style.color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductListFooter extends StatelessWidget {
  const _ProductListFooter({
    required this.state,
    required this.onLoadMore,
  });

  final AdminProductListState state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (state.products.isEmpty) {
      return const _EmptyInventory();
    }

    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!state.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            ProductManagementText.endOfList,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return Center(
      child: OutlinedButton.icon(
        onPressed: onLoadMore,
        icon: const Icon(Icons.expand_more),
        label: const Text(ProductManagementText.loadMore),
      ),
    );
  }
}

class _EmptyInventory extends StatelessWidget {
  const _EmptyInventory();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.softGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: AppColors.primary,
              size: 34,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            ProductManagementText.emptyState,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ProductManagementText.emptySubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

class _FilteredInventoryEmpty extends StatelessWidget {
  const _FilteredInventoryEmpty({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.softGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            ProductManagementText.noFilteredProducts,
            style: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text(ProductManagementText.clearFilters),
          ),
        ],
      ),
    );
  }
}

class _InventoryError extends StatelessWidget {
  const _InventoryError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(ProductManagementText.loadError),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text(ProductManagementText.retry),
          ),
        ],
      ),
    );
  }
}

class _ProductFormDialog extends ConsumerStatefulWidget {
  const _ProductFormDialog({this.product});

  final Product? product;

  @override
  ConsumerState<_ProductFormDialog> createState() {
    return _ProductFormDialogState();
  }
}

class _ProductFormDialogState extends ConsumerState<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _unitController;
  late final TextEditingController _priceController;
  late final TextEditingController _discountPriceController;
  late final TextEditingController _stockQuantityController;
  late final TextEditingController _lowStockThresholdController;
  late bool _isAvailable;
  late bool _isTopOfferEnabled;
  late bool _trackStock;
  String? _selectedCategoryId;
  Uint8List? _imageBytes;
  String? _imageFileName;
  String _imageContentType = ProductProviderConfig.defaultImageContentType;
  String? _imageError;
  bool _isPickingImage = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;

    _nameController = TextEditingController(text: product?.name ?? '');
    _unitController = TextEditingController(text: product?.unit ?? '');
    _priceController = TextEditingController(
      text: product == null ? '' : _formatInputPrice(product.price),
    );
    _discountPriceController = TextEditingController(
      text: product == null ? '' : _formatInputPrice(product.discountPrice),
    );
    _stockQuantityController = TextEditingController(
      text: product?.stockQuantity?.toString() ?? '',
    );
    _lowStockThresholdController = TextEditingController(
      text: (product?.lowStockThreshold ??
              ProductManagementConfig.lowStockThreshold)
          .toString(),
    );
    _selectedCategoryId = product?.categoryId;
    _isAvailable = product?.isAvailable ?? true;
    _isTopOfferEnabled = product == null ? false : _hasTopOffer(product);
    _trackStock = product?.stockQuantity != null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    _priceController.dispose();
    _discountPriceController.dispose();
    _stockQuantityController.dispose();
    _lowStockThresholdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.product != null;
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    return AlertDialog(
      title: Text(
        isEditing
            ? ProductManagementText.editProduct
            : ProductManagementText.addProduct,
      ),
      content: SizedBox(
        width: ProductManagementConfig.formWidth,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TextFormInput(
                  controller: _nameController,
                  label: ProductManagementText.nameLabel,
                  validator: _requiredText,
                ),
                const SizedBox(height: 12),
                _TextFormInput(
                  controller: _unitController,
                  label: ProductManagementText.unitLabel,
                  helperText: ProductManagementText.unitHelp,
                ),
                const SizedBox(height: 12),
                _buildCategoryDropdown(categoriesAsync),
                const SizedBox(height: 12),
                _TextFormInput(
                  controller: _priceController,
                  label: ProductManagementText.priceLabel,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _requiredPositivePrice,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(ProductManagementText.topOffer),
                  subtitle: const Text(ProductManagementText.topOfferHelp),
                  value: _isTopOfferEnabled,
                  onChanged: (value) {
                    setState(() {
                      _isTopOfferEnabled = value;
                      if (!value) _discountPriceController.clear();
                    });
                  },
                ),
                if (_isTopOfferEnabled) ...[
                  const SizedBox(height: 8),
                  _TextFormInput(
                    controller: _discountPriceController,
                    label: ProductManagementText.discountPriceLabel,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    helperText: ProductManagementText.discountPriceHelp,
                    validator: _discountPriceValidator,
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(ProductManagementText.trackStock),
                  subtitle: const Text(ProductManagementText.trackStockHelp),
                  value: _trackStock,
                  onChanged: (value) {
                    setState(() => _trackStock = value);
                  },
                ),
                if (_trackStock) ...[
                  const SizedBox(height: 8),
                  _StockInputs(
                    stockQuantityController: _stockQuantityController,
                    lowStockThresholdController: _lowStockThresholdController,
                    quantityValidator: _stockQuantityValidator,
                    thresholdValidator: _lowStockThresholdValidator,
                  ),
                ],
                const SizedBox(height: 12),
                _ImagePickerField(
                  imageBytes: _imageBytes,
                  imageUrl: widget.product?.imageUrl ?? '',
                  isPickingImage: _isPickingImage,
                  errorText: _imageError,
                  onPickImage: _pickImage,
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(ProductManagementText.stockStatus),
                  subtitle: Text(
                    _isAvailable
                        ? ProductManagementText.available
                        : ProductManagementText.outOfStock,
                  ),
                  value: _isAvailable,
                  onChanged: (value) {
                    setState(() => _isAvailable = value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(ProductManagementText.cancel),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save_outlined),
          label: const Text(ProductManagementText.save),
        ),
      ],
    );
  }

  Widget _buildCategoryDropdown(AsyncValue<List<Category>> categoriesAsync) {
    return categoriesAsync.when(
      data: (categories) {
        final selectedCategoryId = _selectedCategoryId?.trim();
        final categoryExists = categories.any((category) {
          return category.id == selectedCategoryId;
        });
        final items = <DropdownMenuItem<String>>[
          if (selectedCategoryId != null &&
              selectedCategoryId.isNotEmpty &&
              !categoryExists)
            DropdownMenuItem(
              value: selectedCategoryId,
              child: Text('${ProductManagementText.currentCategoryPrefix} '
                  '$selectedCategoryId'),
            ),
          for (final category in categories)
            DropdownMenuItem(
              value: category.id,
              child: Text(category.name),
            ),
        ];

        return DropdownButtonFormField<String>(
          initialValue: selectedCategoryId == null || selectedCategoryId.isEmpty
              ? null
              : selectedCategoryId,
          items: items,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: ProductManagementText.categoryLabel,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          hint: const Text(ProductManagementText.selectCategory),
          disabledHint: const Text(ProductManagementText.noCategories),
          validator: _requiredText,
          onChanged: items.isEmpty
              ? null
              : (value) {
                  setState(() => _selectedCategoryId = value);
                },
        );
      },
      loading: () => const _ReadonlyFormBox(
        label: ProductManagementText.categoryLabel,
        child: LinearProgressIndicator(),
      ),
      error: (_, __) => const _ReadonlyFormBox(
        label: ProductManagementText.categoryLabel,
        child: Text(ProductManagementText.categoriesError),
      ),
    );
  }

  Future<void> _pickImage() async {
    setState(() {
      _isPickingImage = true;
      _imageError = null;
    });

    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: ProductManagementConfig.pickedImageQuality,
        maxWidth: ProductManagementConfig.pickedImageMaxDimension,
        maxHeight: ProductManagementConfig.pickedImageMaxDimension,
      );
      if (image == null) return;

      final processed = await ImageUploadProcessor.process(
        bytes: await image.readAsBytes(),
        fileName: image.name,
        contentType: image.mimeType ?? _contentTypeFor(image.name),
        maxDimension: ProductManagementConfig.pickedImageMaxDimension,
        maxSourceBytes: ProductManagementConfig.maxSourceImageBytes,
        maxUploadBytes: ProductManagementConfig.maxUploadImageBytes,
        quality: ProductManagementConfig.pickedImageQuality,
      );

      if (!mounted) return;
      setState(() {
        _imageBytes = processed.bytes;
        _imageFileName = processed.fileName;
        _imageContentType = processed.contentType;
      });
    } on ImageValidationException catch (error) {
      if (!mounted) return;
      setState(() => _imageError = error.message);
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: ProductManagementText.imagePickError,
      );
    } catch (error) {
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: ProductManagementText.imagePickError,
      );
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  void _submit() {
    final isFormValid = _formKey.currentState?.validate() == true;
    final hasImage = _imageBytes != null ||
        (widget.product?.imageUrl.trim().isNotEmpty ?? false);

    setState(() {
      _imageError = hasImage ? null : ProductManagementText.imageRequired;
    });

    if (!isFormValid || !hasImage) return;

    Navigator.pop(
      context,
      AdminProductInput(
        productId: widget.product?.id,
        name: _nameController.text.trim(),
        categoryId: _selectedCategoryId!.trim(),
        price: double.parse(_priceController.text.trim()),
        discountPrice: _isTopOfferEnabled
            ? double.tryParse(_discountPriceController.text.trim()) ?? 0
            : 0,
        existingImageUrl: widget.product?.imageUrl ?? '',
        isAvailable: _isAvailable,
        unit: _unitController.text.trim(),
        trackStock: _trackStock,
        stockQuantity: _trackStock
            ? int.tryParse(_stockQuantityController.text.trim())
            : null,
        lowStockThreshold: _trackStock
            ? int.tryParse(_lowStockThresholdController.text.trim()) ??
                ProductManagementConfig.lowStockThreshold
            : ProductManagementConfig.lowStockThreshold,
        imageBytes: _imageBytes,
        imageFileName: _imageFileName,
        imageContentType: _imageContentType,
      ),
    );
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ProductManagementText.requiredField;
    }
    return null;
  }

  String? _requiredPositivePrice(String? value) {
    final price = double.tryParse(value?.trim() ?? '');
    if (price == null || price <= 0) return ProductManagementText.invalidPrice;
    return null;
  }

  String? _discountPriceValidator(String? value) {
    if (!_isTopOfferEnabled) return null;

    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return ProductManagementText.discountRequired;

    final discountPrice = double.tryParse(trimmed);
    final price = double.tryParse(_priceController.text.trim());

    if (discountPrice == null || discountPrice <= 0) {
      return ProductManagementText.invalidDiscountPrice;
    }

    if (price != null && price > 0 && discountPrice >= price) {
      return ProductManagementText.discountExceedsPrice;
    }

    return null;
  }

  String? _stockQuantityValidator(String? value) {
    if (!_trackStock) return null;

    final quantity = int.tryParse(value?.trim() ?? '');
    if (quantity == null || quantity < 0) {
      return ProductManagementText.invalidStockQuantity;
    }

    return null;
  }

  String? _lowStockThresholdValidator(String? value) {
    if (!_trackStock) return null;

    final threshold = int.tryParse(value?.trim() ?? '');
    if (threshold == null || threshold < 0) {
      return ProductManagementText.invalidLowStockThreshold;
    }

    return null;
  }

  String _formatInputPrice(double price) {
    return price == 0
        ? ''
        : price % 1 == 0
            ? price.toStringAsFixed(0)
            : price.toStringAsFixed(2);
  }

  String _contentTypeFor(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png')) return 'image/png';
    if (lowerName.endsWith('.webp')) return 'image/webp';
    return ProductProviderConfig.defaultImageContentType;
  }
}

class _TextFormInput extends StatelessWidget {
  const _TextFormInput({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.helperText,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final String? helperText;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    );
  }
}

class _StockInputs extends StatelessWidget {
  const _StockInputs({
    required this.stockQuantityController,
    required this.lowStockThresholdController,
    required this.quantityValidator,
    required this.thresholdValidator,
  });

  final TextEditingController stockQuantityController;
  final TextEditingController lowStockThresholdController;
  final FormFieldValidator<String> quantityValidator;
  final FormFieldValidator<String> thresholdValidator;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useWideLayout = constraints.maxWidth >= 420;
        final quantityInput = _TextFormInput(
          controller: stockQuantityController,
          label: ProductManagementText.stockQuantityLabel,
          keyboardType: TextInputType.number,
          validator: quantityValidator,
        );
        final thresholdInput = _TextFormInput(
          controller: lowStockThresholdController,
          label: ProductManagementText.lowStockThresholdLabel,
          keyboardType: TextInputType.number,
          validator: thresholdValidator,
        );

        if (!useWideLayout) {
          return Column(
            children: [
              quantityInput,
              const SizedBox(height: 10),
              thresholdInput,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: quantityInput),
            const SizedBox(width: 10),
            Expanded(child: thresholdInput),
          ],
        );
      },
    );
  }
}

class _ReadonlyFormBox extends StatelessWidget {
  const _ReadonlyFormBox({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      child: child,
    );
  }
}

class _ImagePickerField extends StatelessWidget {
  const _ImagePickerField({
    required this.imageBytes,
    required this.imageUrl,
    required this.isPickingImage,
    required this.errorText,
    required this.onPickImage,
  });

  final Uint8List? imageBytes;
  final String imageUrl;
  final bool isPickingImage;
  final String? errorText;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: hasError ? Colors.red.shade700 : Colors.grey.shade300,
            ),
          ),
          child: Row(
            children: [
              _ImagePreview(
                imageBytes: imageBytes,
                imageUrl: imageUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      ProductManagementText.imageLabel,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ProductManagementText.imageHelp,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: isPickingImage ? null : onPickImage,
                      icon: isPickingImage
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_library_outlined),
                      label: Text(
                        imageBytes == null && imageUrl.trim().isEmpty
                            ? ProductManagementText.pickImage
                            : ProductManagementText.changeImage,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: TextStyle(
              color: Colors.red.shade700,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({
    required this.imageBytes,
    required this.imageUrl,
  });

  final Uint8List? imageBytes;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: ProductManagementConfig.formImageSize,
      height: ProductManagementConfig.formImageSize,
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: const Icon(Icons.image, color: AppColors.primary),
    );

    final bytes = imageBytes;
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Image.memory(
          bytes,
          width: ProductManagementConfig.formImageSize,
          height: ProductManagementConfig.formImageSize,
          cacheWidth: ProductManagementConfig.formImageCacheExtent,
          cacheHeight: ProductManagementConfig.formImageCacheExtent,
          fit: BoxFit.cover,
        ),
      );
    }

    return AppCachedNetworkImage(
      imageUrl: imageUrl,
      width: ProductManagementConfig.formImageSize,
      height: ProductManagementConfig.formImageSize,
      borderRadius: BorderRadius.circular(AppRadii.md),
      memCacheWidth: ProductManagementConfig.formImageCacheExtent,
      memCacheHeight: ProductManagementConfig.formImageCacheExtent,
      maxWidthDiskCache: ProductManagementConfig.formImageDiskCacheExtent,
      maxHeightDiskCache: ProductManagementConfig.formImageDiskCacheExtent,
      placeholder: placeholder,
      errorPlaceholder: placeholder,
    );
  }
}

class _AvailabilityStyle {
  const _AvailabilityStyle({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  static _AvailabilityStyle resolve(bool isAvailable) {
    if (isAvailable) {
      return _AvailabilityStyle(
        label: ProductManagementText.available,
        foreground: AppColors.primary,
        background: AppColors.softGreen,
      );
    }

    return _AvailabilityStyle(
      label: ProductManagementText.outOfStock,
      foreground: AppColors.accent,
      background: AppColors.softOrange,
    );
  }
}

class _StockStyle {
  const _StockStyle({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  static _StockStyle resolve(Product product) {
    final quantity = product.stockQuantity;
    if (quantity == null) {
      return const _StockStyle(
        label: ProductManagementText.stockNotTracked,
        color: AppColors.mutedText,
        icon: Icons.inventory_2_outlined,
      );
    }

    if (quantity <= 0) {
      return const _StockStyle(
        label: ProductManagementText.noStock,
        color: AppColors.accent,
        icon: Icons.error_outline_rounded,
      );
    }

    if (product.isLowStock) {
      return _StockStyle(
        label: '${ProductManagementText.lowStock}: $quantity',
        color: ProductManagementColors.warning,
        icon: Icons.warning_amber_rounded,
      );
    }

    return _StockStyle(
      label: '${ProductManagementText.stock}: $quantity',
      color: AppColors.primary,
      icon: Icons.inventory_2_rounded,
    );
  }
}

String _formatPrice(double price) {
  return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
}

bool _hasTopOffer(Product product) {
  return product.discountPrice > 0 && product.discountPrice < product.price;
}

class ProductManagementConfig {
  const ProductManagementConfig._();

  static const listExtraItems = 2;
  static const loadMoreExtent = 420.0;
  static const summaryMetricWidth = 112.0;
  static const productImageSize = 82.0;
  static const formWidth = 460.0;
  static const formImageSize = 86.0;
  static const lowStockThreshold = 5;
  static const productImageCacheExtent = 180;
  static const productImageDiskCacheExtent = 240;
  static const formImageCacheExtent = 180;
  static const formImageDiskCacheExtent = 240;
  static const pickedImageQuality = 86;
  static const pickedImageMaxDimension = 1400.0;
  static const maxSourceImageBytes = 8 * 1024 * 1024;
  static const maxUploadImageBytes = 1536 * 1024;
}

class ProductManagementColors {
  const ProductManagementColors._();

  static const warning = Color(0xFFB45309);
  static const delete = Color(0xFFDC2626);
}

class ProductManagementText {
  const ProductManagementText._();

  static const title = 'Manage Products';
  static const dashboardTitle = 'Product Inventory';
  static const dashboardSubtitle = 'Add, edit, and keep stock status current.';
  static const loadedProducts = 'Loaded';
  static const adminAccessRequired = 'Admin access required';
  static const addProduct = 'Add Product';
  static const editProduct = 'Edit Product';
  static const emptyState = 'No products added';
  static const emptySubtitle = 'Use the add button to create your first item.';
  static const loadError = 'Unable to load products';
  static const loadMoreError = 'Unable to load more products';
  static const saveError = 'Unable to save product';
  static const imagePickError = 'Unable to select image';
  static const emptyImageError = 'Selected image is empty';
  static const stockUpdateError = 'Unable to update stock status';
  static const deleteError = 'Unable to delete product';
  static const addSuccess = 'Product added';
  static const updateSuccess = 'Product updated';
  static const deleteSuccess = 'Product deleted';
  static const stockUpdateSuccess = 'Stock status updated';
  static const refresh = 'Refresh products';
  static const retry = 'Retry';
  static const loadMore = 'Load more';
  static const endOfList = 'All loaded products are visible';
  static const nameLabel = 'Name';
  static const categoryLabel = 'Category';
  static const selectCategory = 'Select category';
  static const noCategories = 'No categories available';
  static const categoriesError = 'Unable to load categories';
  static const currentCategoryPrefix = 'Current:';
  static const categoryPrefix = 'Category:';
  static const searchProducts = 'Search products';
  static const clearSearch = 'Clear search';
  static const filterByCategory = 'Filter by category';
  static const allCategories = 'All categories';
  static const clearFilters = 'Clear filters';
  static const noFilteredProducts = 'No products match these filters';
  static const priceLabel = 'Price';
  static const unitLabel = 'Unit';
  static const unitHelp = 'Example: 1 kg, 500 ml, pack';
  static const topOffer = 'Top Offer';
  static const topOffers = 'Top Offers';
  static const topOfferHelp = 'Show this product in offer sections.';
  static const discountPriceLabel = 'Discount Price (optional)';
  static const discountPriceHelp = 'Must be lower than the regular price.';
  static const discountRequired = 'Enter an offer price';
  static const imageLabel = 'Product image';
  static const imageHelp = 'Choose a gallery image to upload.';
  static const pickImage = 'Pick Image';
  static const changeImage = 'Change Image';
  static const imageRequired = 'Image is required';
  static const stockStatus = 'Stock Status';
  static const trackStock = 'Track Stock';
  static const trackStockHelp = 'Enable quantity and low-stock alerts.';
  static const stockQuantityLabel = 'Stock Quantity';
  static const lowStockThresholdLabel = 'Low Stock Alert';
  static const stock = 'Stock';
  static const lowStock = 'Low Stock';
  static const noStock = 'No stock left';
  static const stockNotTracked = 'Stock not tracked';
  static const available = 'Available';
  static const outOfStock = 'Out of Stock';
  static const deleteProduct = 'Delete Product';
  static const deletePrompt = 'Delete';
  static const cancel = 'Cancel';
  static const save = 'Save';
  static const delete = 'Delete';
  static const requiredField = 'Required';
  static const invalidPrice = 'Enter a valid price';
  static const invalidDiscountPrice = 'Enter a valid discount price';
  static const discountExceedsPrice = 'Discount must be less than price';
  static const invalidStockQuantity = 'Enter a valid stock quantity';
  static const invalidLowStockThreshold = 'Enter a valid alert quantity';
}
