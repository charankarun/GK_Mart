import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/order.dart';
import '../../providers/auth_providers.dart';
import '../../providers/order_providers.dart';

class AdminOrdersScreen extends ConsumerWidget {
  const AdminOrdersScreen({super.key});

  String _errorMessage(Object? error) {
    final message = error?.toString() ?? '';

    if (message.contains('permission-denied')) {
      return "You don't have permission to view orders";
    }

    if (message.contains('failed-precondition') ||
        message.toLowerCase().contains('index')) {
      return 'Orders need a Firestore index. Check debug console.';
    }

    return 'Unable to load orders';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdminAsync = ref.watch(isAdminProvider);
    final isAdmin = isAdminAsync.maybeWhen(
      data: (value) => value,
      orElse: () => false,
    );

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Orders')),
        body: Center(
          child: isAdminAsync.isLoading
              ? const CircularProgressIndicator()
              : const Text('Admin access required'),
        ),
      );
    }

    final ordersAsync = ref.watch(ordersStreamProvider);
    final pendingStatusUpdates = ref.watch(orderStatusUpdateControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Orders')),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No orders yet'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final order = orders[index];
              final effectiveStatus = pendingStatusUpdates[order.id] ??
                  OrderStatus.normalize(order.status);
              final isUpdating = pendingStatusUpdates.containsKey(order.id);

              return _AdminOrderCard(
                order: order,
                effectiveStatus: effectiveStatus,
                isUpdating: isUpdating,
                onStatusChanged: (status) async {
                  try {
                    await ref
                        .read(orderStatusUpdateControllerProvider.notifier)
                        .updateOrderStatus(
                          orderId: order.id,
                          status: status,
                        );
                  } catch (_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Unable to update order status'),
                      ),
                    );
                  }
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(_errorMessage(error))),
      ),
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({
    required this.order,
    required this.effectiveStatus,
    required this.isUpdating,
    required this.onStatusChanged,
  });

  final Order order;
  final String effectiveStatus;
  final bool isUpdating;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final statusStyle = _OrderStatusStyle.resolve(effectiveStatus);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _OrderTextBlock(
                    label: 'Order ID',
                    value: order.id,
                    monospaceValue: true,
                  ),
                ),
                const SizedBox(width: 12),
                _StatusChip(
                  label: effectiveStatus,
                  style: statusStyle,
                  isUpdating: isUpdating,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _OrderTextBlock(
              label: 'Customer',
              value: order.customerDisplayName,
            ),
            const SizedBox(height: 10),
            _OrderTextBlock(
              label: 'Items',
              value: _itemsSummary(order),
            ),
            const SizedBox(height: 10),
            _OrderTextBlock(
              label: 'Address',
              value: order.address,
              maxLines: 3,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _OrderTextBlock(
                    label: 'Total',
                    value: '\u20B9${_formatPrice(order.total)}',
                    emphasizeValue: true,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('status-${order.id}-$effectiveStatus'),
                    initialValue: effectiveStatus,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: OrderStatus.values.map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(status),
                      );
                    }).toList(),
                    onChanged: isUpdating
                        ? null
                        : (status) {
                            if (status == null || status == effectiveStatus) {
                              return;
                            }
                            onStatusChanged(status);
                          },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _itemsSummary(Order order) {
    if (order.items.isEmpty) return 'No items';

    final visibleItems = order.items.take(3).map(_itemSummary).join(', ');
    final remainingCount = order.items.length - 3;

    if (remainingCount <= 0) return visibleItems;
    return '$visibleItems, + $remainingCount more';
  }

  String _itemSummary(OrderItem item) {
    final unit = item.unit.trim();
    final quantity =
        unit.isEmpty ? '${item.quantity}' : '${item.quantity} $unit';

    return '${item.name} x $quantity';
  }

  String _formatPrice(double price) {
    return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
  }
}

class _OrderTextBlock extends StatelessWidget {
  const _OrderTextBlock({
    required this.label,
    required this.value,
    this.maxLines = 2,
    this.emphasizeValue = false,
    this.monospaceValue = false,
  });

  final String label;
  final String value;
  final int maxLines;
  final bool emphasizeValue;
  final bool monospaceValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: monospaceValue ? 'monospace' : null,
            fontWeight: emphasizeValue ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.style,
    required this.isUpdating,
  });

  final String label;
  final _OrderStatusStyle style;
  final bool isUpdating;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isUpdating) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: style.foreground,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: style.foreground,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderStatusStyle {
  const _OrderStatusStyle({
    required this.foreground,
    required this.background,
  });

  final Color foreground;
  final Color background;

  static _OrderStatusStyle resolve(String status) {
    switch (OrderStatus.normalize(status)) {
      case OrderStatus.placed:
        return _OrderStatusStyle(
          foreground: Colors.orange.shade800,
          background: Colors.orange.shade50,
        );
      case OrderStatus.packed:
        return _OrderStatusStyle(
          foreground: Colors.blue.shade800,
          background: Colors.blue.shade50,
        );
      case OrderStatus.outForDelivery:
        return _OrderStatusStyle(
          foreground: Colors.purple.shade800,
          background: Colors.purple.shade50,
        );
      case OrderStatus.delivered:
        return _OrderStatusStyle(
          foreground: Colors.green.shade800,
          background: Colors.green.shade50,
        );
    }

    return _OrderStatusStyle(
      foreground: Colors.grey.shade800,
      background: Colors.grey.shade100,
    );
  }
}
