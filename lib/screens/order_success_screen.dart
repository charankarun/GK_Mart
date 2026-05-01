import 'package:flutter/material.dart';
import 'orders_screen.dart';
//import 'home_screen.dart';
import '../main.dart'; // or correct path

class OrderSuccessScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              Icon(
                Icons.check_circle,
                color: Color(0xFF6C63FF),
                size: 100,
              ),

              SizedBox(height: 20),

              Text(
                "Order Placed Successfully 🎉",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              SizedBox(height: 10),

              Text(
                "Your order will be delivered soon",
                style: TextStyle(color: Colors.grey),
              ),

              SizedBox(height: 30),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF6C63FF),
                  minimumSize: Size(double.infinity, 50),
                ),
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => OrdersScreen()),
                    (route) => false,
                  );
                },
                child: Text("View Orders"),
              ),

              SizedBox(height: 10),

              TextButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => MainScreen()),
                    (route) => false,
                  );
                },
                child: Text("Continue Shopping"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}