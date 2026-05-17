import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error_handler.dart';
import '../../domain/entities/customer_order.dart';
import '../providers/order_providers.dart';
import '../widgets/app_state_widgets.dart';

class OrderDetailsScreen extends ConsumerWidget {
  const OrderDetailsScreen({
    super.key,
    required this.orderId,
  });

  final String orderId;

  int getStepIndex(String status) {
    final index = OrderStatus.values.indexOf(OrderStatus.normalize(status));
    return index < 0 ? 0 : index;
  }

  Widget buildTrackingUI(String status) {
    final currentStep = getStepIndex(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Order Tracking',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(OrderStatus.values.length, (index) {
            final isActive = index <= currentStep;

            return Expanded(
              child: Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.green : Colors.grey.shade300,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check,
                      size: 18,
                      color: isActive ? Colors.white : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    OrderStatus.values[index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: isActive ? Colors.black : Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderDetailsProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Order Details')),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const Center(child: Text('Order not found'));
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildTrackingUI(order.status),
                const SizedBox(height: 20),
                if (order.createdAt != null)
                  Text(
                    'Date: ${order.createdAt!.toString().substring(0, 16)}',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                const SizedBox(height: 10),
                const Text(
                  'Items',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: order.items.isEmpty
                      ? const Center(child: Text('No items in this order'))
                      : ListView.builder(
                          itemCount: order.items.length,
                          itemBuilder: (context, index) {
                            final item = order.items[index];

                            return Card(
                              child: ListTile(
                                title: Text(item.name),
                                subtitle: Text(
                                  '\u20B9${_formatPrice(item.price)} x ${item.quantity}',
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const Divider(),
                const SizedBox(height: 10),
                Text(
                  'Total: \u20B9${_formatPrice(order.total)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const AppLoadingState(),
        error: (error, _) => AppRetryState(
          icon: Icons.error_outline_rounded,
          title: 'Unable to load order',
          message: AppErrorHandler.messageFor(
            error,
            fallback: 'Please try again in a moment.',
          ),
          onRetry: () => ref.invalidate(orderDetailsProvider(orderId)),
        ),
      ),
    );
  }

  String _formatPrice(double price) {
    return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
  }
}
