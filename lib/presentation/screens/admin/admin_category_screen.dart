import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/app_error_handler.dart';
import '../../../core/images/image_upload_processor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/category.dart';
import '../../providers/auth_providers.dart';
import '../../providers/category_provider.dart';
import '../../widgets/app_cached_network_image.dart';
import '../../widgets/app_state_widgets.dart';

class AdminCategoryScreen extends ConsumerWidget {
  const AdminCategoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdminAsync = ref.watch(isCurrentUserAdminProvider);
    final isAdmin = isAdminAsync.maybeWhen(
      data: (value) => value,
      orElse: () => false,
    );

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text(CategoryManagementText.title)),
        body: Center(
          child: isAdminAsync.isLoading
              ? const CircularProgressIndicator()
              : const Text(CategoryManagementText.adminAccessRequired),
        ),
      );
    }

    final categoriesAsync = ref.watch(adminCategoryListProvider);
    final categoryAction = ref.watch(adminCategoryControllerProvider);
    final isSaving = categoryAction.isLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text(CategoryManagementText.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isSaving ? null : () => _openCategoryForm(context, ref),
        icon: isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text(CategoryManagementText.addCategory),
      ),
      body: categoriesAsync.when(
        data: (state) {
          final categories = state.categories;
          if (categories.isEmpty) {
            return _EmptyCategories(
              onAdd: isSaving ? null : () => _openCategoryForm(context, ref),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = _CategoryGridMetrics.crossAxisCountFor(
                constraints.maxWidth,
              );

              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                children: [
                  _CategorySummaryCard(totalCategories: categories.length),
                  const SizedBox(height: 14),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: categories.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: _CategoryGridMetrics.aspectRatioFor(
                        constraints.maxWidth,
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final category = categories[index];

                      return _CategoryGridTile(
                        category: category,
                        isBusy: isSaving,
                        onEdit: () {
                          _openCategoryForm(context, ref, category: category);
                        },
                        onDelete: () {
                          _confirmDelete(context, ref, category);
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _CategoryListFooter(
                    isLoading: state.isLoadingMore,
                    hasMore: state.hasMore,
                    onLoadMore: () => _loadMore(context, ref),
                  ),
                ],
              );
            },
          );
        },
        loading: () => const AppLoadingState(),
        error: (error, _) => AppRetryState(
          icon: Icons.error_outline_rounded,
          title: CategoryManagementText.loadError,
          message: AppErrorHandler.messageFor(
            error,
            fallback: CategoryManagementText.loadErrorSubtitle,
          ),
          onRetry: () {
            ref.read(adminCategoryListProvider.notifier).loadInitial();
          },
        ),
      ),
    );
  }

  Future<void> _openCategoryForm(
    BuildContext context,
    WidgetRef ref, {
    Category? category,
  }) async {
    final input = await showDialog<AdminCategoryInput>(
      context: context,
      builder: (_) => _CategoryFormDialog(category: category),
    );

    if (input == null || !context.mounted) return;

    try {
      await ref.read(adminCategoryControllerProvider.notifier).saveCategory(
            input,
          );
      if (!context.mounted) return;
      ref.read(adminCategoryListProvider.notifier).loadInitial();
      _showMessage(
        context,
        category == null
            ? CategoryManagementText.addSuccess
            : CategoryManagementText.updateSuccess,
      );
    } catch (error) {
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: CategoryManagementText.saveError,
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(CategoryManagementText.deleteCategory),
          content: Text(
            '${CategoryManagementText.deletePrompt} ${category.name}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(CategoryManagementText.cancel),
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade50,
                foregroundColor: Colors.red.shade700,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.delete_outline),
              label: const Text(CategoryManagementText.delete),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(adminCategoryControllerProvider.notifier).deleteCategory(
            category.id,
          );
      if (!context.mounted) return;
      ref.read(adminCategoryListProvider.notifier).loadInitial();
      _showMessage(context, CategoryManagementText.deleteSuccess);
    } catch (error) {
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: CategoryManagementText.deleteError,
      );
    }
  }

  void _showMessage(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadMore(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(adminCategoryListProvider.notifier).loadNext();
    } catch (error) {
      if (!context.mounted) return;

      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: CategoryManagementText.loadErrorSubtitle,
      );
    }
  }
}

class _CategorySummaryCard extends StatelessWidget {
  const _CategorySummaryCard({required this.totalCategories});

