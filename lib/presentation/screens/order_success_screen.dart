import 'package:flutter/material.dart';

import '../navigation/customer_navigation_scope.dart';

class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle,
                color: Color(0xFF6C63FF),
                size: 100,
              ),
              const SizedBox(height: 20),
              const Text(
                'Order Placed Successfully',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your order will be delivered soon',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () {
                  CustomerNavigationScope.openOrders(context);
                },
                child: const Text('View Orders'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  CustomerNavigationScope.openHome(context);
                },
                child: const Text('Continue Shopping'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
