class OrderAnalytics {
  const OrderAnalytics({
    required this.totalOrders,
    required this.revenue,
    required this.pendingOrders,
    required this.deliveredOrders,
    required this.selectedDate,
    required this.selectedDateOrders,
    required this.selectedDateRevenue,
  });

  final int totalOrders;
  final double revenue;
  final int pendingOrders;
  final int deliveredOrders;
  final DateTime selectedDate;
  final int selectedDateOrders;
  final double selectedDateRevenue;
}
