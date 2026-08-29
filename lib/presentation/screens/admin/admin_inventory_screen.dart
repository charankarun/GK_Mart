import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/errors/app_error_handler.dart';
import '../../../core/images/image_upload_processor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/product_stats.dart';
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
  Timer? _searchDebounce;
  String? _selectedCategoryFilterId;
  String _lastSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.removeListener(_handleScroll);
    _searchController.removeListener(_handleSearchChanged);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) setState(() {});

    final query = _searchController.text.trim();
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      ProductManagementConfig.searchDebounceDuration,
      () {
        if (!mounted || query == _lastSearchQuery) return;
        _lastSearchQuery = query;
        ref.read(adminProductListProvider.notifier).search(query);
      },
    );
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
            _lastSearchQuery = _searchController.text.trim();
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
                const _InventorySummary(),
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
          final isUpdating =
              state.pendingAvailabilityProductIds.contains(product.id) ||
                  state.pendingStockProductIds.contains(product.id) ||
                  state.pendingDeleteProductIds.contains(product.id);
          return _ProductCard(
            product: product,
            categoryName: categoriesById[product.categoryId]?.name,
            isUpdating: isUpdating,
            onEdit: () => _openProductForm(product: product),
            onManageStock: () => _openStockActions(product),
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
    var initialBarcode = '';
    if (product == null) {
      final mode = await showDialog<_ProductEntryMode>(
        context: context,
        builder: (_) => const _ProductEntryModeDialog(),
      );
      if (mode == null || !mounted) return;

      if (mode == _ProductEntryMode.scanBarcode) {
        final scannedBarcode = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => const _BarcodeScannerScreen(),
          ),
        );
        if (!mounted) return;
        initialBarcode = scannedBarcode?.trim() ?? '';
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProductFormDialog(
        product: product,
        initialBarcode: initialBarcode,
      ),
    );

    if (saved != true || !mounted) return;

    _showMessage(
      product == null
          ? ProductManagementText.addSuccess
          : ProductManagementText.updateSuccess,
    );
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
          product.barcode.toLowerCase().contains(query) ||
          product.brand.toLowerCase().contains(query) ||
          product.categoryId.toLowerCase().contains(query) ||
          product.unit.toLowerCase().contains(query);
    }).toList();
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    setState(() {
      _searchController.clear();
      _selectedCategoryFilterId = null;
    });
    if (_lastSearchQuery.isNotEmpty) {
      _lastSearchQuery = '';
      ref.read(adminProductListProvider.notifier).search('');
    }
  }

  Future<void> _openStockActions(Product product) async {
    final action = await showModalBottomSheet<_StockAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text(ProductManagementText.increaseStock),
                onTap: () {
                  Navigator.pop(sheetContext, _StockAction.increase);
                },
              ),
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: const Text(ProductManagementText.decreaseStock),
                onTap: () {
                  Navigator.pop(sheetContext, _StockAction.decrease);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: const Text(ProductManagementText.updateStock),
                onTap: () {
                  Navigator.pop(sheetContext, _StockAction.update);
                },
              ),
            ],
          ),
        );
      },
    );

    if (action == null || !mounted) return;

    final quantity = await _promptStockQuantity(product, action);
    if (quantity == null || !mounted) return;

    final currentQuantity = product.stockQuantity ?? 0;
    final nextQuantity = switch (action) {
      _StockAction.increase => currentQuantity + quantity,
      _StockAction.decrease => currentQuantity - quantity,
      _StockAction.update => quantity,
    };

    if (nextQuantity < 0) {
      _showMessage(ProductManagementText.negativeStockBlocked);
      return;
    }

    final confirmed = await _confirmStockUpdate(
      product: product,
      currentQuantity: currentQuantity,
      nextQuantity: nextQuantity,
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(adminProductListProvider.notifier).updateStock(
            productId: product.id,
            stockQuantity: nextQuantity,
          );
      if (!mounted) return;
      _showMessage(ProductManagementText.stockQuantityUpdateSuccess);
    } catch (error) {
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: ProductManagementText.stockQuantityUpdateError,
      );
    }
  }

  Future<int?> _promptStockQuantity(
    Product product,
    _StockAction action,
  ) {
    return showDialog<int>(
      context: context,
      builder: (_) => _StockQuantityDialog(
        action: action,
        currentQuantity: product.stockQuantity ?? 0,
      ),
    );
  }

  Future<bool?> _confirmStockUpdate({
    required Product product,
    required int currentQuantity,
    required int nextQuantity,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(ProductManagementText.confirmStockUpdate),
          content: Text(
            '${product.name}\n'
            '${ProductManagementText.currentStock}: $currentQuantity\n'
            '${ProductManagementText.newStock}: $nextQuantity',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(ProductManagementText.cancel),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.check_rounded),
              label: const Text(ProductManagementText.confirm),
            ),
          ],
        );
      },
    );
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

