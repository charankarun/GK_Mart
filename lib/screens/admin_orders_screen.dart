import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../admin_access.dart';

class AdminOrdersScreen extends StatelessWidget {
  const AdminOrdersScreen({super.key});

  static const List<String> statusList = [
    "Placed",
    "Processing",
    "Out for Delivery",
    "Delivered",
  ];

  String _readString(Map<String, dynamic> data, String key,
      {String fallback = ''}) {
    final value = data[key]?.toString().trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  List<Map<String, dynamic>> _readItems(dynamic value) {
    if (value is! List) return [];

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _validStatus(dynamic value) {
    final status = value?.toString().trim();
    return statusList.contains(status) ? status! : statusList.first;
  }

  String _errorMessage(Object? error) {
    final message = error?.toString() ?? '';

    if (message.contains('permission-denied')) {
      return "You don't have permission to view orders";
    }

    if (message.contains('failed-precondition') ||
        message.toLowerCase().contains('index')) {
      return "Orders need a Firestore index. Check debug console.";
    }

    return "Unable to load orders";
  }

  @override
  Widget build(BuildContext context) {
    if (!isAdminUser()) {
      return Scaffold(
        appBar: AppBar(title: const Text("Admin Panel")),
        body: const Center(child: Text("Admin access required")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Admin Panel")),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .orderBy('timestamp', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(_errorMessage(snapshot.error)));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data!.docs;

          if (orders.isEmpty) {
            return const Center(child: Text("No orders yet"));
          }

          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final data = order.data();
              final items = _readItems(data['items']);
              final visibleItems = items.take(10).toList();
              final status = _validStatus(data['status']);
              final total = data['total'] ?? 0;
              final orderLabel = order.id.length > 6
                  ? order.id.substring(0, 6)
                  : order.id;

              return Card(
                margin: const EdgeInsets.all(10),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Order ID: $orderLabel",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text("\u20B9$total"),
                      const SizedBox(height: 8),
                      DropdownButton<String>(
                        value: status,
                        isExpanded: true,
                        items: statusList.map((status) {
                          return DropdownMenuItem(
                            value: status,
                            child: Text(status),
                          );
                        }).toList(),
                        onChanged: (newStatus) async {
                          if (newStatus == null) return;

                          await order.reference.update({
                            'status': newStatus,
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      if (items.isEmpty)
                        const Text("No items")
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...visibleItems.map<Widget>((item) {
                              final name = _readString(
                                item,
                                'name',
                                fallback: 'Product',
                              );
                              final quantity = item['quantity'] ?? 0;
                              return Text("$name x $quantity");
                            }),
                            if (items.length > visibleItems.length)
                              Text(
                                "+ ${items.length - visibleItems.length} more items",
                                style: const TextStyle(color: Colors.grey),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
