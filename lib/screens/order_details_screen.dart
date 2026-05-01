import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OrderDetailsScreen extends StatelessWidget {
  final String orderId;

  OrderDetailsScreen({required this.orderId});

  int getStepIndex(String status) {
    final s = status.toLowerCase().trim();

    if (s == 'pending' || s == 'placed') return 0;
    if (s == 'processing') return 1;
    if (s == 'out for delivery') return 2;
    if (s == 'delivered') return 3;

    return 0;
  }

  Widget buildTrackingUI(String status) {
    final currentStep = getStepIndex(status);

    final steps = [
      "Placed",
      "Processing",
      "Out for Delivery",
      "Delivered",
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Order Tracking",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),

        SizedBox(height: 15),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(steps.length, (index) {
            bool isActive = index <= currentStep;

            return Expanded(
              child: Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.green : Colors.grey.shade300,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check,
                      size: 18,
                      color: isActive ? Colors.white : Colors.grey,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    steps[index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: isActive ? Colors.black : Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Order Details")),

      /// 🔥 REALTIME LISTENER
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .snapshots(),

        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final items = data['items'] ?? [];
          final status = (data['status'] ?? 'Placed').toString().trim();

          return Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                /// 🔥 TRACKING UI
                buildTrackingUI(status),

                SizedBox(height: 20),

                if (data['timestamp'] != null)
                  Text(
                    "Date: ${data['timestamp'].toDate().toString().substring(0, 16)}",
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),

                SizedBox(height: 10),

                Text(
                  "Items",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                SizedBox(height: 10),

                Expanded(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];

                      return Card(
                        child: ListTile(
                          title: Text(item['name']),
                          subtitle: Text(
                            "₹${item['price']} x ${item['quantity']}",
                          ),
                        ),
                      );
                    },
                  ),
                ),

                Divider(),

                SizedBox(height: 10),

                Text(
                  "Total: ₹${data['total']}",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}