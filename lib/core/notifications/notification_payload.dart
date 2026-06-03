import 'dart:convert';

import '../../domain/entities/order.dart';

class NotificationPayload {
  const NotificationPayload({
    required this.type,
    this.orderId = '',
    this.status = '',
    this.amount = '',
    this.customerName = '',
    this.phone = '',
    this.date = '',
  });

  static const customerOrderPlacedType = 'customer_order_placed';
  static const adminNewOrderType = 'admin_new_order';
  static const orderStatusType = 'order_status';

  final String type;
  final String orderId;
  final String status;
  final String amount;
  final String customerName;
  final String phone;
  final String date;

  bool get isOrderNotification {
    return type == customerOrderPlacedType ||
        type == adminNewOrderType ||
        type == orderStatusType ||
        orderId.trim().isNotEmpty;
  }

  String get normalizedStatus {
    final trimmedStatus = status.trim();
    if (trimmedStatus.isEmpty) return '';
    return OrderStatus.normalize(trimmedStatus);
  }

  Map<String, String> toMap() {
    return {
      'type': type,
      if (orderId.trim().isNotEmpty) 'orderId': orderId.trim(),
      if (normalizedStatus.isNotEmpty) 'status': normalizedStatus,
      if (amount.trim().isNotEmpty) 'amount': amount.trim(),
      if (customerName.trim().isNotEmpty) 'customerName': customerName.trim(),
      if (phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (date.trim().isNotEmpty) 'date': date.trim(),
    };
  }

  static NotificationPayload customerOrderPlaced({
    required String orderId,
    required double amount,
    required DateTime date,
    required String status,
  }) {
    return NotificationPayload(
      type: customerOrderPlacedType,
      orderId: orderId.trim(),
      amount: _formatAmount(amount),
      date: _formatDate(date),
      status: OrderStatus.normalize(status),
    );
  }

  static NotificationPayload adminNewOrder({
    required String orderId,
    required String customerName,
    required String phone,
    required double amount,
    required DateTime date,
  }) {
    return NotificationPayload(
      type: adminNewOrderType,
      orderId: orderId.trim(),
      customerName: customerName.trim(),
      phone: phone.trim(),
      amount: _formatAmount(amount),
      date: _formatDate(date),
    );
  }

  String toJson() {
    return jsonEncode(toMap());
  }

  static NotificationPayload orderStatus({
    required String orderId,
    required String status,
  }) {
    return NotificationPayload(
      type: orderStatusType,
      orderId: orderId.trim(),
      status: OrderStatus.normalize(status),
    );
  }

  static NotificationPayload? fromJson(String? value) {
    final trimmedValue = value?.trim();
    if (trimmedValue == null || trimmedValue.isEmpty) return null;

    try {
      final decoded = jsonDecode(trimmedValue);
      if (decoded is Map) return fromMap(decoded);
    } on FormatException {
      return null;
    }

    return null;
  }

  static NotificationPayload? fromMap(Map<dynamic, dynamic> data) {
    final type = _readString(
      data,
      const ['type', 'notificationType', 'notification_type'],
    );
    final orderId = _readString(
      data,
      const ['orderId', 'order_id', 'orderID', 'id'],
    );
    final rawStatus = _readString(
      data,
      const ['status', 'orderStatus', 'order_status'],
    );
    final amount = _readString(data, const ['amount', 'orderAmount']);
    final customerName = _readString(
      data,
      const ['customerName', 'customer_name'],
    );
    final phone = _readString(data, const ['phone', 'mobile']);
    final date = _readString(data, const ['date', 'orderDate', 'order_time']);

    final inferredType =
        type.isEmpty && orderId.isNotEmpty ? orderStatusType : type.trim();
    if (inferredType.isEmpty && orderId.isEmpty) return null;

    return NotificationPayload(
      type: inferredType,
      orderId: orderId,
      status: rawStatus.isEmpty ? '' : OrderStatus.normalize(rawStatus),
      amount: amount,
      customerName: customerName,
      phone: phone,
      date: date,
    );
  }

  static String _readString(Map<dynamic, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;

      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _formatAmount(double amount) {
    return amount % 1 == 0 ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
  }

  static String _formatDate(DateTime date) {
    final localDate = date.toLocal();
    final day = localDate.day.toString().padLeft(2, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    final hour = localDate.hour.toString().padLeft(2, '0');
    final minute = localDate.minute.toString().padLeft(2, '0');
    return '$day/$month/${localDate.year} $hour:$minute';
  }
}

class OrderNotificationCopy {
  const OrderNotificationCopy({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  static OrderNotificationCopy orderPlaced({
    required String orderId,
    required double amount,
  }) {
    final visibleOrderId = orderId.trim();
    return OrderNotificationCopy(
      title: 'Order Placed Successfully',
      body: 'Your order $visibleOrderId has been placed successfully.\n'
          'Amount: ₹${_formatAmount(amount)}',
    );
  }

  static OrderNotificationCopy adminNewOrder({
    required String orderId,
    required String customerName,
    required double amount,
  }) {
    final visibleOrderId = orderId.trim();
    final visibleName = customerName.trim().isEmpty
        ? 'Customer'
        : customerName.trim();
    return OrderNotificationCopy(
      title: 'New Order Received',
      body: 'Order $visibleOrderId\n'
          'Customer: $visibleName\n'
          'Amount: ₹${_formatAmount(amount)}',
    );
  }

  static OrderNotificationCopy forStatus({
    required String status,
    required String orderId,
  }) {
    final trimmedStatus = status.trim();
    final visibleOrderId = orderId.trim();
    final orderSuffix = visibleOrderId.isEmpty ? '' : ' $visibleOrderId';

    if (trimmedStatus.isEmpty) {
      return OrderNotificationCopy(
        title: 'Order update',
        body: 'Your order$orderSuffix has a new update.',
      );
    }

    final normalizedStatus = OrderStatus.normalize(trimmedStatus);

    switch (normalizedStatus) {
      case OrderStatus.placed:
        return OrderNotificationCopy(
          title: 'Order Confirmed',
          body: 'Your order$orderSuffix has been confirmed.',
        );
      case OrderStatus.confirmed:
        return OrderNotificationCopy(
          title: 'Order Confirmed',
          body: 'Your order$orderSuffix has been confirmed.',
        );
      case OrderStatus.packed:
        return OrderNotificationCopy(
          title: 'Order Packed',
          body:
              'Your order$orderSuffix has been packed and is being prepared for dispatch.',
        );
      case OrderStatus.shipped:
        return OrderNotificationCopy(
          title: 'Order Shipped',
          body: 'Your order$orderSuffix is on the way.',
        );
      case OrderStatus.outForDelivery:
        return OrderNotificationCopy(
          title: 'Out For Delivery',
          body: 'Your order$orderSuffix is on the way.',
        );
      case OrderStatus.delivered:
        return OrderNotificationCopy(
          title: 'Order Delivered',
          body: 'Your order$orderSuffix has been delivered successfully.',
        );
      case OrderStatus.cancelled:
        return OrderNotificationCopy(
          title: 'Order Cancelled',
          body: 'Your order$orderSuffix has been cancelled.',
        );
    }

    return OrderNotificationCopy(
      title: 'Order update',
      body: 'Your order$orderSuffix has a new update.',
    );
  }

  static String _formatAmount(double amount) {
    return amount % 1 == 0 ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
  }
}
