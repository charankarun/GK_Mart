import 'dart:convert';

import '../../domain/entities/order.dart';

class NotificationPayload {
  const NotificationPayload({
    required this.type,
    this.orderId = '',
    this.status = '',
  });

  static const orderStatusType = 'order_status';

  final String type;
  final String orderId;
  final String status;

  bool get isOrderNotification {
    return type == orderStatusType || orderId.trim().isNotEmpty;
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
    };
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

    final inferredType =
        type.isEmpty && orderId.isNotEmpty ? orderStatusType : type.trim();
    if (inferredType.isEmpty && orderId.isEmpty) return null;

    return NotificationPayload(
      type: inferredType,
      orderId: orderId,
      status: rawStatus.isEmpty ? '' : OrderStatus.normalize(rawStatus),
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
}

class OrderNotificationCopy {
  const OrderNotificationCopy({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

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
          title: 'Order placed',
          body: 'Your order$orderSuffix has been placed successfully.',
        );
      case OrderStatus.packed:
        return OrderNotificationCopy(
          title: 'Order packed',
          body: 'Your order$orderSuffix is packed and getting ready.',
        );
      case OrderStatus.outForDelivery:
        return OrderNotificationCopy(
          title: 'Out for delivery',
          body: 'Your order$orderSuffix is on the way.',
        );
      case OrderStatus.delivered:
        return OrderNotificationCopy(
          title: 'Order delivered',
          body: 'Your order$orderSuffix has been delivered.',
        );
    }

    return OrderNotificationCopy(
      title: 'Order update',
      body: 'Your order$orderSuffix has a new update.',
    );
  }
}
