import 'customer_order.dart';

class OrderPage {
  const OrderPage({
    required this.orders,
    required this.hasMore,
    this.nextCursor,
  });

  final List<Order> orders;
  final bool hasMore;
  final OrderPageCursor? nextCursor;
}

class OrderPageCursor {
  const OrderPageCursor({
    required this.id,
    this.createdAt,
  });

  final String id;
  final DateTime? createdAt;
}
