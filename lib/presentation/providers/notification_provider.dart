import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import 'auth_providers.dart';

class NotificationItem {
  final String id;
  final String type;
  final String orderId;
  final String status;
  final String amount;
  final String customerName;
  final String phone;
  final String date;
  final DateTime createdAt;
  final bool isRead;
  final String title;
  final String body;
  final DateTime? readAt;

  NotificationItem({
    required this.id,
    required this.type,
    required this.orderId,
    required this.status,
    required this.amount,
    required this.customerName,
    required this.phone,
    required this.date,
    required this.createdAt,
    required this.isRead,
    required this.title,
    required this.body,
    required this.readAt,
  });

  factory NotificationItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtRaw = data['createdAt'];
    DateTime parsedCreatedAt;
    if (createdAtRaw is Timestamp) {
      parsedCreatedAt = createdAtRaw.toDate();
    } else {
      parsedCreatedAt = DateTime.now();
    }

    final readAtRaw = data['readAt'];
    DateTime? parsedReadAt;
    if (readAtRaw is Timestamp) {
      parsedReadAt = readAtRaw.toDate();
    }

    return NotificationItem(
      id: doc.id,
      type: data['type']?.toString() ?? '',
      orderId: data['orderId']?.toString() ?? '',
      status: data['status']?.toString() ?? '',
      amount: data['amount']?.toString() ?? '',
      customerName: data['customerName']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      date: data['date']?.toString() ?? '',
      createdAt: parsedCreatedAt,
      isRead: data['isRead'] as bool? ?? false,
      title: data['title']?.toString() ?? '',
      body: data['body']?.toString() ?? '',
      readAt: parsedReadAt,
    );
  }
}

final userNotificationsStreamProvider = StreamProvider.autoDispose<List<NotificationItem>>((ref) {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return Stream.value(const <NotificationItem>[]);

  return FirebaseFirestore.instance
      .collection(FirestoreCollections.notifications)
      .where('targetUserId', isEqualTo: session.uid)
      .snapshots()
      .map((snapshot) {
        final items = snapshot.docs.map((doc) => NotificationItem.fromFirestore(doc)).toList();
        // Sort in memory to avoid requiring a Firestore composite index
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return items;
      });
});

final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notificationsAsync = ref.watch(userNotificationsStreamProvider);
  return notificationsAsync.maybeWhen(
    data: (list) => list.where((item) => !item.isRead).length,
    orElse: () => 0,
  );
});

final notificationControllerProvider = Provider((ref) => NotificationController());

class NotificationController {
  Future<void> markAsRead(String notificationId) async {
    await FirebaseFirestore.instance
        .collection(FirestoreCollections.notifications)
        .doc(notificationId)
        .update({
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> markAllAsRead(String userId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(FirestoreCollections.notifications)
        .where('targetUserId', isEqualTo: userId)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    var hasUpdates = false;
    for (final doc in snapshot.docs) {
      final isRead = doc.data()['isRead'] as bool? ?? false;
      if (!isRead) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
        hasUpdates = true;
      }
    }
    if (hasUpdates) {
      await batch.commit();
    }
  }
}
