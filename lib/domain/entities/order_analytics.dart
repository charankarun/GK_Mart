class OrderAnalytics {
  const OrderAnalytics({
    required this.totalOrders,
    required this.revenue,
    required this.pendingOrders,
    required this.deliveredOrders,
  });

  final int totalOrders;
  final double revenue;
  final int pendingOrders;
  final int deliveredOrders;
}
