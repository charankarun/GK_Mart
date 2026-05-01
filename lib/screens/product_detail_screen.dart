import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final String? productId;

  ProductDetailScreen({required this.product, this.productId});

  @override
  _ProductDetailScreenState createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {

  int qty = 0;
  String? cartDocId;

  String get productKey =>
      widget.productId ??
      widget.product['id']?.toString() ??
      widget.product['name'].toString();

  @override
  void initState() {
    super.initState();
    loadCartData();
  }

  void loadCartData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('carts')
        .doc(user.uid)
        .collection('items')
        .doc(productKey)
        .get();

    if (!mounted) return;

    if (doc.exists) {
      setState(() {
        qty = doc['quantity'];
        cartDocId = doc.id;
      });
    } else {
      setState(() {
        qty = 0;
        cartDocId = null;
      });
    }
  }

  Future<void> addToCart() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final cartRef = FirebaseFirestore.instance
        .collection('carts')
        .doc(user.uid)
        .collection('items');

    final docRef = cartRef.doc(productKey);
    final existing = await docRef.get();

    if (existing.exists) {
      final currentQty = existing['quantity'];

      await docRef.update({
        'quantity': currentQty + 1,
      });
    } else {
      await docRef.set({
        'name': widget.product['name'],
        'price': widget.product['price'],
        'unit': widget.product['unit'],
        'image': widget.product['image'],
        'quantity': 1,
      });
    }

    loadCartData();
  }

  Future<void> increaseQty() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || cartDocId == null) return;

    await FirebaseFirestore.instance
        .collection('carts')
        .doc(user.uid)
        .collection('items')
        .doc(cartDocId)
        .update({'quantity': qty + 1});

    loadCartData();
  }

  Future<void> decreaseQty() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || cartDocId == null) return;

    if (qty > 1) {
      await FirebaseFirestore.instance
          .collection('carts')
          .doc(user.uid)
          .collection('items')
          .doc(cartDocId)
          .update({'quantity': qty - 1});
    } else {
      await FirebaseFirestore.instance
          .collection('carts')
          .doc(user.uid)
          .collection('items')
          .doc(cartDocId)
          .delete();
    }

    loadCartData();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;

    return Scaffold(
      appBar: AppBar(title: Text(product['name'])),

      body: Column(
        children: [

          // 🔥 IMAGE
          Container(
            height: 250,
            width: double.infinity,
            color: Colors.grey[200],
            child: product['image'] != null &&
                    product['image'].toString().isNotEmpty
                ? Image.network(product['image'], fit: BoxFit.cover)
                : Icon(Icons.image, size: 100),
          ),

          // 🔥 DETAILS
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Text(
                    product['name'],
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),

                  SizedBox(height: 8),

                  Text(
                    "₹${product['price']}",
                    style: TextStyle(
                      fontSize: 18,
                      color: Color(0xFF6C63FF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  SizedBox(height: 4),

                  Text(
                    product['unit'],
                    style: TextStyle(color: Colors.grey),
                  ),

                  SizedBox(height: 16),

                  Text(
                    "Fresh and high quality product. Delivered fast to your home.",
                    style: TextStyle(fontSize: 14),
                  ),

                  Spacer(),

                  // 🔥 QUANTITY CONTROL
                  qty == 0
                      ? SizedBox.shrink()
                      : Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.remove),
                              onPressed: decreaseQty,
                            ),
                            Text("$qty", style: TextStyle(fontSize: 16)),
                            IconButton(
                              icon: Icon(Icons.add),
                              onPressed: increaseQty,
                            ),
                          ],
                        ),
                ],
              ),
            ),
          ),

          // 🔥 BOTTOM BUTTON
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF6C63FF),
                padding: EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: addToCart,
              child: Text(
                qty == 0 ? "Add to Cart" : "Add More",
                style: TextStyle(fontSize: 16),
              ),
            ),
          )
        ],
      ),
    );
  }
}
