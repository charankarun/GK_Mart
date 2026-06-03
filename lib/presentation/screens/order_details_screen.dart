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

  Widget buildTrackingUI(String status) {
    final normalized = OrderStatus.normalize(status);
    final bool isCancelled = normalized == OrderStatus.cancelled;
    final List<String> steps = isCancelled
        ? [OrderStatus.placed, OrderStatus.cancelled]
        : [
            OrderStatus.placed,
            OrderStatus.confirmed,
            OrderStatus.packed,
            OrderStatus.shipped,
            OrderStatus.outForDelivery,
            OrderStatus.delivered,
          ];
    final currentStep = steps.indexOf(normalized);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Order Tracking',
          style: TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE1E8DE)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(steps.length, (index) {
                final stepName = steps[index];
                final isCompleted = index < currentStep;
                final isCurrent = index == currentStep;
                final isPending = index > currentStep;

                Color stepColor;
                if (isCancelled && stepName == OrderStatus.cancelled) {
                  stepColor = const Color(0xFFDC2626);
                } else if (isCompleted) {
                  stepColor = const Color(0xFF16A34A);
                } else if (isCurrent) {
                  stepColor = const Color(0xFF2E7D32);
                } else {
                  stepColor = const Color(0xFF9CA3AF);
                }

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 100,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              if (isCurrent)
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: stepColor.withValues(alpha: 0.16),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: stepColor.withValues(alpha: 0.4),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: isPending ? Colors.white : stepColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: stepColor,
                                    width: isPending ? 2.5 : 0,
                                  ),
                                ),
                                child: Icon(
                                  isCompleted
                                      ? Icons.check_rounded
                                      : (isCurrent
                                          ? (isCancelled
                                              ? Icons.close_rounded
                                              : Icons.radio_button_checked_rounded)
                                          : Icons.radio_button_off_rounded),
                                  size: 14,
                                  color: isPending
                                      ? const Color(0xFF9CA3AF)
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            stepName,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700,
                              color: isCurrent
                                  ? const Color(0xFF111827)
                                  : const Color(0xFF5F6B62),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (index < steps.length - 1)
                      Container(
                        width: 40,
                        height: 3,
                        margin: const EdgeInsets.only(top: 17),
                        decoration: BoxDecoration(
                          color: index < currentStep
                              ? (isCancelled ? const Color(0xFFDC2626) : const Color(0xFF16A34A))
                              : const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ),
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
