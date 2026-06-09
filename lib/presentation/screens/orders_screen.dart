import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error_handler.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/customer_order.dart';
import '../providers/auth_providers.dart';
import '../providers/order_providers.dart';
import '../widgets/app_state_widgets.dart';
import 'order_details_screen.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(OrdersText.title)),
        body: const Center(child: Text(OrdersText.loginRequired)),
      );
    }

    final ordersAsync = ref.watch(userOrderListProvider(session.uid));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text(OrdersText.title)),
      body: ordersAsync.when(
        data: (state) {
          final orders = state.orders;
          if (orders.isEmpty) {
            return const _EmptyOrders();
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: orders.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              if (index >= orders.length) {
                return _OrderListFooter(
                  isLoading: state.isLoadingMore,
                  hasMore: state.hasMore,
                  onLoadMore: () => _loadMore(
                    context: context,
                    ref: ref,
                    userId: session.uid,
                  ),
                );
              }

              final order = orders[index];

              return _OrderCard(
                order: order,
                displayNumber: orders.length - index,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderDetailsScreen(orderId: order.id),
                    ),
                  );
                },
              );
            },
          );
        },
        loading: () => const AppLoadingState(),
        error: (error, _) => AppRetryState(
          icon: Icons.error_outline_rounded,
          title: OrdersText.loadError,
          message: AppErrorHandler.messageFor(
            error,
            fallback: OrdersText.loadErrorSubtitle,
          ),
          onRetry: () {
            ref.read(userOrderListProvider(session.uid).notifier).loadInitial();
          },
        ),
      ),
    );
  }

  static Future<void> _loadMore({
    required BuildContext context,
    required WidgetRef ref,
    required String userId,
  }) async {
    try {
      await ref.read(userOrderListProvider(userId).notifier).loadNext();
    } catch (error) {
      if (!context.mounted) return;

      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: OrdersText.loadErrorSubtitle,
      );
    }
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.displayNumber,
    required this.onTap,
  });

  final CustomerOrder order;
  final int displayNumber;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = OrderStatus.normalize(order.status);
    final statusColor = _statusColor(normalizedStatus);
    final distinctItemCount = order.items.length;
    final itemText = distinctItemCount == 1 ? 'Item' : 'Items';
    final distinctItemSummary = '$distinctItemCount $itemText';
    final itemNames = order.items.map((item) => '${item.name} x${item.quantity}').join(', ');

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('orders')
                          .doc(order.id)
                          .snapshots(),
                      builder: (context, snapshot) {
                        final docData = snapshot.data?.data();
                        final serverOrderId = docData?['orderId'] as String?;
                        final serverStatus = docData?['status'] as String? ?? order.status;

                        final isGK = (serverOrderId != null && serverOrderId.startsWith('GK')) ||
                                     (order.orderId != null && order.orderId!.startsWith('GK'));

                        if (!isGK) {
                          if (serverStatus == 'Failed') {
                            return const Text(
                              'Validation Failed',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.danger,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            );
                          }

                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Row(
                              children: [
                                Text(
                                  'Order #',
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(width: 6),
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            );
                          }

                          return const Text(
                            'Order Not Created',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.mutedText,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          );
                        }

                        final displayVal = (serverOrderId != null && serverOrderId.startsWith('GK'))
                            ? serverOrderId
                            : (order.orderId != null && order.orderId!.startsWith('GK') ? order.orderId! : '');

                        return Text(
                          'Order #$displayVal',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(
                    status: normalizedStatus,
                    color: statusColor,
                  ),
                ],
              ),
              if (order.createdAt != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      color: AppColors.mutedText,
                      size: 13,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Placed on ${_formatDate(order.createdAt!)}',
                      style: const TextStyle(
                        color: AppColors.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
              if (itemNames.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  itemNames,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Billing Amount',
                          style: TextStyle(
                            color: AppColors.mutedText,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '\u20B9${_formatPrice(order.total)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.softGreen,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      distinctItemSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.status,
    required this.color,
  });

  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 9,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case OrderStatus.placed:
      case OrderStatus.confirmed:
        return Icons.check_circle_rounded;
      case OrderStatus.packed:
        return Icons.inventory_2_rounded;
      case OrderStatus.outForDelivery:
      case OrderStatus.shipped:
        return Icons.local_shipping_rounded;
      case OrderStatus.delivered:
        return Icons.task_alt_rounded;
      case OrderStatus.cancelled:
        return Icons.cancel_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) {
    return const _ScreenState(
      icon: Icons.receipt_long_outlined,
      title: OrdersText.emptyTitle,
      subtitle: OrdersText.emptySubtitle,
    );
  }
}

class _OrderListFooter extends StatelessWidget {
  const _OrderListFooter({
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
            OrdersText.endOfList,
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
        label: const Text(OrdersText.loadMore),
      ),
    );
  }
}

class _ScreenState extends StatelessWidget {
  const _ScreenState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
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
              child: Icon(icon, color: AppColors.primary, size: 34),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.mutedText,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (OrderStatus.normalize(status)) {
    case OrderStatus.placed:
      return OrdersColors.placed;
    case OrderStatus.confirmed:
      return OrdersColors.placed;
    case OrderStatus.packed:
      return OrdersColors.packed;
    case OrderStatus.outForDelivery:
      return OrdersColors.outForDelivery;
    case OrderStatus.delivered:
      return OrdersColors.delivered;
    case OrderStatus.cancelled:
      return AppColors.danger;
    default:
      return AppColors.mutedText;
  }
}

String _formatPrice(double price) {
  return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
}

String _formatDate(DateTime date) {
  final localDate = date.toLocal();
  final day = localDate.day.toString().padLeft(2, '0');
  final month = localDate.month.toString().padLeft(2, '0');
  final hour = localDate.hour.toString().padLeft(2, '0');
  final minute = localDate.minute.toString().padLeft(2, '0');

  return '$day/$month/${localDate.year}  $hour:$minute';
}

class OrdersColors {
  const OrdersColors._();

  static const placed = AppColors.warning;
  static const packed = AppColors.info;
  static const outForDelivery = AppColors.accent;
  static const delivered = AppColors.success;
}

class OrdersConfig {
  const OrdersConfig._();

  static const itemImageCacheExtent = 130;
  static const itemImageDiskCacheExtent = 180;
}

class OrdersText {
  const OrdersText._();

  static const title = 'My Orders';
  static const loginRequired = 'Please login to view your orders';
  static const emptyTitle = 'No orders yet';
  static const emptySubtitle = 'Your completed checkouts will appear here.';
  static const loadError = 'Unable to load orders';
  static const loadErrorSubtitle = 'Please try again in a moment.';
  static const loadMore = 'Load more';
  static const endOfList = 'All loaded orders are visible';
  static const orderPrefix = 'Order #';
  static const total = 'Total';
  static const items = 'Items';
  static const payment = 'Payment';
  static const orderStatus = 'Order status';
  static const noItems = 'No products in this order';
  static const notAvailable = 'NA';
}