class _InventorySummary extends ConsumerWidget {
  const _InventorySummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardInventoryStatsProvider);
    final stats = statsAsync.maybeWhen(
      data: (data) => data,
      orElse: () => null,
    );

    final total = stats?.totalProducts.toString() ?? '...';
    final available = stats?.availableProducts.toString() ?? '...';
    final lowStock = stats?.lowStockProducts.toString() ?? '...';
    final outOfStock = stats?.outOfStockProducts.toString() ?? '...';

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
                label: ProductManagementText.totalProducts,
                value: total,
                color: AppColors.primary,
              ),
              _SummaryMetric(
                label: ProductManagementText.available,
                value: available,
                color: AppColors.primary,
              ),
              _SummaryMetric(
                label: ProductManagementText.lowStock,
                value: lowStock,
                color: ProductManagementColors.warning,
              ),
              _SummaryMetric(
                label: ProductManagementText.outOfStock,
                value: outOfStock,
                color: ProductManagementColors.danger,
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
              hintText: ProductManagementText.searchProductsHint,
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
    required this.onManageStock,
    required this.onDelete,
    required this.onAvailabilityChanged,
  });

  final Product product;
  final String? categoryName;
  final bool isUpdating;
  final VoidCallback onEdit;
  final VoidCallback onManageStock;
  final VoidCallback onDelete;
  final ValueChanged<bool> onAvailabilityChanged;

  @override
  Widget build(BuildContext context) {
    final badgeStyle = _InventoryBadgeStyle.resolve(product);
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
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProductImage(
                imageUrl: product.imageUrl,
                onTap: () {
                  _showProductImagePreview(
                    context,
                    imageUrl: product.imageUrl,
                  );
                },
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
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (product.formattedQuantityUnit.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        product.formattedQuantityUnit,
                        style: const TextStyle(
                          color: AppColors.mutedText,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (_hasTopOffer(product))
                          const _ProductMiniChip(
                            label: ProductManagementText.topOffer,
                            color: AppColors.accent,
                            background: AppColors.softOrange,
                          ),
                        _ProductMiniChip(
                          label: badgeStyle.label,
                          color: badgeStyle.foreground,
                          background: badgeStyle.background,
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
                        style: const TextStyle(
                          color: AppColors.mutedText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (product.barcode.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        '${ProductManagementText.barcodePrefix} '
                        '${product.barcode.trim()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.mutedText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _PriceRow(product: product),
                    const SizedBox(height: 8),
                    _StockLine(style: stockStyle),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                product.isAvailable ? 'Active' : 'Inactive',
                                style: const TextStyle(
                                  color: AppColors.mutedText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              if (isUpdating)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 1.8),
                                  ),
                                )
                              else
                                Transform.scale(
                                  scale: 0.78,
                                  child: Switch(
                                    value: product.isAvailable,
                                    onChanged: onAvailabilityChanged,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(6),
                                tooltip: ProductManagementText.manageStock,
                                onPressed: isUpdating ? null : onManageStock,
                                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(6),
                                tooltip: ProductManagementText.editProduct,
                                onPressed: isUpdating ? null : onEdit,
                                icon: const Icon(Icons.edit_outlined, size: 18),
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(6),
                                tooltip: ProductManagementText.deleteProduct,
                                onPressed: isUpdating ? null : onDelete,
                                color: ProductManagementColors.delete,
                                icon: const Icon(Icons.delete_outline, size: 18),
                              ),
                            ],
                          ),
                        ],
                      ),
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
    required this.onTap,
  });

  final String imageUrl;
  final VoidCallback onTap;

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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: AppCachedNetworkImage(
          imageUrl: imageUrl,
          width: ProductManagementConfig.productImageSize,
          height: ProductManagementConfig.productImageSize,
          borderRadius: BorderRadius.circular(AppRadii.md),
          memCacheWidth: ProductManagementConfig.productImageCacheExtent,
          memCacheHeight: ProductManagementConfig.productImageCacheExtent,
          maxWidthDiskCache:
              ProductManagementConfig.productImageDiskCacheExtent,
          maxHeightDiskCache:
              ProductManagementConfig.productImageDiskCacheExtent,
          placeholder: placeholder,
          errorPlaceholder: placeholder,
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
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

enum _ProductEntryMode {
  scanBarcode,
  manualEntry,
}

class _ProductEntryModeDialog extends StatelessWidget {
  const _ProductEntryModeDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(ProductManagementText.chooseEntryMode),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.document_scanner_outlined),
            title: const Text(ProductManagementText.scanBarcode),
            subtitle: const Text(ProductManagementText.scanBarcodeHelp),
            onTap: () {
              Navigator.pop(context, _ProductEntryMode.scanBarcode);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_note_rounded),
            title: const Text(ProductManagementText.manualEntry),
            subtitle: const Text(ProductManagementText.manualEntryHelp),
            onTap: () {
              Navigator.pop(context, _ProductEntryMode.manualEntry);
            },
          ),
        ],
      ),
    );
  }
}

