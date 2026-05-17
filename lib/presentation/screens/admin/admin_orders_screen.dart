import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error_handler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/order.dart';
import '../../providers/auth_providers.dart';
import '../../providers/order_providers.dart';
import '../../widgets/app_state_widgets.dart';

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

    final ordersAsync = ref.watch(adminOrderListProvider);
    final pendingStatusUpdates = ref.watch(orderStatusUpdateControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Admin Orders')),
      body: ordersAsync.when(
        data: (state) {
          final orders = state.orders;
          if (orders.isEmpty) {
            return const _AdminOrdersEmptyState();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index >= orders.length) {
                return _AdminOrderListFooter(
                  isLoading: state.isLoadingMore,
                  hasMore: state.hasMore,
                  onLoadMore: () => _loadMore(context, ref),
                );
              }

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
                    ref.read(adminOrderListProvider.notifier).loadInitial();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(AdminOrdersText.statusUpdateSuccess),
                      ),
                    );
                  } catch (error) {
                    if (!context.mounted) return;

                    AppErrorHandler.showErrorSnackBar(
                      context,
                      error,
                      fallbackMessage: 'Unable to update order status',
                    );
                  }
                },
              );
            },
          );
        },
        loading: () => const AppLoadingState(),
        error: (error, _) => AppRetryState(
          icon: Icons.error_outline_rounded,
          title: _errorMessage(error),
          message: AppErrorHandler.messageFor(
            error,
            fallback: 'Please try again in a moment.',
          ),
          onRetry: () {
            ref.read(adminOrderListProvider.notifier).loadInitial();
          },
        ),
      ),
    );
  }

  Future<void> _loadMore(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(adminOrderListProvider.notifier).loadNext();
    } catch (error) {
      if (!context.mounted) return;

      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: 'Unable to load more orders',
      );
    }
  }
}

class AdminOrdersText {
  const AdminOrdersText._();

  static const statusUpdateSuccess = 'Order status updated';
}

class _AdminOrdersEmptyState extends StatelessWidget {
  const _AdminOrdersEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No orders yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.mutedText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AdminOrderListFooter extends StatelessWidget {
  const _AdminOrderListFooter({
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
            'All loaded orders are visible',
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
        label: const Text('Load more'),
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

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _OrderIdBlock(orderId: order.id),
                ),
                const SizedBox(width: 12),
                _StatusChip(
                  label: effectiveStatus,
                  style: statusStyle,
                  isUpdating: isUpdating,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _InfoGrid(
              entries: [
                _InfoEntry(
                  label: 'Customer name',
                  value: order.customerDisplayName,
                  icon: Icons.person_outline_rounded,
                ),
                _InfoEntry(
                  label: 'Customer phone',
                  value: _fallback(order.phone, 'Phone not available'),
                  icon: Icons.phone_outlined,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoBlock(
              label: 'Delivery address',
              value: _fallback(order.address, 'No delivery address added'),
              icon: Icons.location_on_outlined,
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            _InfoBlock(
              label: 'Order summary',
              value: _itemsSummary(order),
              icon: Icons.shopping_bag_outlined,
              maxLines: 3,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1, color: AppColors.border),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final useWideLayout = constraints.maxWidth >= 560;

                final totalBlock = _InfoBlock(
                  label: 'Total',
                  value: '\u20B9${_formatPrice(order.total)}',
                  icon: Icons.payments_outlined,
                  emphasizeValue: true,
                );
                final dropdown = DropdownButtonFormField<String>(
                  key: ValueKey('status-${order.id}-$effectiveStatus'),
                  initialValue: effectiveStatus,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Update Order',
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
                );

                if (!useWideLayout) {
                  return Column(
                    children: [
                      totalBlock,
                      const SizedBox(height: 12),
                      dropdown,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: totalBlock),
                    const SizedBox(width: 12),
                    SizedBox(width: 210, child: dropdown),
                  ],
                );
              },
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

  String _fallback(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String _formatPrice(double price) {
    return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
  }
}

class _OrderIdBlock extends StatelessWidget {
  const _OrderIdBlock({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final visibleId = orderId.trim().isEmpty ? 'Unknown order' : orderId.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order ID',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            visibleId,
            maxLines: 2,
            style: const TextStyle(
              color: AppColors.text,
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.entries});

  final List<_InfoEntry> entries;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 520;
        final itemWidth = useTwoColumns
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final entry in entries)
              SizedBox(
                width: itemWidth,
                child: _InfoBlock(
                  label: entry.label,
                  value: entry.value,
                  icon: entry.icon,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InfoEntry {
  const _InfoEntry({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.label,
    required this.value,
    required this.icon,
    this.maxLines = 2,
    this.emphasizeValue = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final int maxLines;
  final bool emphasizeValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    height: 1.25,
                    fontWeight:
                        emphasizeValue ? FontWeight.w900 : FontWeight.w700,
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
          foreground: AppColors.accent,
          background: AppColors.softOrange,
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
          foreground: AppColors.primary,
          background: AppColors.softGreen,
        );
    }

    return _OrderStatusStyle(
      foreground: Colors.grey.shade800,
      background: Colors.grey.shade100,
    );
  }
}
