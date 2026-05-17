import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error_handler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/order_analytics.dart';
import '../../providers/auth_providers.dart';
import '../../providers/order_providers.dart';
import '../../widgets/app_state_widgets.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdminAsync = ref.watch(isAdminProvider);
    final isAdmin = isAdminAsync.maybeWhen(
      data: (value) => value,
      orElse: () => false,
    );

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text(AdminDashboardText.title)),
        body: Center(
          child: isAdminAsync.isLoading
              ? const CircularProgressIndicator()
              : const Text(AdminDashboardText.adminAccessRequired),
        ),
      );
    }

    final ordersAsync = ref.watch(ordersStreamProvider);
    final analyticsAsync = ref.watch(orderAnalyticsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text(AdminDashboardText.title)),
      body: analyticsAsync.when(
        data: (analytics) {
          final stats = _OrderDashboardStats.fromAnalytics(analytics);
          final recentOrders = ordersAsync.maybeWhen(
            data: (orders) => orders.take(4).toList(),
            orElse: () => const <Order>[],
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              _DashboardHeader(stats: stats),
              const SizedBox(height: 14),
              _DashboardMetricsGrid(stats: stats),
              const SizedBox(height: 14),
              _RecentOrdersPanel(
                orders: recentOrders,
                isLoading: ordersAsync.isLoading,
              ),
            ],
          );
        },
        loading: () => const AppLoadingState(),
        error: (error, _) => AppRetryState(
          icon: Icons.error_outline_rounded,
          title: AdminDashboardText.loadError,
          message: AppErrorHandler.messageFor(
            error,
            fallback: AdminDashboardText.loadErrorSubtitle,
          ),
          onRetry: () => ref.invalidate(orderAnalyticsProvider),
        ),
      ),
    );
  }
}

class _OrderDashboardStats {
  const _OrderDashboardStats({
    required this.totalOrders,
    required this.deliveredOrders,
    required this.totalRevenue,
    required this.pendingOrders,
  });

  final int totalOrders;
  final int deliveredOrders;
  final double totalRevenue;
  final int pendingOrders;

  factory _OrderDashboardStats.fromAnalytics(OrderAnalytics analytics) {
    return _OrderDashboardStats(
      totalOrders: analytics.totalOrders,
      deliveredOrders: analytics.deliveredOrders,
      totalRevenue: analytics.revenue,
      pendingOrders: analytics.pendingOrders,
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.stats});

  final _OrderDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Icon(
              Icons.dashboard_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  AdminDashboardText.overviewTitle,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${stats.pendingOrders} pending | '
                  '\u20B9${_formatPrice(stats.totalRevenue)} revenue',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontWeight: FontWeight.w700,
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

class _DashboardMetricsGrid extends StatelessWidget {
  const _DashboardMetricsGrid({required this.stats});

  final _OrderDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 720 ? 3 : 2;
        final aspectRatio = constraints.maxWidth >= 720 ? 1.75 : 1.28;

        return GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: aspectRatio,
          ),
          children: [
            _DashboardMetricCard(
              title: AdminDashboardText.totalOrders,
              value: stats.totalOrders.toString(),
              icon: Icons.receipt_long_rounded,
              color: AppColors.primary,
            ),
            _DashboardMetricCard(
              title: AdminDashboardText.revenue,
              value: '\u20B9${_formatPrice(stats.totalRevenue)}',
              icon: Icons.payments_rounded,
              color: AppColors.primary,
            ),
            _DashboardMetricCard(
              title: AdminDashboardText.pendingOrders,
              value: stats.pendingOrders.toString(),
              icon: Icons.pending_actions_rounded,
              color: AppColors.accent,
            ),
            _DashboardMetricCard(
              title: AdminDashboardText.deliveredOrders,
              value: stats.deliveredOrders.toString(),
              icon: Icons.task_alt_rounded,
              color: AppColors.primary,
            ),
          ],
        );
      },
    );
  }
}

class _DashboardMetricCard extends StatelessWidget {
  const _DashboardMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, color: color),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.mutedText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentOrdersPanel extends StatelessWidget {
  const _RecentOrdersPanel({
    required this.orders,
    required this.isLoading,
  });

  final List<Order> orders;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            AdminDashboardText.recentOrders,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else if (orders.isEmpty)
            const Text(
              AdminDashboardText.noRecentOrders,
              style: TextStyle(
                color: AppColors.mutedText,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            for (var index = 0; index < orders.length; index += 1) ...[
              _RecentOrderRow(order: orders[index]),
              if (index != orders.length - 1)
                const Divider(height: 18, color: AppColors.border),
            ],
        ],
      ),
    );
  }
}

class _RecentOrderRow extends StatelessWidget {
  const _RecentOrderRow({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final status = OrderStatus.normalize(order.status);
    final statusColor = _statusColor(status);

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.softGreen,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: const Icon(
            Icons.receipt_long_rounded,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '#${_shortOrderId(order.id)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${order.customerDisplayName} | '
                '\u20B9${_formatPrice(order.total)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _MiniStatusPill(status: status, color: statusColor),
      ],
    );
  }
}

class _MiniStatusPill extends StatelessWidget {
  const _MiniStatusPill({
    required this.status,
    required this.color,
  });

  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (OrderStatus.normalize(status)) {
    case OrderStatus.placed:
      return AppColors.accent;
    case OrderStatus.packed:
      return AppColors.primary;
    case OrderStatus.outForDelivery:
      return AppColors.accent;
    case OrderStatus.delivered:
      return AppColors.primary;
  }

  return AppColors.mutedText;
}

String _shortOrderId(String orderId) {
  final trimmed = orderId.trim();
  if (trimmed.length <= 8) return trimmed.isEmpty ? 'UNKNOWN' : trimmed;
  return trimmed.substring(0, 8).toUpperCase();
}

String _formatPrice(double price) {
  return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
}

class AdminDashboardText {
  const AdminDashboardText._();

  static const title = 'Admin Dashboard';
  static const adminAccessRequired = 'Admin access required';
  static const loadError = 'Unable to load dashboard';
  static const loadErrorSubtitle = 'Please try again in a moment.';
  static const overviewTitle = 'Store overview';
  static const totalOrders = 'Total Orders';
  static const revenue = 'Revenue';
  static const pendingOrders = 'Pending Orders';
  static const deliveredOrders = 'Delivered Orders';
  static const recentOrders = 'Recent Orders';
  static const noRecentOrders = 'No recent orders yet';
}