enum _StockAction {
  increase,
  decrease,
  update,
}

class _StockQuantityDialog extends StatefulWidget {
  const _StockQuantityDialog({
    required this.action,
    required this.currentQuantity,
  });

  final _StockAction action;
  final int currentQuantity;

  @override
  State<_StockQuantityDialog> createState() => _StockQuantityDialogState();
}

class _StockQuantityDialogState extends State<_StockQuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantityController;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: widget.action == _StockAction.update
          ? widget.currentQuantity.toString()
          : '',
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _quantityController,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: _label,
            helperText:
                '${ProductManagementText.currentStock}: ${widget.currentQuantity}',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          validator: _validateQuantity,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(ProductManagementText.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text(ProductManagementText.continueAction),
        ),
      ],
    );
  }

  String get _title {
    return switch (widget.action) {
      _StockAction.increase => ProductManagementText.increaseStock,
      _StockAction.decrease => ProductManagementText.decreaseStock,
      _StockAction.update => ProductManagementText.updateStock,
    };
  }

  String get _label {
    return switch (widget.action) {
      _StockAction.increase => ProductManagementText.quantityToAdd,
      _StockAction.decrease => ProductManagementText.quantityToRemove,
      _StockAction.update => ProductManagementText.newStockQuantity,
    };
  }

  String? _validateQuantity(String? value) {
    final quantity = int.tryParse(value?.trim() ?? '');
    if (quantity == null) return ProductManagementText.invalidStockQuantity;

    if (widget.action == _StockAction.update) {
      if (quantity < 0) return ProductManagementText.invalidStockQuantity;
      return null;
    }

    if (quantity <= 0) return ProductManagementText.invalidStockQuantity;
    if (widget.action == _StockAction.decrease &&
        quantity > widget.currentQuantity) {
      return ProductManagementText.negativeStockBlocked;
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.pop(context, int.parse(_quantityController.text.trim()));
  }
}

class _BarcodeScannerScreen extends StatefulWidget {
  const _BarcodeScannerScreen();

  @override
  State<_BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<_BarcodeScannerScreen> {
  late final MobileScannerController _controller;
  bool _hasResult = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.itf14,
      ],
    );
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(ProductManagementText.scanBarcode),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          _ScannerTorchButton(controller: _controller),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            fit: BoxFit.cover,
            tapToFocus: true,
            onDetect: _handleBarcode,
            onDetectError: (_, __) {},
            errorBuilder: (context, error) {
              return _ScannerErrorView(
                message: error.errorDetails?.message ?? error.errorCode.message,
                onRetry: () => _controller.start(),
              );
            },
          ),
          const _ScannerOverlay(),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.pop(context, ''),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text(ProductManagementText.manualEntry),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_hasResult) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      _hasResult = true;
      unawaited(_controller.stop());
      Navigator.pop(context, value);
      return;
    }
  }
}

