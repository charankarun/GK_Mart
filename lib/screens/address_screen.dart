import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddressScreen extends StatefulWidget {
  @override
  _AddressScreenState createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  TextEditingController addressController = TextEditingController();

  bool isLoading = false;

  Future<void> saveAddress() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    setState(() => isLoading = true);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({
      'address': addressController.text.trim(),
    }, SetOptions(merge: true));

    if (!mounted) return;

    setState(() => isLoading = false);

    Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    loadAddress();
  }

  void loadAddress() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final doc = await FirebaseFirestore.instance
    .collection('users')
    .doc(user.uid)
    .get();

    if (doc.exists) {
      final data = doc.data();

      if (data != null && data['address'] != null) {
        if (!mounted) return;
        addressController.text = data['address'];
      }
    }
  }

  @override
  void dispose() {
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("My Address")),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: addressController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: "Enter your full address",
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : saveAddress,
              child: isLoading
                  ? CircularProgressIndicator(color: Colors.white)
                  : Text("Save Address"),
            ),
          ],
        ),
      ),
    );
  }
}
