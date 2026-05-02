import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/order.dart';
import '../../providers/auth_providers.dart';
import '../../providers/order_providers.dart';

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
        appBar: AppBar(title: const Text('Admin Dashboard')),
        body: Center(
          child: isAdminAsync.isLoading
              ? const CircularProgressIndicator()
              : const Text('Admin access required'),
        ),
      );
    }

    final ordersAsync = ref.watch(ordersStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: ordersAsync.when(
        data: (orders) {
          final stats = _OrderDashboardStats.fromOrders(orders);

          return LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 720 ? 3 : 2;

              return GridView(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: constraints.maxWidth >= 720 ? 1.7 : 1.25,
                ),
                children: [
                  _DashboardMetricCard(
                    title: 'Total Orders',
                    value: stats.totalOrders,
                    icon: Icons.receipt_long,
                    color: const Color(0xFF2563EB),
                  ),
                  _DashboardMetricCard(
                    title: 'Pending Orders',
                    value: stats.pendingOrders,
                    icon: Icons.pending_actions,
                    color: const Color(0xFFF59E0B),
                  ),
                  _DashboardMetricCard(
                    title: 'Delivered Orders',
                    value: stats.deliveredOrders,
                    icon: Icons.task_alt,
                    color: const Color(0xFF16A34A),
                  ),
                  _DashboardMetricCard(
                    title: OrderStatus.placed,
                    value: stats.placedOrders,
                    icon: Icons.shopping_bag,
                    color: const Color(0xFFEA580C),
                  ),
                  _DashboardMetricCard(
                    title: OrderStatus.packed,
                    value: stats.packedOrders,
                    icon: Icons.sync,
                    color: const Color(0xFF7C3AED),
                  ),
                  _DashboardMetricCard(
                    title: OrderStatus.outForDelivery,
                    value: stats.outForDeliveryOrders,
                    icon: Icons.local_shipping,
                    color: const Color(0xFF0891B2),
                  ),
                ],
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Unable to load dashboard')),
      ),
    );
  }
}

class _OrderDashboardStats {
  const _OrderDashboardStats({
    required this.totalOrders,
    required this.placedOrders,
    required this.packedOrders,
    required this.outForDeliveryOrders,
    required this.deliveredOrders,
  });

  final int totalOrders;
  final int placedOrders;
  final int packedOrders;
  final int outForDeliveryOrders;
  final int deliveredOrders;

  int get pendingOrders {
    return placedOrders + packedOrders + outForDeliveryOrders;
  }

  factory _OrderDashboardStats.fromOrders(List<Order> orders) {
    int placed = 0;
    int packed = 0;
    int outForDelivery = 0;
    int delivered = 0;

    for (final order in orders) {
      switch (OrderStatus.normalize(order.status)) {
        case OrderStatus.placed:
          placed++;
          break;
        case OrderStatus.packed:
          packed++;
          break;
        case OrderStatus.outForDelivery:
          outForDelivery++;
          break;
        case OrderStatus.delivered:
          delivered++;
          break;
      }
    }

    return _OrderDashboardStats(
      totalOrders: orders.length,
      placedOrders: placed,
      packedOrders: packed,
      outForDeliveryOrders: outForDelivery,
      deliveredOrders: delivered,
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
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
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
                  value.toString(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
