import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'order_details_screen.dart';

class OrdersScreen extends StatelessWidget {

  // 🔥 STATUS COLOR FUNCTION
  Color getStatusColor(String status) {
    switch (status) {
      case 'Placed':
        return Colors.orange;
      case 'Processing':
        return Colors.blue;
      case 'Out for Delivery':
        return Colors.purple;
      case 'Delivered':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text("My Orders")),
        body: Center(child: Text("Please login to view your orders")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text("My Orders")),

      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('userId', isEqualTo: user.uid)
            .orderBy('timestamp', descending: true)
            .snapshots(),

        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text("No orders yet 📦"));
          }

          final orders = snapshot.data!.docs;

          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {

              final order = orders[index];
              final data = order.data() as Map<String, dynamic>;
              final List items = List.from(data['items'] ?? []);
              

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderDetailsScreen(orderId: order.id),
                    ),
                  );
                },

                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 6)
                    ],
                  ),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      /// 🧾 ORDER HEADER
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Order #${orders.length - index}",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),

                          /// 🟢 STATUS
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: getStatusColor(data['status'] ?? 'Placed').withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              data['status'] ?? 'Placed',
                              style: TextStyle(
                                color: getStatusColor(data['status'] ?? 'Placed'),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 6),

                      /// 💰 TOTAL
                      Text(
                        "Total: ₹${data['total']}",
                        style: TextStyle(fontSize: 14),
                      ),
                      Text("Payment: ${data['paymentMethod'] ?? 'COD'}"),

                      SizedBox(height: 4),

                      /// 📅 DATE
                      if (data['timestamp'] != null)
                        Text(
                          data['timestamp']
                              .toDate()
                              .toString()
                              .substring(0, 16),
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),

                      SizedBox(height: 8),

                      /// 🛒 ITEMS PREVIEW
                      ...items.take(2).map<Widget>((item) {
                        return Text(
                          "${item['name']} x ${item['quantity']}",
                          style: TextStyle(fontSize: 13),
                        );
                      }).toList(),

                      if (items.length > 2)
                        Text(
                          "+ ${items.length - 2} more items",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
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
