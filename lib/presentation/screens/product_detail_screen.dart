import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/cart_item.dart';
import '../../domain/entities/product.dart';
import '../providers/auth_providers.dart';
import '../providers/commerce_providers.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({
    super.key,
    required this.product,
  });

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: Text(product.name)),
        body: const Center(child: Text('Please login to add products')),
      );
    }

    final cartItems = ref.watch(cartItemsProvider);
    CartItem? cartItem;
    for (final item in cartItems) {
      if (item.productId == product.id) {
        cartItem = item;
        break;
      }
    }
    final quantity = cartItem?.quantity ?? 0;
    final cartController = ref.read(cartControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(product.name)),
      body: Column(
        children: [
          Container(
            height: 250,
            width: double.infinity,
            color: Colors.grey[200],
            child: product.imageUrl.isNotEmpty
                ? Image.network(product.imageUrl, fit: BoxFit.cover)
                : const Icon(Icons.image, size: 100),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '\u20B9${_formatPrice(product.sellingPrice)}',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Color(0xFF6C63FF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.unit,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Fresh and high quality product. Delivered fast to your home.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const Spacer(),
                  if (quantity > 0)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: () {
                            cartController.decrement(product.id);
                          },
                        ),
                        Text(
                          '$quantity',
                          style: const TextStyle(fontSize: 16),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            cartController.increment(product.id);
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: !product.isAvailable
                  ? null
                  : () {
                      cartController.addProduct(product);
                    },
              child: Text(
                !product.isAvailable
                    ? 'Out of Stock'
                    : quantity == 0
                        ? 'Add to Cart'
                        : 'Add More',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrice(double price) {
    return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
  }
}
