import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/app_bottom_nav_icon.dart';
import 'admin/admin_category_screen.dart';
import 'admin/admin_dashboard_screen.dart';
import 'admin/admin_inventory_screen.dart';
import 'admin/admin_orders_screen.dart';
import 'account_screen.dart';

class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int selectedIndex = 0;

  final screens = const [
    AdminDashboardScreen(),
    AdminOrdersScreen(),
    AdminInventoryScreen(),
    AdminCategoryScreen(),
    AccountPage(),
  ];

  void onItemTapped(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: screens[selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: const Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: selectedIndex,
          onTap: onItemTapped,
          items: const [
            BottomNavigationBarItem(
              icon: AppBottomNavIcon(
                icon: Icons.dashboard_rounded,
                selected: false,
              ),
              activeIcon: AppBottomNavIcon(
                icon: Icons.dashboard_rounded,
                selected: true,
              ),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: AppBottomNavIcon(
                icon: Icons.receipt_long_rounded,
                selected: false,
              ),
              activeIcon: AppBottomNavIcon(
                icon: Icons.receipt_long_rounded,
                selected: true,
              ),
              label: 'Orders',
            ),
            BottomNavigationBarItem(
              icon: AppBottomNavIcon(
                icon: Icons.inventory_2_rounded,
                selected: false,
              ),
              activeIcon: AppBottomNavIcon(
                icon: Icons.inventory_2_rounded,
                selected: true,
              ),
              label: 'Inventory',
            ),
            BottomNavigationBarItem(
              icon: AppBottomNavIcon(
                icon: Icons.category_rounded,
                selected: false,
              ),
              activeIcon: AppBottomNavIcon(
                icon: Icons.category_rounded,
                selected: true,
              ),
              label: 'Categories',
            ),
            BottomNavigationBarItem(
              icon: AppBottomNavIcon(
                icon: Icons.person_outline_rounded,
                selected: false,
              ),
              activeIcon: AppBottomNavIcon(
                icon: Icons.person_rounded,
                selected: true,
              ),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}
