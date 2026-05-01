import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'address_screen.dart';
import 'order_success_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final List cartItems;
  

  CheckoutScreen({required this.cartItems});

  @override
  _CheckoutScreenState createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool isLoading = false;
  String paymentMethod = "COD";

  double getTotal() {
    double total = 0;
    for (var item in widget.cartItems) {
      total += item['price'] * item['quantity'];
    }
    return total;
  }

  Future<void> placeOrder() async {
    if (widget.cartItems.isEmpty) return;
    if (isLoading) return;

    setState(() => isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      List<Map<String, dynamic>> items = [];

      for (var item in widget.cartItems) {
        final data = item.data() as Map<String, dynamic>;

        items.add({
          'name': data['name'],
          'price': data['price'],
          'unit': data['unit'] ?? '',
          'quantity': data['quantity'],
        });
      }
      final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();

            String address = "No address added";

              final data = userDoc.data();

              if (data != null) {
                final map = Map<String, dynamic>.from(data as Map);
                address = map['address'] ?? "No address added";
              }
      await FirebaseFirestore.instance.collection('orders').add({
          'userId': user.uid,
          'items': items,
          'total': getTotal(),
          'address': address, // ✅ ADD THIS
          'status': 'Placed',
          'timestamp': FieldValue.serverTimestamp(),
          'paymentMethod': paymentMethod,
        });

      final cartRef = FirebaseFirestore.instance
          .collection('carts')
          .doc(user.uid)
          .collection('items');

      final snapshot = await cartRef.get();

      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => OrderSuccessScreen()
          ),
        (route) => false,
      );
    } catch (e) {
      print("Error placing order: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    double total = getTotal();

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text("Checkout")),
        body: Center(child: Text("Please login to checkout")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text("Checkout")),
      body: Column(
        children: [

          // ITEMS
          Expanded(
            child: ListView.builder(
              itemCount: widget.cartItems.length,
              itemBuilder: (context, index) {
                final item = widget.cartItems[index];

                return Card(
                  margin: EdgeInsets.all(8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    title: Text(item['name']),
                    subtitle: Text("₹${item['price']} x ${item['quantity']}"),
                    trailing: Text(
                      "₹${item['price'] * item['quantity']}",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              },
            ),
          ),

          // ADDRESS
          Container(
            padding: EdgeInsets.all(12),
            margin: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on, color: Colors.red),
                SizedBox(width: 10),

                Expanded(
                  child: FutureBuilder(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .get(),
                    builder: (context, snapshot) {

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Text("Loading address...");
                      }

                      if (!snapshot.hasData || snapshot.data == null) {
                        return Text("No address found");
                      }

                      final doc = snapshot.data as DocumentSnapshot;

                      String address = "No address added";

                      final data = doc.data() as Map<String, dynamic>?;

                          if (data != null) {
                            address = data['address'] ?? "No address added";
                          }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Deliver to",
                              style: TextStyle(fontSize: 12, color: Colors.grey)),
                          SizedBox(height: 4),
                          Text(address,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        ],
                      );
                    },
                  ),
                ),

                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => AddressScreen()),
                    );
                  },
                  child: Text("Change"),
                ),
              ],
            ),
          ),
          Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text("Payment Method",
        style: TextStyle(fontWeight: FontWeight.bold)),

    SizedBox(height: 10),

    Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.money, color: Colors.green),
          SizedBox(width: 10),
          Text("Cash on Delivery"),
          Spacer(),
          Icon(Icons.check_circle, color: Colors.green),
        ],
      ),
    ),
  ],
),

          // TOTAL + BUTTON
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 5),
              ],
            ),
            child: Column(
              children: [

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Total",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text("₹$total",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),

                SizedBox(height: 10),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(double.infinity, 50),
                    backgroundColor: Color(0xFF6C63FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: isLoading
                  ? null
                  : () async {

                      // 🔥 CHECK ADDRESS BEFORE ORDER
                      final doc = await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .get();

                      String address = "No address added";

                      final data = doc.data();

                      if (data != null) {
                        final map = Map<String, dynamic>.from(data as Map);
                        address = map['address'] ?? "No address added";
                      }

                      if (address == "No address added") {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Please add address first")),
                        );
                        return;
                      }

                      await placeOrder();
                    },
                  child: isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text("Place Order"),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
