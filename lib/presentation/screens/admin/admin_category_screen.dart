import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/category.dart';
import '../../providers/auth_providers.dart';
import '../../providers/catalog_providers.dart';

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

    final categoriesAsync = ref.watch(categoriesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(CategoryManagementText.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCategoryForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text(CategoryManagementText.addCategory),
      ),
      body: categoriesAsync.when(
        data: (categories) {
          if (categories.isEmpty) {
            return const Center(child: Text(CategoryManagementText.emptyState));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final category = categories[index];
              return _CategoryCard(
                category: category,
                onEdit: () {
                  _openCategoryForm(context, ref, category: category);
                },
                onDelete: () {
                  _confirmDelete(context, ref, category);
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text(CategoryManagementText.loadError),
        ),
      ),
    );
  }

  Future<void> _openCategoryForm(
    BuildContext context,
    WidgetRef ref, {
    Category? category,
  }) async {
    final formData = await showDialog<_CategoryFormData>(
      context: context,
      builder: (_) => _CategoryFormDialog(category: category),
    );

    if (formData == null || !context.mounted) return;

    final input = Category(
      id: category?.id ?? '',
      name: formData.name,
      imageUrl: formData.imageUrl,
    );

    try {
      if (category == null) {
        await ref.read(addCategoryProvider)(input);
        if (!context.mounted) return;
        _showMessage(context, CategoryManagementText.addSuccess);
      } else {
        await ref.read(updateCategoryProvider)(input);
        if (!context.mounted) return;
        _showMessage(context, CategoryManagementText.updateSuccess);
      }
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, CategoryManagementText.saveError);
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
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(CategoryManagementText.delete),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(deleteCategoryProvider)(category.id);
      if (!context.mounted) return;
      _showMessage(context, CategoryManagementText.deleteSuccess);
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, CategoryManagementText.deleteError);
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  final Category category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: _CategoryImage(imageUrl: category.imageUrl),
        title: Text(
          category.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          category.id,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: CategoryManagementText.editCategory,
              onPressed: onEdit,
              icon: const Icon(Icons.edit),
            ),
            IconButton(
              tooltip: CategoryManagementText.deleteCategory,
              onPressed: onDelete,
              icon: const Icon(Icons.delete, color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryImage extends StatelessWidget {
  const _CategoryImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.category, color: Colors.green.shade700),
    );

    if (imageUrl.trim().isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
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
  final formKey = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late final TextEditingController imageUrlController;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.category?.name ?? '');
    imageUrlController = TextEditingController(
      text: widget.category?.imageUrl ?? '',
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    imageUrlController.dispose();
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
        width: 420,
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TextFormInput(
                controller: nameController,
                label: CategoryManagementText.nameLabel,
                validator: _requiredText,
              ),
              const SizedBox(height: 12),
              _TextFormInput(
                controller: imageUrlController,
                label: CategoryManagementText.imageUrlLabel,
                keyboardType: TextInputType.url,
                validator: _imageUrlValidator,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(CategoryManagementText.cancel),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text(CategoryManagementText.save),
        ),
      ],
    );
  }

  void _submit() {
    if (!formKey.currentState!.validate()) return;

    Navigator.pop(
      context,
      _CategoryFormData(
        name: nameController.text.trim(),
        imageUrl: imageUrlController.text.trim(),
      ),
    );
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return CategoryManagementText.requiredField;
    }
    return null;
  }

  String? _imageUrlValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return CategoryManagementText.invalidImageUrl;
    }

    return null;
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

class _CategoryFormData {
  const _CategoryFormData({
    required this.name,
    required this.imageUrl,
  });

  final String name;
  final String imageUrl;
}

class CategoryManagementText {
  const CategoryManagementText._();

  static const title = 'Manage Categories';
  static const adminAccessRequired = 'Admin access required';
  static const addCategory = 'Add Category';
  static const editCategory = 'Edit Category';
  static const deleteCategory = 'Delete Category';
  static const emptyState = 'No categories added';
  static const loadError = 'Unable to load categories';
  static const saveError = 'Unable to save category';
  static const deleteError = 'Unable to delete category';
  static const addSuccess = 'Category added';
  static const updateSuccess = 'Category updated';
  static const deleteSuccess = 'Category deleted';
  static const deletePrompt = 'Delete';
  static const nameLabel = 'Name';
  static const imageUrlLabel = 'Image URL';
  static const cancel = 'Cancel';
  static const save = 'Save';
  static const delete = 'Delete';
  static const requiredField = 'Required';
  static const invalidImageUrl = 'Enter a valid image URL';
}
