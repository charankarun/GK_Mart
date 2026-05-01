import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../admin_access.dart';
import 'orders_screen.dart';
import 'edit_profile_screen.dart';
import 'address_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_orders_screen.dart';
import 'change_password_screen.dart';
import 'admin_inventory_screen.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text("My Account"),
        ),
        body: Center(child: Text("Please login to view your account")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("My Account"),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [

            // 👤 PROFILE CARD
            Container(
              margin: EdgeInsets.all(12),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(color: Colors.grey.shade200, blurRadius: 5),
                ],
              ),
              child: Row(
                children: [

                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Color(0xFF6C63FF),
                    child: Icon(Icons.person, color: Colors.white, size: 30),
                  ),

                  SizedBox(width: 15),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StreamBuilder(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .snapshots(),
                        builder: (context, snapshot) {

                          if (!snapshot.hasData) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Loading...", style: TextStyle(fontSize: 16)),
                              ],
                            );
                          }

                          final doc = snapshot.data;
                            if (doc == null || !doc.exists) {
                              return Text("No data");
                            }

                            final data = doc.data() as Map<String, dynamic>;

                          final name = data['name'] ?? "User";
                          final email = data['email'] ?? "";

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 5),
                              Text(email),
                            ],
                          );
                        },
                      )
                    ],
                  )
                ],
              ),
            ),

            // 📦 OPTIONS LIST
            _buildOption(
                icon: Icons.edit,
                title: "Edit Profile",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => EditProfileScreen()),
                  );
                },
              ),
            _buildOption(
              icon: Icons.shopping_bag,
              title: "My Orders",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => OrdersScreen()),
                );
              },
            ),

            _buildOption(
              icon: Icons.location_on,
              title: "My Address",
              onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => AddressScreen()),
                    );
                  },
             ),

            _buildOption(
              icon: Icons.support_agent,
              title: "Customer Support",
              onTap: () {},
            ),

            _buildOption(
              icon: Icons.lock_reset,
              title: "Reset Password",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                );
              },
            ),

            if (isAdminUser())
              _buildOption(
                icon: Icons.inventory_2,
                title: "Manage Products",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminInventoryScreen(),
                    ),
                  );
                },
              ),

            if (isAdminUser())
              _buildOption(
                icon: Icons.admin_panel_settings,
                title: "Admin Panel",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminOrdersScreen()),
                  );
                },
              ),

            SizedBox(height: 20),

            // 🚪 LOGOUT BUTTON
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                ),
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                },
                child: Text("Signout"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔧 Reusable option widget
  Widget _buildOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: ListTile(
        leading: Icon(icon, color: Color(0xFF6C63FF)),
        title: Text(title),
        trailing: Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}
