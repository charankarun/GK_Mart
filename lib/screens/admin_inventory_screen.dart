import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../admin_access.dart';

class AdminInventoryScreen extends StatefulWidget {
  const AdminInventoryScreen({super.key});

  @override
  State<AdminInventoryScreen> createState() => _AdminInventoryScreenState();
}

class _AdminInventoryScreenState extends State<AdminInventoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabController;

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  String _readString(Map<String, dynamic> data, String key,
      {String fallback = ''}) {
    final value = data[key]?.toString().trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  double _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _showProductDialog({
    QueryDocumentSnapshot<Map<String, dynamic>>? product,
  }) async {
    final data = product?.data() ?? <String, dynamic>{};
    final nameController = TextEditingController(
      text: _readString(data, 'name'),
    );
    final priceController = TextEditingController(
      text: data['price']?.toString() ?? '',
    );
    final unitController = TextEditingController(
      text: _readString(data, 'unit'),
    );
    final categoryController = TextEditingController(
      text: _readString(data, 'category'),
    );
    final imageController = TextEditingController(
      text: _readString(data, 'image'),
    );
    bool outOfStock = data['outOfStock'] == true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(product == null ? "Add Product" : "Edit Product"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field(nameController, "Product Name"),
                    const SizedBox(height: 10),
                    _field(
                      priceController,
                      "Price",
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 10),
                    _field(unitController, "Unit"),
                    const SizedBox(height: 10),
                    _field(categoryController, "Category"),
                    const SizedBox(height: 10),
                    _field(imageController, "Image URL"),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Out of stock"),
                      value: outOfStock,
                      onChanged: (value) {
                        setDialogState(() => outOfStock = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final price = double.tryParse(priceController.text.trim());

                    if (name.isEmpty || price == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Product name and price are required"),
                        ),
                      );
                      return;
                    }

                    final payload = {
                      'name': name,
                      'price': price,
                      'unit': unitController.text.trim(),
                      'category': categoryController.text.trim(),
                      'image': imageController.text.trim(),
                      'outOfStock': outOfStock,
                      'updatedAt': FieldValue.serverTimestamp(),
                    };

                    if (product == null) {
                      payload['createdAt'] = FieldValue.serverTimestamp();
                      await FirebaseFirestore.instance
                          .collection('products')
                          .add(payload);
                    } else {
                      await product.reference.set(payload, SetOptions(merge: true));
                    }

                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    priceController.dispose();
    unitController.dispose();
    categoryController.dispose();
    imageController.dispose();
  }

  Future<void> _showCategoryDialog() async {
    final nameController = TextEditingController();
    final imageController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Add Category"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(nameController, "Category Name"),
              const SizedBox(height: 10),
              _field(imageController, "Image URL"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Category name is required")),
                  );
                  return;
                }

                await FirebaseFirestore.instance.collection('categories').add({
                  'name': name,
                  'image': imageController.text.trim(),
                  'createdAt': FieldValue.serverTimestamp(),
                });

                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    imageController.dispose();
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Future<void> _deleteDocument(
    DocumentReference reference,
    String message,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Confirm Delete"),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await reference.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isAdminUser()) {
      return Scaffold(
        appBar: AppBar(title: const Text("Manage Products")),
        body: const Center(child: Text("Admin access required")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Products"),
        bottom: TabBar(
          controller: tabController,
          tabs: const [
            Tab(text: "Products"),
            Tab(text: "Categories"),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (tabController.index == 0) {
            _showProductDialog();
          } else {
            _showCategoryDialog();
          }
        },
        child: const Icon(Icons.add),
      ),
      body: TabBarView(
        controller: tabController,
        children: [
          _productsTab(),
          _categoriesTab(),
        ],
      ),
    );
  }

  Widget _productsTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('products')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text("Unable to load products"));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final products = snapshot.data!.docs;
        if (products.isEmpty) {
          return const Center(child: Text("No products added"));
        }

        return ListView.builder(
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            final data = product.data();
            final name = _readString(data, 'name', fallback: 'Product');
            final category = _readString(data, 'category');
            final unit = _readString(data, 'unit');
            final price = _readDouble(data['price']);
            final imageUrl = _readString(data, 'image');
            final outOfStock = data['outOfStock'] == true;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.image, size: 36);
                        },
                      )
                    : const Icon(Icons.image, size: 36),
                title: Text(name),
                subtitle: Text(
                  "\u20B9$price"
                  "${unit.isNotEmpty ? " • $unit" : ""}"
                  "${category.isNotEmpty ? " • $category" : ""}",
                ),
                trailing: Wrap(
                  spacing: 2,
                  children: [
                    Switch(
                      value: outOfStock,
                      onChanged: (value) {
                        product.reference.set({
                          'outOfStock': value,
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showProductDialog(product: product),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        _deleteDocument(
                          product.reference,
                          "Delete $name from products?",
                        );
                      },
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

  Widget _categoriesTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('categories')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text("Unable to load categories"));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final categories = snapshot.data!.docs;
        if (categories.isEmpty) {
          return const Center(child: Text("No categories added"));
        }

        return ListView.builder(
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            final data = category.data();
            final name = _readString(data, 'name', fallback: 'Category');
            final imageUrl = _readString(data, 'image');

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: imageUrl.isNotEmpty
                    ? CircleAvatar(backgroundImage: NetworkImage(imageUrl))
                    : const CircleAvatar(child: Icon(Icons.category)),
                title: Text(name),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    _deleteDocument(
                      category.reference,
                      "Delete $name from categories?",
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
