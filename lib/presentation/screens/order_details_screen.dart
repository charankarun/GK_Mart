// ==============================================================================
// FILE: lib/presentation/screens/order_details_screen.dart
// PURPOSE: Screen displaying a detailed breakdown of a single customer order.
// LAYER: Presentation / Views (Screens)
// DEPENDENCIES: orderDetailsProvider, OrderRepository
//
// ARCHITECTURAL ROLE:
// Listens to real-time streams of individual order documents. Builds tracking UI
// stepper indicators based on the order status, displays ordered catalog item lists,
// and allows clients to request order cancellations if status is Placed/Confirmed/Packed.
//
// Order Details Screen Responsibilities:
// - Display a progress stepper matching Placed/Confirmed/Packed/Shipped/Out for Delivery/Delivered/Cancelled.
// - Stream order changes dynamically.
// - Expose cancel interfaces for authorized user order states.
// ==============================================================================

import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error_handler.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/customer_order.dart';
import '../providers/order_providers.dart';
import '../providers/repository_providers.dart';
import '../widgets/app_cached_network_image.dart';
import '../widgets/app_state_widgets.dart';

/// Screen displaying tracking timelines and items for a specific order.
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
                const SizedBox(height: 16),
                const Text(
                  'Delivery Address',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    order.address.trim().isNotEmpty ? order.address.trim() : 'No delivery address added',
                    if (order.pincode.trim().isNotEmpty) 'Pincode: ${order.pincode.trim()}',
                  ].join('\n'),
                  style: const TextStyle(
                    fontSize: 14, 
                    color: Color(0xFF374151), 
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
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
                            return _OrderDetailItemRow(item: item);
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
                if (OrderStatus.normalize(order.status) == OrderStatus.placed ||
                    OrderStatus.normalize(order.status) == OrderStatus.confirmed ||
                    OrderStatus.normalize(order.status) == OrderStatus.packed) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        developer.log('Cancel button clicked', name: 'OrderCancelTrace');
                        _showCancelConfirmation(context, ref, order);
                      },
                      child: const Text(
                        'Cancel Order',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
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

  void _showCancelConfirmation(BuildContext context, WidgetRef ref, Order order) {
    developer.log('OrderDetailsScreen: _showCancelConfirmation dialog triggered for order: ${order.id}', name: 'OrderCancelTrace');
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cancel this order?'),
          actions: [
            TextButton(
              onPressed: () {
                developer.log('OrderDetailsScreen: Confirmation dialog dismissed with No', name: 'OrderCancelTrace');
                Navigator.pop(context);
              },
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () async {
                developer.log('Dialog confirmed', name: 'OrderCancelTrace');
                Navigator.pop(context);
                _cancelOrder(context, ref, order);
              },
              child: const Text(
                'Yes, Cancel Order',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _cancelOrder(BuildContext context, WidgetRef ref, Order order) async {
    developer.log('Controller called', name: 'OrderCancelTrace');
    developer.log('Repository called', name: 'OrderCancelTrace');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cancelling order...')),
    );

    try {
      developer.log('Firestore update started', name: 'OrderCancelTrace');
      await ref.read(orderRepositoryProvider).cancelOrder(
            orderId: order.id,
            userId: order.userId,
          );
      developer.log('Firestore update succeeded', name: 'OrderCancelTrace');
      
      developer.log('UI refresh started', name: 'OrderCancelTrace');
      ref.invalidate(userOrderListProvider(order.userId));
      ref.invalidate(adminOrderListProvider);
      ref.invalidate(dashboardRecentOrdersProvider);
      ref.invalidate(orderDetailsProvider(order.id));
      
      if (context.mounted) {
        developer.log('OrderDetailsScreen: Showing success SnackBar', name: 'OrderCancelTrace');
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order Cancelled Successfully')),
        );
      }
    } catch (e, stackTrace) {
      developer.log('Firestore update failed', name: 'OrderCancelTrace', error: e, stackTrace: stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        AppErrorHandler.showErrorSnackBar(
          context,
          e,
          fallbackMessage: 'Failed to cancel order.',
        );
      }
    }
  }
}

class _OrderDetailItemRow extends StatelessWidget {
  const _OrderDetailItemRow({required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = item.imageUrl.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: AppCachedNetworkImage(
                imageUrl: trimmedUrl,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                placeholder: const AppImagePlaceholder(iconSize: 22),
                errorPlaceholder: const AppImagePlaceholder(iconSize: 22),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\u20B9${_formatPrice(item.effectivePrice)}${item.unit.isNotEmpty ? " / ${item.unit}" : ""}',
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Qty: ${item.quantity}',
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '\u20B9${_formatPrice(item.lineTotal)}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatPrice(double price) {
    return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
  }
}