  final int totalCategories;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Icon(
              Icons.category_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  CategoryManagementText.categoryLibrary,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$totalCategories ${CategoryManagementText.categoriesActive}',
                  style: const TextStyle(
                    color: AppColors.mutedText,
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
}

class _CategoryGridTile extends StatelessWidget {
  const _CategoryGridTile({
    required this.category,
    required this.isBusy,
    required this.onEdit,
    required this.onDelete,
  });

  final Category category;
  final bool isBusy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: isBusy ? null : onEdit,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.soft,
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Center(
                      child: _CategoryImage(
                        imageUrl: category.imageUrl,
                        size: _CategoryGridMetrics.iconSize,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    category.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
              Positioned(
                right: -10,
                top: -10,
                child: PopupMenuButton<_CategoryCardAction>(
                  enabled: !isBusy,
                  tooltip: CategoryManagementText.categoryActions,
                  onSelected: (action) {
                    switch (action) {
                      case _CategoryCardAction.edit:
                        onEdit();
                        break;
                      case _CategoryCardAction.delete:
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _CategoryCardAction.edit,
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined),
                          SizedBox(width: 10),
                          Text(CategoryManagementText.editCategory),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: _CategoryCardAction.delete,
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: Colors.red),
                          SizedBox(width: 10),
                          Text(CategoryManagementText.deleteCategory),
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

class _CategoryListFooter extends StatelessWidget {
  const _CategoryListFooter({
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
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text(
            CategoryManagementText.endOfList,
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
        label: const Text(CategoryManagementText.loadMore),
      ),
    );
  }
}

class _CategoryImage extends StatelessWidget {
  const _CategoryImage({
    required this.imageUrl,
    required this.size,
  });

  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: const Icon(
        Icons.category_outlined,
        color: AppColors.primary,
        size: 34,
      ),
    );

    return AppCachedNetworkImage(
      imageUrl: imageUrl,
      width: size,
      height: size,
      borderRadius: BorderRadius.circular(AppRadii.md),
      memCacheWidth: _CategoryGridMetrics.tileImageCacheExtent,
      memCacheHeight: _CategoryGridMetrics.tileImageCacheExtent,
      maxWidthDiskCache: _CategoryGridMetrics.tileImageDiskCacheExtent,
      maxHeightDiskCache: _CategoryGridMetrics.tileImageDiskCacheExtent,
      placeholder: placeholder,
      errorPlaceholder: placeholder,
    );
  }
}

class _EmptyCategories extends StatelessWidget {
  const _EmptyCategories({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
              child: const Icon(
                Icons.apps_outlined,
                color: AppColors.primary,
                size: 36,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              CategoryManagementText.emptyState,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              CategoryManagementText.emptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text(CategoryManagementText.addCategory),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({this.category});

  final Category? category;

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  late final TextEditingController _nameController;
  Uint8List? _imageBytes;
  String? _imageFileName;
  String _imageContentType = CategoryProviderConfig.defaultImageContentType;
  String? _imageError;
  bool _isPickingImage = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.category != null;

    return AlertDialog(
      title: Text(
        isEditing
            ? CategoryManagementText.editCategory
            : CategoryManagementText.addCategory,
      ),
      content: SizedBox(
        width: _CategoryGridMetrics.formWidth,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TextFormInput(
                  controller: _nameController,
                  label: CategoryManagementText.nameLabel,
                  validator: _requiredText,
                ),
                const SizedBox(height: 12),
                _CategoryImagePickerField(
                  imageBytes: _imageBytes,
                  imageUrl: widget.category?.imageUrl ?? '',
                  isPickingImage: _isPickingImage,
                  errorText: _imageError,
                  onPickImage: _pickImage,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isPickingImage ? null : () => Navigator.pop(context),
          child: const Text(CategoryManagementText.cancel),
        ),
        ElevatedButton.icon(
          onPressed: _isPickingImage ? null : _submit,
          icon: const Icon(Icons.save_outlined),
          label: const Text(CategoryManagementText.save),
        ),
      ],
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
        imageQuality: _CategoryGridMetrics.pickedImageQuality,
        maxWidth: _CategoryGridMetrics.pickedImageMaxDimension,
        maxHeight: _CategoryGridMetrics.pickedImageMaxDimension,
      );
      if (image == null) return;

      final processed = await ImageUploadProcessor.process(
        bytes: await image.readAsBytes(),
        fileName: image.name,
        contentType: image.mimeType ?? _contentTypeFor(image.name),
        maxDimension: _CategoryGridMetrics.pickedImageMaxDimension,
        maxSourceBytes: _CategoryGridMetrics.maxSourceImageBytes,
        maxUploadBytes: _CategoryGridMetrics.maxUploadImageBytes,
        quality: _CategoryGridMetrics.pickedImageQuality,
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
        fallbackMessage: CategoryManagementText.imagePickError,
      );
    } catch (error) {
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: CategoryManagementText.imagePickError,
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
        (widget.category?.imageUrl.trim().isNotEmpty ?? false);

    setState(() {
      _imageError = hasImage ? null : CategoryManagementText.imageRequired;
    });

    if (!isFormValid || !hasImage) return;

    Navigator.pop(
      context,
      AdminCategoryInput(
        categoryId: widget.category?.id,
        name: _nameController.text.trim(),
        existingImageUrl: widget.category?.imageUrl ?? '',
        imageBytes: _imageBytes,
        imageFileName: _imageFileName,
        imageContentType: _imageContentType,
      ),
    );
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return CategoryManagementText.requiredField;
    }
    return null;
  }

  String _contentTypeFor(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png')) return 'image/png';
    if (lowerName.endsWith('.webp')) return 'image/webp';
    return CategoryProviderConfig.defaultImageContentType;
  }
}

class _TextFormInput extends StatelessWidget {
  const _TextFormInput({
    required this.controller,
    required this.label,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    );
  }
}

class _CategoryImagePickerField extends StatelessWidget {
  const _CategoryImagePickerField({
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
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: hasError ? Colors.red.shade700 : Colors.grey.shade300,
            ),
          ),
          child: Row(
            children: [
              _CategoryImagePreview(
                imageBytes: imageBytes,
                imageUrl: imageUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      CategoryManagementText.imageLabel,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CategoryManagementText.imageHelp,
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
                            ? CategoryManagementText.pickImage
                            : CategoryManagementText.changeImage,
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

class _CategoryImagePreview extends StatelessWidget {
  const _CategoryImagePreview({
    required this.imageBytes,
    required this.imageUrl,
  });

  final Uint8List? imageBytes;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: _CategoryGridMetrics.formImageSize,
      height: _CategoryGridMetrics.formImageSize,
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: const Icon(Icons.category_outlined, color: AppColors.primary),
    );

    final bytes = imageBytes;
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Image.memory(
          bytes,
          width: _CategoryGridMetrics.formImageSize,
          height: _CategoryGridMetrics.formImageSize,
          cacheWidth: _CategoryGridMetrics.formImageCacheExtent,
          cacheHeight: _CategoryGridMetrics.formImageCacheExtent,
          fit: BoxFit.cover,
        ),
      );
    }

    return AppCachedNetworkImage(
      imageUrl: imageUrl,
      width: _CategoryGridMetrics.formImageSize,
      height: _CategoryGridMetrics.formImageSize,
      borderRadius: BorderRadius.circular(AppRadii.md),
      memCacheWidth: _CategoryGridMetrics.formImageCacheExtent,
      memCacheHeight: _CategoryGridMetrics.formImageCacheExtent,
      maxWidthDiskCache: _CategoryGridMetrics.formImageDiskCacheExtent,
      maxHeightDiskCache: _CategoryGridMetrics.formImageDiskCacheExtent,
      placeholder: placeholder,
      errorPlaceholder: placeholder,
    );
  }
}

enum _CategoryCardAction { edit, delete }

class _CategoryGridMetrics {
  const _CategoryGridMetrics._();

  static const iconSize = 76.0;
  static const formWidth = 430.0;
  static const formImageSize = 84.0;
  static const tileImageCacheExtent = 160;
  static const tileImageDiskCacheExtent = 220;
  static const formImageCacheExtent = 180;
  static const formImageDiskCacheExtent = 240;
  static const pickedImageQuality = 86;
  static const pickedImageMaxDimension = 1200.0;
  static const maxSourceImageBytes = 6 * 1024 * 1024;
  static const maxUploadImageBytes = 1024 * 1024;

  static int crossAxisCountFor(double width) {
    if (width >= 980) return 5;
    if (width >= 720) return 4;
    if (width >= 520) return 3;
    return 2;
  }

  static double aspectRatioFor(double width) {
    if (width >= 720) return 1.02;
    return 0.92;
  }
}

class CategoryManagementText {
  const CategoryManagementText._();

  static const title = 'Manage Categories';
  static const categoryLibrary = 'Category Library';
  static const categoriesActive = 'categories active';
  static const adminAccessRequired = 'Admin access required';
  static const addCategory = 'Add Category';
  static const editCategory = 'Edit Category';
  static const deleteCategory = 'Delete Category';
  static const categoryActions = 'Category actions';
  static const emptyState = 'No categories added';
  static const emptySubtitle = 'Add categories so products can be grouped.';
  static const loadError = 'Unable to load categories';
  static const loadErrorSubtitle = 'Please try again in a moment.';
  static const loadMore = 'Load more';
  static const endOfList = 'All loaded categories are visible';
  static const saveError = 'Unable to save category';
  static const deleteError = 'Unable to delete category';
  static const imagePickError = 'Unable to select image';
  static const emptyImageError = 'Selected image is empty';
  static const addSuccess = 'Category added';
  static const updateSuccess = 'Category updated';
  static const deleteSuccess = 'Category deleted';
  static const deletePrompt = 'Delete';
  static const nameLabel = 'Name';
  static const imageLabel = 'Category image';
  static const imageHelp = 'Choose a gallery image to upload.';
  static const pickImage = 'Pick Image';
  static const changeImage = 'Change Image';
  static const imageRequired = 'Image is required';
  static const cancel = 'Cancel';
  static const save = 'Save';
  static const delete = 'Delete';
  static const requiredField = 'Required';
}
