import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../providers/role_provider.dart';
import '../widgets/app_bottom_nav_icon.dart';
import 'admin/admin_category_screen.dart';
import 'admin/admin_dashboard_screen.dart';
import 'admin/admin_inventory_screen.dart';
import 'admin/admin_orders_screen.dart';
import 'account_screen.dart';

class AdminShellScreen extends ConsumerStatefulWidget {
  const AdminShellScreen({super.key});

  @override
  ConsumerState<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends ConsumerState<AdminShellScreen> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(userPermissionsProvider);

    final screens = <Widget>[];
    final items = <BottomNavigationBarItem>[];

    if (permissions.canViewAnalytics) {
      screens.add(const AdminDashboardScreen());
      items.add(const BottomNavigationBarItem(
        icon: AppBottomNavIcon(
          icon: Icons.dashboard_rounded,
          selected: false,
        ),
        activeIcon: AppBottomNavIcon(
          icon: Icons.dashboard_rounded,
          selected: true,
        ),
        label: 'Dashboard',
      ));
    }

    if (permissions.canManageOrders) {
      screens.add(const AdminOrdersScreen());
      items.add(const BottomNavigationBarItem(
        icon: AppBottomNavIcon(
          icon: Icons.receipt_long_rounded,
          selected: false,
        ),
        activeIcon: AppBottomNavIcon(
          icon: Icons.receipt_long_rounded,
          selected: true,
        ),
        label: 'Orders',
      ));
    }

    if (permissions.canManageInventory) {
      screens.add(const AdminInventoryScreen());
      items.add(const BottomNavigationBarItem(
        icon: AppBottomNavIcon(
          icon: Icons.inventory_2_rounded,
          selected: false,
        ),
        activeIcon: AppBottomNavIcon(
          icon: Icons.inventory_2_rounded,
          selected: true,
        ),
        label: 'Inventory',
      ));
    }

    if (permissions.canManageCategories) {
      screens.add(const AdminCategoryScreen());
      items.add(const BottomNavigationBarItem(
        icon: AppBottomNavIcon(
          icon: Icons.category_rounded,
          selected: false,
        ),
        activeIcon: AppBottomNavIcon(
          icon: Icons.category_rounded,
          selected: true,
        ),
        label: 'Categories',
      ));
    }

    // Always add Account screen as the final navigation tab
    screens.add(const AccountPage());
    items.add(const BottomNavigationBarItem(
      icon: AppBottomNavIcon(
        icon: Icons.person_outline_rounded,
        selected: false,
      ),
      activeIcon: AppBottomNavIcon(
        icon: Icons.person_rounded,
        selected: true,
      ),
      label: 'Account',
    ));

    if (selectedIndex >= screens.length) {
      selectedIndex = screens.length - 1;
    }

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
          onTap: (index) {
            setState(() {
              selectedIndex = index;
            });
          },
          items: items,
        ),
      ),
    );
  }
}
