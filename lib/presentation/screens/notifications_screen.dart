import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/order.dart';
import '../providers/auth_providers.dart';
import '../providers/notification_provider.dart';
import '../widgets/app_state_widgets.dart';
import 'order_details_screen.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          centerTitle: true,
        ),
        body: const Center(
          child: Text('Please log in to view notifications'),
        ),
      );
    }

    final notificationsAsync = ref.watch(userNotificationsStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          notificationsAsync.maybeWhen(
            data: (list) {
              final hasUnread = list.any((item) => !item.isRead);
              if (!hasUnread) return const SizedBox.shrink();
              return TextButton.icon(
                onPressed: () {
                  ref.read(notificationControllerProvider).markAllAsRead(session.uid);
                },
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text(
                  'Mark all read',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: notificationsAsync.when(
        data: (list) {
          if (list.isEmpty) {
            return const _EmptyNotifications();
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final notification = list[index];
              return _NotificationCard(
                notification: notification,
                onTap: () {
                  ref.read(notificationControllerProvider).markAsRead(notification.id);
                  if (notification.orderId.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderDetailsScreen(orderId: notification.orderId),
                      ),
                    );
                  }
                },
              );
            },
          );
        },
        loading: () => const AppLoadingState(),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load notifications',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(userNotificationsStreamProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
  });

  final NotificationItem notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = OrderStatus.normalize(notification.status);
    final isUnread = !notification.isRead;
    final iconData = _statusIcon(status, notification.type);
    final iconColor = _statusColor(status);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        decoration: BoxDecoration(
          color: isUnread ? Colors.white : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(
            color: isUnread ? AppColors.primary.withValues(alpha: 0.15) : AppColors.border,
            width: isUnread ? 1.5 : 1.0,
          ),
          boxShadow: isUnread
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : AppShadows.soft,
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Icon Container
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                iconData,
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isUnread ? FontWeight.w900 : FontWeight.w700,
                            color: isUnread ? AppColors.text : AppColors.mutedText,
                          ),
                        ),
                      ),
                      if (isUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
                      color: isUnread ? const Color(0xFF374151) : AppColors.mutedText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getRelativeTime(notification.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(String status, String type) {
    if (type == 'admin_new_order') {
      return Icons.receipt_long_rounded;
    }
    switch (status) {
      case OrderStatus.placed:
      case OrderStatus.confirmed:
        return Icons.check_circle_rounded;
      case OrderStatus.packed:
        return Icons.inventory_2_rounded;
      case OrderStatus.outForDelivery:
      case OrderStatus.shipped:
        return Icons.local_shipping_rounded;
      case OrderStatus.delivered:
        return Icons.task_alt_rounded;
      case OrderStatus.cancelled:
        return Icons.cancel_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case OrderStatus.placed:
      case OrderStatus.confirmed:
        return AppColors.accent;
      case OrderStatus.packed:
        return AppColors.info;
      case OrderStatus.outForDelivery:
      case OrderStatus.shipped:
        return AppColors.accent;
      case OrderStatus.delivered:
        return AppColors.primary;
      case OrderStatus.cancelled:
        return AppColors.danger;
      default:
        return AppColors.primary;
    }
  }

  String _getRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.isNegative || difference.inSeconds < 30) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final count = difference.inMinutes;
      return '$count ${count == 1 ? "min" : "mins"} ago';
    } else if (difference.inHours < 24) {
      final count = difference.inHours;
      return '$count ${count == 1 ? "hour" : "hours"} ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else {
      final day = dateTime.day.toString().padLeft(2, '0');
      final month = dateTime.month.toString().padLeft(2, '0');
      return '$day/$month/${dateTime.year}';
    }
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.softGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_off_rounded,
                color: AppColors.primary,
                size: 38,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "You're all caught up.",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "No new notifications.",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
