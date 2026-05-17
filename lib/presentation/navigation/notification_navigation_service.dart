import 'package:flutter/material.dart';

import '../../core/notifications/notification_payload.dart';
import '../screens/order_details_screen.dart';
import '../screens/orders_screen.dart';

class NotificationNavigationService {
  NotificationNavigationService._();

  static final NotificationNavigationService instance =
      NotificationNavigationService._();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  NotificationPayload? _pendingPayload;

  void open(NotificationPayload payload) {
    if (!_navigate(payload)) {
      _pendingPayload = payload;
    }
  }

  void processPending() {
    final payload = _pendingPayload;
    if (payload == null) return;

    if (_navigate(payload)) {
      _pendingPayload = null;
    }
  }

  bool _navigate(NotificationPayload payload) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return false;

    final orderId = payload.orderId.trim();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) {
          if (orderId.isEmpty) return const OrdersScreen();
          return OrderDetailsScreen(orderId: orderId);
        },
      ),
    );
    return true;
  }
}