class _ScannerTorchButton extends StatelessWidget {
  const _ScannerTorchButton({required this.controller});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, child) {
        if (!state.isInitialized || !state.isRunning) {
          return const SizedBox.shrink();
        }

        final icon = switch (state.torchState) {
          TorchState.on => Icons.flash_on_rounded,
          TorchState.off => Icons.flash_off_rounded,
          TorchState.auto => Icons.flash_auto_rounded,
          TorchState.unavailable => Icons.flashlight_off_rounded,
        };

        return IconButton(
          tooltip: ProductManagementText.toggleTorch,
          onPressed: state.torchState == TorchState.unavailable
              ? null
              : controller.toggleTorch,
          icon: Icon(icon),
        );
      },
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 280,
          height: 160,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 3),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
        ),
      ),
    );
  }
}

class _ScannerErrorView extends StatelessWidget {
  const _ScannerErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white,
                size: 38,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text(ProductManagementText.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductFormDialog extends ConsumerStatefulWidget {
  const _ProductFormDialog({
    this.product,
    this.initialBarcode = '',
  });

  final Product? product;
  final String initialBarcode;

  @override
  ConsumerState<_ProductFormDialog> createState() {
    return _ProductFormDialogState();
  }
}

class _ProductFormDialogState extends ConsumerState<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _quantityValueController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _priceController;
  late final TextEditingController _discountPriceController;
  late final TextEditingController _stockQuantityController;
  late final TextEditingController _lowStockThresholdController;
  late final TextEditingController _descriptionController;
  late bool _isAvailable;
  late bool _trackStock;
  String? _selectedCategoryId;
  String? _selectedUnit;
  Uint8List? _imageBytes;
  String? _imageFileName;
  String _imageContentType = ProductProviderConfig.defaultImageContentType;
  String? _imageError;
  String? _barcodeLookupMessage;
  bool _isPickingImage = false;
  bool _isLookingUpBarcode = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;

    _nameController = TextEditingController(text: product?.name ?? '');
    _descriptionController = TextEditingController(text: product?.description ?? '');
    _quantityValueController = TextEditingController(
      text: product?.quantityValue == null
          ? ''
          : (product!.quantityValue == product.quantityValue!.toInt()
              ? product.quantityValue!.toInt().toString()
              : product.quantityValue!.toString()),
    );
    _selectedUnit = product?.unit ?? '';
    _barcodeController = TextEditingController(
      text: product?.barcode ?? widget.initialBarcode.trim(),
    );
    _priceController = TextEditingController(
      text: product == null ? '' : _formatInputPrice(product.price),
    );
    _discountPriceController = TextEditingController(
      text: product == null ? '' : _formatInputPrice(product.sellingPrice),
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
    _trackStock = product?.trackStock ?? (product == null || product.stockQuantity != null);

    if (product == null && widget.initialBarcode.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _lookupBarcode(widget.initialBarcode);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityValueController.dispose();
    _barcodeController.dispose();
    _priceController.dispose();
    _discountPriceController.dispose();
    _stockQuantityController.dispose();
    _lowStockThresholdController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.product != null;
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    return PopScope(
      canPop: !_isSaving,
      child: AlertDialog(
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
                    controller: _descriptionController,
                    label: 'Description (Optional)',
                    keyboardType: TextInputType.multiline,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  _buildCategoryDropdown(categoriesAsync),
                  const SizedBox(height: 12),
                  _BarcodeFormInput(
                    controller: _barcodeController,
                    isLookingUp: _isLookingUpBarcode,
                    lookupMessage: _barcodeLookupMessage,
                    onScan: _scanBarcode,
                  ),
                  const SizedBox(height: 12),
                  _TextFormInput(
                    controller: _priceController,
                    label: ProductManagementText.mrpLabel,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _requiredPositivePrice,
                  ),
                  const SizedBox(height: 12),
                  _TextFormInput(
                    controller: _discountPriceController,
                    label: ProductManagementText.sellingPriceLabel,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    helperText: ProductManagementText.sellingPriceHelp,
                    validator: _sellingPriceValidator,
                  ),
                  const SizedBox(height: 12),
                  _TextFormInput(
                    controller: _quantityValueController,
                    label: 'Quantity Value',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    helperText: 'Example: 500, 1, 12',
                    validator: (val) {
                      if (val != null && val.trim().isNotEmpty) {
                        final doubleVal = double.tryParse(val.trim());
                        if (doubleVal == null || doubleVal < 0) {
                          return 'Please enter a valid positive number';
                        }
                      }
                      if ((_selectedUnit != null && _selectedUnit!.isNotEmpty) && (val == null || val.trim().isEmpty)) {
                        return 'Quantity value is required if unit is selected';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedUnit,
                    decoration: InputDecoration(
                      labelText: 'Unit',
                      helperText: 'Select the packaging unit (e.g. ml, Kg)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                    ),
                    items: () {
                      final currentUnit = _selectedUnit ?? '';
                      final dropdownUnits = [
                        '',
                        'Kg',
                        'g',
                        'L',
                        'ml',
                        'Pack',
                        'Packet',
                        'Piece',
                        'Bottle',
                        'Box',
                        'Dozen',
                      ];
                      if (currentUnit.isNotEmpty && !dropdownUnits.contains(currentUnit)) {
                        dropdownUnits.add(currentUnit);
                      }
                      return dropdownUnits.map((unit) {
                        return DropdownMenuItem<String>(
                          value: unit,
                          child: Text(unit.isEmpty ? 'None' : unit),
                        );
                      }).toList();
                    }(),
                    onChanged: _isSaving
                        ? null
                        : (val) {
                            setState(() {
                              _selectedUnit = val;
                            });
                          },
                    validator: (val) {
                      if ((val == null || val.isEmpty) && _quantityValueController.text.trim().isNotEmpty) {
                        return 'Unit is required if quantity value is entered';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(ProductManagementText.trackStock),
                    subtitle: const Text(ProductManagementText.trackStockHelp),
                    value: _trackStock,
                    onChanged: _isSaving ? null : (value) {
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
                    onPickImage: _isSaving ? () {} : _pickImage,
                    onViewImage: () {
                      _showProductImagePreview(
                        context,
                        imageBytes: _imageBytes,
                        imageUrl: widget.product?.imageUrl ?? '',
                      );
                    },
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
                    onChanged: _isSaving ? null : (value) {
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
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            child: const Text(ProductManagementText.cancel),
          ),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _submit,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text(ProductManagementText.save),
          ),
        ],
      ),
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

  Future<void> _scanBarcode() async {
    final scannedBarcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const _BarcodeScannerScreen(),
      ),
    );
    if (!mounted) return;

    final barcode = scannedBarcode?.trim();
    if (barcode == null || barcode.isEmpty) return;

    _barcodeController.text = barcode;
    await _lookupBarcode(barcode);
  }

  Future<void> _lookupBarcode(String barcode) async {
    final normalizedBarcode = barcode.trim();
    if (normalizedBarcode.isEmpty || _isLookingUpBarcode) return;

    setState(() {
      _isLookingUpBarcode = true;
      _barcodeLookupMessage = ProductManagementText.barcodeLookupLoading;
    });

    try {
      final result = await const _BarcodeProductLookupService().lookup(
        normalizedBarcode,
      );
      if (!mounted) return;

      if (result == null) {
        setState(() {
          _barcodeLookupMessage =
              ProductManagementText.barcodeLookupUnavailable;
        });
        return;
      }

      setState(() {
        if (_nameController.text.trim().isEmpty &&
            result.productName.trim().isNotEmpty) {
          _nameController.text = result.productName.trim();
        }
        final mrp = result.mrp;
        if (_priceController.text.trim().isEmpty && mrp != null && mrp > 0) {
          final formattedMrp = _formatInputPrice(mrp);
          _priceController.text = formattedMrp;
          if (_discountPriceController.text.trim().isEmpty) {
            _discountPriceController.text = formattedMrp;
          }
        }
        _barcodeLookupMessage = ProductManagementText.barcodeLookupApplied;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _barcodeLookupMessage = ProductManagementText.barcodeLookupUnavailable;
      });
    } finally {
      if (mounted) {
        setState(() => _isLookingUpBarcode = false);
      }
    }
  }

  Future<void> _submit() async {
    final isFormValid = _formKey.currentState?.validate() == true;
    final hasImage = _imageBytes != null ||
        (widget.product?.imageUrl.trim().isNotEmpty ?? false);

    setState(() {
      _imageError = hasImage ? null : ProductManagementText.imageRequired;
    });

    if (!isFormValid || !hasImage || _isSaving) return;

    setState(() {
      _isSaving = true;
    });

    final mrp = double.parse(_priceController.text.trim());
    final sellingPrice = double.parse(_discountPriceController.text.trim());
    final stockQuantity = _trackStock
        ? int.tryParse(_stockQuantityController.text.trim()) ?? 0
        : null;

    final input = AdminProductInput(
      productId: widget.product?.id,
      name: _nameController.text.trim(),
      categoryId: _selectedCategoryId!.trim(),
      price: mrp,
      discountPrice: sellingPrice < mrp ? sellingPrice : 0,
      existingImageUrl: widget.product?.imageUrl ?? '',
      isAvailable: _trackStock && stockQuantity != null
          ? stockQuantity > 0
          : _isAvailable,
      unit: _selectedUnit ?? '',
      barcode: _barcodeController.text.trim(),
      brand: widget.product?.brand ?? '',
      trackStock: _trackStock,
      stockQuantity: stockQuantity,
      lowStockThreshold: _trackStock
          ? int.tryParse(_lowStockThresholdController.text.trim()) ??
              ProductManagementConfig.lowStockThreshold
          : ProductManagementConfig.lowStockThreshold,
      quantityValue: double.tryParse(_quantityValueController.text.trim()),
      description: _descriptionController.text.trim(),
      imageBytes: _imageBytes,
      imageFileName: _imageFileName,
      imageContentType: _imageContentType,
    );

    try {
      await ref.read(adminProductListProvider.notifier).saveProduct(input);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: ProductManagementText.saveError,
      );
    }
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

  String? _sellingPriceValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return ProductManagementText.sellingPriceRequired;

    final sellingPrice = double.tryParse(trimmed);
    final mrp = double.tryParse(_priceController.text.trim());

    if (sellingPrice == null || sellingPrice <= 0) {
      return ProductManagementText.invalidSellingPrice;
    }

    if (mrp != null && mrp > 0 && sellingPrice > mrp) {
      return ProductManagementText.sellingPriceExceedsMrp;
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
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final String? helperText;
  final FormFieldValidator<String>? validator;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      maxLines: maxLines,
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

class _BarcodeFormInput extends StatelessWidget {
  const _BarcodeFormInput({
    required this.controller,
    required this.isLookingUp,
    required this.lookupMessage,
    required this.onScan,
  });

  final TextEditingController controller;
  final bool isLookingUp;
  final String? lookupMessage;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: ProductManagementText.barcodeLabel,
        helperText: lookupMessage ?? ProductManagementText.barcodeHelp,
        prefixIcon: const Icon(Icons.qr_code_2_rounded),
        suffixIcon: IconButton(
          tooltip: ProductManagementText.scanBarcode,
          onPressed: isLookingUp ? null : onScan,
          icon: isLookingUp
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.document_scanner_outlined),
        ),
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
    required this.onViewImage,
  });

  final Uint8List? imageBytes;
  final String imageUrl;
  final bool isPickingImage;
  final String? errorText;
  final VoidCallback onPickImage;
  final VoidCallback onViewImage;

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
                onTap: onViewImage,
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
    required this.onTap,
  });

  final Uint8List? imageBytes;
  final String imageUrl;
  final VoidCallback onTap;

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
      return InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Image.memory(
            bytes,
            width: ProductManagementConfig.formImageSize,
            height: ProductManagementConfig.formImageSize,
            cacheWidth: ProductManagementConfig.formImageCacheExtent,
            cacheHeight: ProductManagementConfig.formImageCacheExtent,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: AppCachedNetworkImage(
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
      ),
    );
  }
}

class _InventoryBadgeStyle {
  const _InventoryBadgeStyle({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  static _InventoryBadgeStyle resolve(Product product) {
    if (!product.isAvailable || product.isStockEmpty) {
      return _InventoryBadgeStyle(
        label: ProductManagementText.outOfStock,
        foreground: ProductManagementColors.danger,
        background: ProductManagementColors.dangerBackground,
      );
    }

    if (product.isLowStock) {
      return _InventoryBadgeStyle(
        label: ProductManagementText.lowStock,
        foreground: ProductManagementColors.warning,
        background: AppColors.softOrange,
      );
    }

    return const _InventoryBadgeStyle(
      label: ProductManagementText.available,
      foreground: AppColors.primary,
      background: AppColors.softGreen,
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
    if (!product.trackStock) {
      return const _StockStyle(
        label: ProductManagementText.stockNotTracked,
        color: AppColors.mutedText,
        icon: Icons.inventory_2_outlined,
      );
    }

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
        color: ProductManagementColors.danger,
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

void _showProductImagePreview(
  BuildContext context, {
  Uint8List? imageBytes,
  required String imageUrl,
}) {
  final hasImage = imageBytes != null || imageUrl.trim().isNotEmpty;

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final fallback = const AppImagePlaceholder(
        icon: Icons.broken_image_outlined,
        iconSize: 42,
        backgroundColor: AppColors.softGreen,
      );

      Widget image;
      if (imageBytes != null) {
        image = Image.memory(
          imageBytes,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        );
      } else if (hasImage) {
        image = AppCachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.contain,
          placeholder: const AppImagePlaceholder(isLoading: true),
          errorPlaceholder: fallback,
        );
      } else {
        image = fallback;
      }

      return Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: MediaQuery.sizeOf(dialogContext).height * 0.72,
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Center(child: image),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: IconButton.filledTonal(
                tooltip: ProductManagementText.close,
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _BarcodeProductLookup {
  const _BarcodeProductLookup({
    required this.productName,
    required this.mrp,
  });

  final String productName;
  final double? mrp;
}

class _BarcodeProductLookupService {
  const _BarcodeProductLookupService();

  Future<_BarcodeProductLookup?> lookup(String barcode) async {
    final normalizedBarcode = barcode.trim();
    if (normalizedBarcode.isEmpty) return null;

    final client = HttpClient();
    client.connectionTimeout = ProductManagementConfig.lookupTimeout;
    try {
      final uri = Uri.https(
        'world.openfoodfacts.org',
        '/api/v2/product/$normalizedBarcode.json',
        {
          'fields': 'product_name,mrp,price,maximum_retail_price',
        },
      );
      final request = await client.getUrl(uri).timeout(
            ProductManagementConfig.lookupTimeout,
          );
      final response = await request.close().timeout(
            ProductManagementConfig.lookupTimeout,
          );
      if (response.statusCode != HttpStatus.ok) return null;

      final body = await response.transform(utf8.decoder).join().timeout(
            ProductManagementConfig.lookupTimeout,
          );
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['status'] != 1) return null;

      final product = decoded['product'];
      if (product is! Map<String, dynamic>) return null;

      final name = _lookupString(product['product_name']);
      final mrp = _lookupAmount(
        product['mrp'] ?? product['maximum_retail_price'] ?? product['price'],
      );

      if (name.isEmpty && mrp == null) return null;
      return _BarcodeProductLookup(
        productName: name,
        mrp: mrp,
      );
    } finally {
      client.close(force: true);
    }
  }
}

String _lookupString(Object? value) {
  return value?.toString().trim() ?? '';
}

double? _lookupAmount(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();

  final normalized = value.toString().replaceAll(RegExp(r'[^0-9.]'), '').trim();
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

class ProductManagementConfig {
  const ProductManagementConfig._();

  static const listExtraItems = 2;
  static const loadMoreExtent = 420.0;
  static const searchDebounceDuration = Duration(milliseconds: 350);
  static const lookupTimeout = Duration(seconds: 4);
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
  static const danger = Color(0xFFDC2626);
  static const dangerBackground = Color(0xFFFEE2E2);
  static const delete = Color(0xFFDC2626);
}

class ProductManagementText {
  const ProductManagementText._();

  static const title = 'Manage Products';
  static const dashboardTitle = 'Product Inventory';
  static const dashboardSubtitle = 'Add, edit, and keep stock status current.';
  static const totalProducts = 'Total Products';
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
  static const stockQuantityUpdateError = 'Unable to update stock quantity';
  static const deleteError = 'Unable to delete product';
  static const addSuccess = 'Product added';
  static const updateSuccess = 'Product updated';
  static const deleteSuccess = 'Product deleted';
  static const stockUpdateSuccess = 'Stock status updated';
  static const stockQuantityUpdateSuccess = 'Stock quantity updated';
  static const refresh = 'Refresh products';
  static const retry = 'Retry';
  static const loadMore = 'Load more';
  static const endOfList = 'All loaded products are visible';
  static const nameLabel = 'Name';
  static const brandLabel = 'Brand';
  static const categoryLabel = 'Category';
  static const selectCategory = 'Select category';
  static const noCategories = 'No categories available';
  static const categoriesError = 'Unable to load categories';
  static const currentCategoryPrefix = 'Current:';
  static const categoryPrefix = 'Category:';
  static const barcodePrefix = 'Barcode:';
  static const searchProducts = 'Search inventory';
  static const searchProductsHint = 'Search product name or barcode';
  static const clearSearch = 'Clear search';
  static const filterByCategory = 'Filter by category';
  static const allCategories = 'All categories';
  static const clearFilters = 'Clear filters';
  static const noFilteredProducts = 'No products match these filters';
  static const chooseEntryMode = 'Add product';
  static const scanBarcode = 'Scan Barcode';
  static const scanBarcodeHelp = 'Use the camera to fill the barcode field.';
  static const manualEntry = 'Manual Entry';
  static const manualEntryHelp = 'Enter product details without scanning.';
  static const barcodeLabel = 'Barcode';
  static const barcodeHelp = 'Scan or type the product barcode.';
  static const barcodeLookupLoading = 'Looking up product details...';
  static const barcodeLookupApplied = 'Product details filled where available.';
  static const barcodeLookupUnavailable =
      'Lookup unavailable. Continue manually.';
  static const toggleTorch = 'Toggle flash';
  static const mrpLabel = 'MRP';
  static const sellingPriceLabel = 'Selling Price';
  static const sellingPriceHelp = 'Must be less than or equal to MRP.';
  static const unitLabel = 'Unit';
  static const unitHelp = 'Example: 1 kg, 500 ml, pack';
  static const topOffer = 'Top Offer';
  static const topOffers = 'Top Offers';
  static const topOfferHelp = 'Show this product in offer sections.';
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
  static const manageStock = 'Manage stock';
  static const increaseStock = 'Increase stock';
  static const decreaseStock = 'Decrease stock';
  static const updateStock = 'Update stock';
  static const confirmStockUpdate = 'Confirm stock update';
  static const currentStock = 'Current stock';
  static const newStock = 'New stock';
  static const quantityToAdd = 'Quantity to add';
  static const quantityToRemove = 'Quantity to remove';
  static const newStockQuantity = 'New stock quantity';
  static const negativeStockBlocked = 'Stock cannot go below zero';
  static const continueAction = 'Continue';
  static const confirm = 'Confirm';
  static const stock = 'Stock';
  static const lowStock = 'Low Stock';
  static const noStock = 'No stock left';
  static const stockNotTracked = 'Stock Tracking Disabled';
  static const available = 'Available';
  static const outOfStock = 'Out of Stock';
  static const deleteProduct = 'Delete Product';
  static const deletePrompt = 'Delete';
  static const cancel = 'Cancel';
  static const save = 'Save';
  static const delete = 'Delete';
  static const close = 'Close';
  static const requiredField = 'Required';
  static const invalidPrice = 'Enter a valid price';
  static const sellingPriceRequired = 'Enter a selling price';
  static const invalidSellingPrice = 'Enter a valid selling price';
  static const sellingPriceExceedsMrp = 'Selling price cannot exceed MRP';
  static const invalidStockQuantity = 'Enter a valid stock quantity';
  static const invalidLowStockThreshold = 'Enter a valid alert quantity';
}
