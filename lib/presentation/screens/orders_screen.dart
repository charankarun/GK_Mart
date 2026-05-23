import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error_handler.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/customer_order.dart';
import '../providers/auth_providers.dart';
import '../providers/order_providers.dart';
import '../widgets/app_cached_network_image.dart';
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
    final totalQuantity = order.items.fold<int>(
      0,
      (total, item) => total + item.quantity,
    );

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
            boxShadow: AppShadows.card,
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OrderProductImages(items: order.items),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                '${OrdersText.orderPrefix}$displayNumber',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusPill(
                              status: normalizedStatus,
                              color: statusColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _formatOrderItems(order.items),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.text,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (order.createdAt != null)
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                color: AppColors.mutedText,
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  _formatDate(order.createdAt!),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.mutedText,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _StatusSummary(status: normalizedStatus, color: statusColor),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: AppColors.border),
              ),
              Row(
                children: [
                  Expanded(
                    child: _SummaryChip(
                      label: OrdersText.total,
                      value: '\u20B9${_formatPrice(order.total)}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummaryChip(
                      label: OrdersText.items,
                      value: '$totalQuantity',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummaryChip(
                      label: OrdersText.payment,
                      value: order.paymentMethod,
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

class _OrderProductImages extends StatelessWidget {
  const _OrderProductImages({required this.items});

  final List<OrderItem> items;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(3).toList();
    final overflowCount = items.length - visibleItems.length;

    if (visibleItems.isEmpty) {
      return const _OrderImageBox(imageUrl: '');
    }

    return SizedBox(
      width: 92,
      height: 84,
      child: Stack(
        children: [
          for (var index = 0; index < visibleItems.length; index += 1)
            Positioned(
              left: index * 12,
              top: index * 7,
              child: _OrderImageBox(imageUrl: visibleItems[index].imageUrl),
            ),
          if (overflowCount > 0)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.text.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  border: Border.all(color: AppColors.card, width: 2),
                ),
                child: Text(
                  '+$overflowCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderImageBox extends StatelessWidget {
  const _OrderImageBox({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = imageUrl.trim();

    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.card, width: 2),
        boxShadow: AppShadows.soft,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: AppCachedNetworkImage(
          imageUrl: trimmedUrl,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          memCacheWidth: OrdersConfig.itemImageCacheExtent,
          memCacheHeight: OrdersConfig.itemImageCacheExtent,
          maxWidthDiskCache: OrdersConfig.itemImageDiskCacheExtent,
          maxHeightDiskCache: OrdersConfig.itemImageDiskCacheExtent,
          placeholder: const _OrderImagePlaceholder(),
          errorPlaceholder: const _OrderImagePlaceholder(),
        ),
      ),
    );
  }
}

class _OrderImagePlaceholder extends StatelessWidget {
  const _OrderImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const AppImagePlaceholder(iconSize: 26);
  }
}

class _StatusSummary extends StatelessWidget {
  const _StatusSummary({
    required this.status,
    required this.color,
  });

  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.local_shipping_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          const Text(
            OrdersText.orderStatus,
            style: TextStyle(
              color: AppColors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.mutedText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.trim().isEmpty ? OrdersText.notAvailable : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
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
    case OrderStatus.packed:
      return OrdersColors.packed;
    case OrderStatus.outForDelivery:
      return OrdersColors.outForDelivery;
    case OrderStatus.delivered:
      return OrdersColors.delivered;
    default:
      return AppColors.mutedText;
  }
}

String _formatOrderItems(List<OrderItem> items) {
  if (items.isEmpty) return OrdersText.noItems;

  final visibleItems = items.take(2).map((item) {
    return '${item.name} x ${item.quantity}';
  }).join(', ');

  if (items.length <= 2) return visibleItems;
  return '$visibleItems + ${items.length - 2} more';
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
