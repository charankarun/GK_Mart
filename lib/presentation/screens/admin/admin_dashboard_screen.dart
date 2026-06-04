import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error_handler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/order_analytics.dart';
import '../../providers/auth_providers.dart';
import '../../providers/order_providers.dart';
import '../../providers/product_provider.dart';
import '../../providers/store_providers.dart';
import '../../widgets/app_state_widgets.dart';
import 'admin_orders_screen.dart';
import 'store_settings_screen.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() {
    return _AdminDashboardScreenState();
  }
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _dashboardLog(
      'Dashboard initialization selectedDate=${_selectedDate.toIso8601String()}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdminAsync = ref.watch(isAdminProvider);
    final isAdmin = isAdminAsync.maybeWhen(
      data: (value) => value,
      orElse: () => false,
    );

    if (!isAdmin) {
      if (isAdminAsync.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text(AdminDashboardText.title)),
          body: AppRetryState(
            icon: Icons.admin_panel_settings_outlined,
            title: AdminDashboardText.adminVerificationError,
            message: AppErrorHandler.messageFor(
              isAdminAsync.error,
              fallback: AdminDashboardText.adminVerificationErrorSubtitle,
            ),
            onRetry: () => ref.invalidate(isAdminProvider),
          ),
        );
      }

      return Scaffold(
        appBar: AppBar(title: const Text(AdminDashboardText.title)),
        body: Center(
          child: isAdminAsync.isLoading
              ? const CircularProgressIndicator()
              : const Text(AdminDashboardText.adminAccessRequired),
        ),
      );
    }

    final analyticsAsync = ref.watch(orderAnalyticsProvider(_selectedDate));
    final recentOrdersAsync = ref.watch(dashboardRecentOrdersProvider);
    final inventoryStatsAsync = ref.watch(dashboardInventoryStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AdminDashboardText.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: 'Store Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StoreSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: analyticsAsync.when(
        data: (analytics) {
          final stats = _OrderDashboardStats.fromAnalytics(analytics);
          final recentOrders = recentOrdersAsync.maybeWhen(
            data: (orders) => orders,
            orElse: () => const <Order>[],
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              _DashboardHeader(stats: stats),
              const SizedBox(height: 14),
              const _StoreStatusCard(),
              const SizedBox(height: 14),
              _DashboardDateFilter(
                selectedDate: _selectedDate,
                onPickDate: _pickDate,
              ),
              const SizedBox(height: 14),
              _DashboardMetricsGrid(
                stats: stats,
                inventoryStatsAsync: inventoryStatsAsync,
                onOpenAllOrders: _openAllOrders,
                onOpenSelectedDateOrders: _openOrdersForSelectedDate,
              ),
              if (inventoryStatsAsync.hasError) ...[
                const SizedBox(height: 14),
                AppInlineRetryState(
                  icon: Icons.inventory_2_outlined,
                  message: AppErrorHandler.messageFor(
                    inventoryStatsAsync.error,
                    fallback: AdminDashboardText.inventoryLoadError,
                  ),
                  onRetry: () {
                    ref.invalidate(dashboardInventoryStatsProvider);
                  },
                ),
              ],
              const SizedBox(height: 14),
              _RecentOrdersPanel(
                orders: recentOrders,
                isLoading: recentOrdersAsync.isLoading,
                error: recentOrdersAsync.error,
                onRetry: () => ref.invalidate(dashboardRecentOrdersProvider),
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
          onRetry: () => ref.invalidate(orderAnalyticsProvider(_selectedDate)),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null || !mounted) return;

    _dashboardLog('Date filter query picked=${picked.toIso8601String()}');
    setState(() => _selectedDate = picked);
  }

  void _openOrdersForSelectedDate() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminDateOrdersScreen(date: _selectedDate),
      ),
    );
  }

  void _openAllOrders() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AdminOrdersScreen(),
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
    required this.selectedDate,
    required this.selectedDateOrders,
    required this.selectedDateRevenue,
  });

  final int totalOrders;
  final int deliveredOrders;
  final double totalRevenue;
  final int pendingOrders;
  final DateTime selectedDate;
  final int selectedDateOrders;
  final double selectedDateRevenue;

  factory _OrderDashboardStats.fromAnalytics(OrderAnalytics analytics) {
    return _OrderDashboardStats(
      totalOrders: analytics.totalOrders,
      deliveredOrders: analytics.deliveredOrders,
      totalRevenue: analytics.revenue,
      pendingOrders: analytics.pendingOrders,
      selectedDate: analytics.selectedDate,
      selectedDateOrders: analytics.selectedDateOrders,
      selectedDateRevenue: analytics.selectedDateRevenue,
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

class _DashboardDateFilter extends StatelessWidget {
  const _DashboardDateFilter({
    required this.selectedDate,
    required this.onPickDate,
  });

  final DateTime selectedDate;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onPickDate,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.soft,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.softGreen,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      AdminDashboardText.calendarFilter,
                      style: TextStyle(
                        color: AppColors.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatDate(selectedDate),
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_calendar_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardMetricsGrid extends StatelessWidget {
  const _DashboardMetricsGrid({
    required this.stats,
    required this.inventoryStatsAsync,
    required this.onOpenAllOrders,
    required this.onOpenSelectedDateOrders,
  });

  final _OrderDashboardStats stats;
  final AsyncValue<DashboardInventoryStats> inventoryStatsAsync;
  final VoidCallback onOpenAllOrders;
  final VoidCallback onOpenSelectedDateOrders;

  @override
  Widget build(BuildContext context) {
    final inventoryStats = inventoryStatsAsync.maybeWhen(
      data: (stats) => stats,
      orElse: () => null,
    );
    final inventoryValueFallback =
        inventoryStatsAsync.isLoading ? AdminDashboardText.loadingValue : '--';

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 720
            ? 3
            : constraints.maxWidth < 320
                ? 1
                : 2;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final extraTextHeight = ((textScale - 1) * 28).clamp(0, 36).toDouble();
        final baseCardExtent = constraints.maxWidth >= 720
            ? 166.0
            : constraints.maxWidth < 360
                ? 190.0
                : 180.0;
        final cardExtent = baseCardExtent + extraTextHeight;

        return GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: cardExtent,
          ),
          children: [
            _DashboardMetricCard(
              title: AdminDashboardText.totalOrders,
              value: stats.totalOrders.toString(),
              icon: Icons.receipt_long_rounded,
              color: AppColors.primary,
              onTap: onOpenAllOrders,
            ),
            _DashboardMetricCard(
              title: AdminDashboardText.revenue,
              value: '\u20B9${_formatPrice(stats.totalRevenue)}',
              icon: Icons.payments_rounded,
              color: AppColors.primary,
            ),
            _DashboardMetricCard(
              title: AdminDashboardText.dailyRevenue,
              value: '\u20B9${_formatPrice(stats.selectedDateRevenue)}',
              icon: Icons.today_rounded,
              color: AppColors.success,
            ),
            _DashboardMetricCard(
              title: AdminDashboardText.dailyOrders,
              value: stats.selectedDateOrders.toString(),
              icon: Icons.event_available_rounded,
              color: AppColors.info,
              onTap: onOpenSelectedDateOrders,
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
            _DashboardMetricCard(
              title: AdminDashboardText.totalProducts,
              value: inventoryStats?.totalProducts.toString() ??
                  inventoryValueFallback,
              icon: Icons.inventory_2_rounded,
              color: AppColors.info,
            ),
            _DashboardMetricCard(
              title: AdminDashboardText.availableProducts,
              value: inventoryStats?.availableProducts.toString() ??
                  inventoryValueFallback,
              icon: Icons.check_circle_rounded,
              color: AppColors.success,
            ),
            _DashboardMetricCard(
              title: AdminDashboardText.lowStockProducts,
              value: inventoryStats?.lowStockProducts.toString() ??
                  inventoryValueFallback,
              icon: Icons.warning_amber_rounded,
              color: AppColors.accent,
            ),
            _DashboardMetricCard(
              title: AdminDashboardText.outOfStockProducts,
              value: inventoryStats?.outOfStockProducts.toString() ??
                  inventoryValueFallback,
              icon: Icons.remove_shopping_cart_rounded,
              color: AppColors.danger,
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
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(AppRadii.lg);

    return Material(
      color: AppColors.card,
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.mutedText.withValues(alpha: 0.5),
                      size: 16,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          value,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.mutedText,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentOrdersPanel extends StatelessWidget {
  const _RecentOrdersPanel({
    required this.orders,
    required this.isLoading,
    required this.error,
    required this.onRetry,
  });

  final List<Order> orders;
  final bool isLoading;
  final Object? error;
  final VoidCallback onRetry;

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
          else if (error != null)
            _InlineDashboardRetry(
              message: AppErrorHandler.messageFor(
                error,
                fallback: AdminDashboardText.recentOrdersLoadError,
              ),
              onRetry: onRetry,
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

class _InlineDashboardRetry extends StatelessWidget {
  const _InlineDashboardRetry({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.mutedText),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.mutedText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: const Text(AdminDashboardText.retry),
        ),
      ],
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

String _formatDate(DateTime date) {
  final localDate = date.toLocal();
  final day = localDate.day.toString().padLeft(2, '0');
  final month = localDate.month.toString().padLeft(2, '0');
  return '$day/$month/${localDate.year}';
}

void _dashboardLog(String message) {
  if (!kDebugMode) return;
  debugPrint('[AdminDashboard] $message');
}

class AdminDashboardText {
  const AdminDashboardText._();

  static const title = 'Admin Dashboard';
  static const adminAccessRequired = 'Admin access required';
  static const adminVerificationError = 'Unable to verify admin access';
  static const adminVerificationErrorSubtitle = 'Please try again in a moment.';
  static const loadError = 'Unable to load dashboard';
  static const loadErrorSubtitle = 'Please try again in a moment.';
  static const overviewTitle = 'Store overview';
  static const totalOrders = 'Total Orders';
  static const revenue = 'Revenue';
  static const pendingOrders = 'Pending Orders';
  static const deliveredOrders = 'Delivered Orders';
  static const totalProducts = 'Total Products';
  static const availableProducts = 'Available Products';
  static const lowStockProducts = 'Low Stock';
  static const outOfStockProducts = 'Out Of Stock';
  static const calendarFilter = 'Calendar Filter';
  static const dailyRevenue = 'Revenue For Selected Date';
  static const dailyOrders = 'Orders For Selected Date';
  static const recentOrders = 'Recent Orders';
  static const noRecentOrders = 'No recent orders yet';
  static const inventoryLoadError = 'Unable to load inventory stats.';
  static const recentOrdersLoadError = 'Unable to load recent orders.';
  static const loadingValue = '...';
  static const retry = 'Retry';
}

class _StoreStatusCard extends ConsumerWidget {
  const _StoreStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(storeConfigProvider);

    return configAsync.when(
      data: (config) {
        final isOpen = config.isOpen;
        final statusText = isOpen ? 'OPEN' : 'CLOSED';
        final statusColor = isOpen ? AppColors.success : AppColors.danger;
        final hoursText = "${config.formattedOpenTime} - ${config.formattedCloseTime}";

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            side: const BorderSide(color: AppColors.border),
          ),
          color: AppColors.card,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StoreSettingsScreen(),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Icon(
                      isOpen ? Icons.storefront_rounded : Icons.storefront_outlined,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Store Status: ',
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Today's Hours: $hoursText",
                          style: const TextStyle(
                            color: AppColors.mutedText,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: AppColors.mutedText,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
