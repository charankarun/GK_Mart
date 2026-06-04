import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_app/domain/entities/auth_session.dart';
import 'package:supermarket_app/presentation/providers/auth_providers.dart';
import 'package:supermarket_app/presentation/providers/notification_provider.dart';
import 'package:supermarket_app/presentation/screens/notifications_screen.dart';

class _FakeNotificationController extends NotificationController {
  final List<String> markedReadIds = [];
  bool markedAllRead = false;

  @override
  Future<void> markAsRead(String notificationId) async {
    markedReadIds.add(notificationId);
  }

  @override
  Future<void> markAllAsRead(String userId) async {
    markedAllRead = true;
  }
}

void main() {
  testWidgets('NotificationsScreen shows empty state when list is empty', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSessionProvider.overrideWithValue(
            const AuthSession(uid: 'user-1', email: 'user@example.com'),
          ),
          userNotificationsStreamProvider.overrideWith(
            (ref) => Stream.value(const <NotificationItem>[]),
          ),
        ],
        child: const MaterialApp(
          home: NotificationsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text("You're all caught up."), findsOneWidget);
    expect(find.text("No new notifications."), findsOneWidget);
  });

  testWidgets('NotificationsScreen displays notification list with relative times and allows interactions', (tester) async {
    final fakeController = _FakeNotificationController();
    final now = DateTime.now();

    final testNotifications = [
      NotificationItem(
        id: 'notif-1',
        type: 'customer_order_placed',
        orderId: 'GK00001',
        status: 'placed',
        amount: '150',
        customerName: 'Karun',
        phone: '1234567890',
        date: '05/06/2026 12:00',
        createdAt: now.subtract(const Duration(minutes: 5)),
        isRead: false,
        title: 'Order Placed Successfully',
        body: 'Your order GK00001 has been placed.',
        readAt: null,
      ),
      NotificationItem(
        id: 'notif-2',
        type: 'order_status',
        orderId: 'GK00002',
        status: 'delivered',
        amount: '200',
        customerName: 'Karun',
        phone: '1234567890',
        date: '04/06/2026 10:00',
        createdAt: now.subtract(const Duration(hours: 2)),
        isRead: true,
        title: 'Order Delivered',
        body: 'Your order GK00002 has been delivered.',
        readAt: now.subtract(const Duration(hours: 2)),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSessionProvider.overrideWithValue(
            const AuthSession(uid: 'user-1', email: 'user@example.com'),
          ),
          userNotificationsStreamProvider.overrideWith(
            (ref) => Stream.value(testNotifications),
          ),
          notificationControllerProvider.overrideWithValue(fakeController),
        ],
        child: const MaterialApp(
          home: NotificationsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify title and body are rendered
    expect(find.text('Order Placed Successfully'), findsOneWidget);
    expect(find.text('Your order GK00001 has been placed.'), findsOneWidget);
    expect(find.text('Order Delivered'), findsOneWidget);
    expect(find.text('Your order GK00002 has been delivered.'), findsOneWidget);

    // Verify relative times
    expect(find.text('5 mins ago'), findsOneWidget);
    expect(find.text('2 hours ago'), findsOneWidget);

    // Tap on a notification and verify click callback is triggered
    await tester.tap(find.text('Order Placed Successfully'));
    await tester.pump();

    expect(fakeController.markedReadIds, contains('notif-1'));

    // Tap "Mark all read" button and verify markAllAsRead is triggered
    expect(find.text('Mark all read'), findsOneWidget);
    final TextButton button = tester.widget(find.byType(TextButton));
    button.onPressed?.call();
    await tester.pump();

    expect(fakeController.markedAllRead, isTrue);
  });
}
