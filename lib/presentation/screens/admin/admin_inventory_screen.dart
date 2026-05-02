import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../domain/entities/category.dart';
import '../../../domain/entities/product.dart';
import '../../providers/auth_providers.dart';
import '../../providers/catalog_providers.dart';
import '../../providers/product_provider.dart';

class AdminInventoryScreen extends ConsumerStatefulWidget {
  const AdminInventoryScreen({super.key});

  @override
  ConsumerState<AdminInventoryScreen> createState() {
    return _AdminInventoryScreenState();
  }
}

class _AdminInventoryScreenState extends ConsumerState<AdminInventoryScreen> {
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

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
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
        onPressed: () => _openProductForm(),
        icon: const Icon(Icons.add),
        label: const Text(ProductManagementText.addProduct),
      ),
      body: productsAsync.when(
        data: _buildProductList,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _InventoryError(
          onRetry: () {
            ref.read(adminProductListProvider.notifier).loadInitial();
          },
        ),
      ),
    );
  }

  Widget _buildProductList(AdminProductListState state) {
    final products = state.products;

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
            return _InventorySummary(products: products);
          }

          final productIndex = index - 1;
          if (productIndex >= products.length) {
            return _ProductListFooter(
              state: state,
              onLoadMore: () => _loadNextPage(showErrors: true),
            );
          }

          final product = products[productIndex];
          return _ProductCard(
            product: product,
            onEdit: () => _openProductForm(product: product),
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
    } catch (_) {
      if (!mounted) return;
      _showMessage(ProductManagementText.saveError);
    }
  }

  Future<void> _updateAvailability(Product product, bool isAvailable) async {
    try {
      await ref.read(adminProductListProvider.notifier).updateAvailability(
            productId: product.id,
            isAvailable: isAvailable,
          );
      if (!mounted) return;
      _showMessage(ProductManagementText.stockUpdateSuccess);
    } catch (_) {
      if (!mounted) return;
      _showMessage(ProductManagementText.stockUpdateError);
    }
  }

  Future<void> _loadNextPage({required bool showErrors}) async {
    try {
      await ref.read(adminProductListProvider.notifier).loadNext();
    } catch (_) {
      if (!mounted || !showErrors) return;
      _showMessage(ProductManagementText.loadMoreError);
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
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
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: ProductManagementText.loadedProducts,
                  value: products.length.toString(),
                  color: const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryMetric(
                  label: ProductManagementText.available,
                  value: availableCount.toString(),
                  color: const Color(0xFF15803D),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryMetric(
                  label: ProductManagementText.outOfStock,
                  value: outOfStockCount.toString(),
                  color: const Color(0xFFDC2626),
                ),
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
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

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onEdit,
    required this.onAvailabilityChanged,
  });

  final Product product;
  final VoidCallback onEdit;
  final ValueChanged<bool> onAvailabilityChanged;

  @override
  Widget build(BuildContext context) {
    final availabilityStyle = _AvailabilityStyle.resolve(product.isAvailable);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
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
                      _AvailabilityChip(style: availabilityStyle),
                    ],
                  ),
                  if (product.categoryId.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      '${ProductManagementText.categoryPrefix} ${product.categoryId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _PriceRow(product: product),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.isAvailable
                              ? ProductManagementText.available
                              : ProductManagementText.outOfStock,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                      Switch(
                        value: product.isAvailable,
                        onChanged: onAvailabilityChanged,
                      ),
                      IconButton(
                        tooltip: ProductManagementText.editProduct,
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
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
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.image, color: Colors.black45),
    );

    if (imageUrl.trim().isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        width: ProductManagementConfig.productImageSize,
        height: ProductManagementConfig.productImageSize,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
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
              color: Color(0xFF15803D),
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

class _AvailabilityChip extends StatelessWidget {
  const _AvailabilityChip({required this.style});

  final _AvailabilityStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          color: style.foreground,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
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
              color: Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: Color(0xFF2563EB),
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
  late final TextEditingController _priceController;
  late final TextEditingController _discountPriceController;
  late bool _isAvailable;
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
    _priceController = TextEditingController(
      text: product == null ? '' : _formatInputPrice(product.price),
    );
    _discountPriceController = TextEditingController(
      text: product == null ? '' : _formatInputPrice(product.discountPrice),
    );
    _selectedCategoryId = product?.categoryId;
    _isAvailable = product?.isAvailable ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _discountPriceController.dispose();
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
                _TextFormInput(
                  controller: _discountPriceController,
                  label: ProductManagementText.discountPriceLabel,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _discountPriceValidator,
                ),
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
              borderRadius: BorderRadius.circular(8),
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

      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) {
        throw StateError(ProductManagementText.emptyImageError);
      }

      setState(() {
        _imageBytes = bytes;
        _imageFileName = image.name;
        _imageContentType = image.mimeType ?? _contentTypeFor(image.name);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ProductManagementText.imagePickError)),
      );
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  void _submit() {
    final isFormValid = _formKey.currentState!.validate();
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
        discountPrice:
            double.tryParse(_discountPriceController.text.trim()) ?? 0,
        existingImageUrl: widget.product?.imageUrl ?? '',
        isAvailable: _isAvailable,
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
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    final discountPrice = double.tryParse(trimmed);
    final price = double.tryParse(_priceController.text.trim());

    if (discountPrice == null || discountPrice < 0) {
      return ProductManagementText.invalidDiscountPrice;
    }

    if (price != null && price > 0 && discountPrice >= price) {
      return ProductManagementText.discountExceedsPrice;
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
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
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
          borderRadius: BorderRadius.circular(8),
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
            borderRadius: BorderRadius.circular(8),
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
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.image, color: Colors.black45),
    );

    final bytes = imageBytes;
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          width: ProductManagementConfig.formImageSize,
          height: ProductManagementConfig.formImageSize,
          fit: BoxFit.cover,
        ),
      );
    }

    if (imageUrl.trim().isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        width: ProductManagementConfig.formImageSize,
        height: ProductManagementConfig.formImageSize,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
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
        foreground: Colors.green.shade800,
        background: Colors.green.shade50,
      );
    }

    return _AvailabilityStyle(
      label: ProductManagementText.outOfStock,
      foreground: Colors.red.shade800,
      background: Colors.red.shade50,
    );
  }
}

String _formatPrice(double price) {
  return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
}

class ProductManagementConfig {
  const ProductManagementConfig._();

  static const listExtraItems = 2;
  static const loadMoreExtent = 420.0;
  static const productImageSize = 82.0;
  static const formWidth = 460.0;
  static const formImageSize = 86.0;
  static const pickedImageQuality = 86;
  static const pickedImageMaxDimension = 1400.0;
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
  static const addSuccess = 'Product added';
  static const updateSuccess = 'Product updated';
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
  static const priceLabel = 'Price';
  static const discountPriceLabel = 'Discount Price';
  static const imageLabel = 'Product image';
  static const imageHelp = 'Choose a gallery image to upload.';
  static const pickImage = 'Pick Image';
  static const changeImage = 'Change Image';
  static const imageRequired = 'Image is required';
  static const stockStatus = 'Stock Status';
  static const available = 'Available';
  static const outOfStock = 'Out of Stock';
  static const cancel = 'Cancel';
  static const save = 'Save';
  static const requiredField = 'Required';
  static const invalidPrice = 'Enter a valid price';
  static const invalidDiscountPrice = 'Enter a valid discount price';
  static const discountExceedsPrice = 'Discount must be less than price';
}
