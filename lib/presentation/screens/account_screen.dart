import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/admin_mode_provider.dart';
import '../providers/auth_providers.dart';
import '../providers/repository_providers.dart';
import 'address_screen.dart';
import 'admin/admin_category_screen.dart';
import 'admin/admin_inventory_screen.dart';
import 'admin/admin_orders_screen.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';
import 'orders_screen.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Account')),
        body: const Center(child: Text('Please login to view your account')),
      );
    }

    final userAsync = ref.watch(currentUserProfileProvider);
    final isAdmin = ref.watch(isAdminProvider).maybeWhen(
          data: (value) => value,
          orElse: () => false,
        );
    final adminMode = ref.watch(adminModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Account')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(color: Colors.grey.shade200, blurRadius: 5),
                ],
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Color(0xFF6C63FF),
                    child: Icon(Icons.person, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: userAsync.when(
                      data: (user) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? 'User',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              user?.email.isNotEmpty == true
                                  ? user!.email
                                  : session.email ?? session.phoneNumber ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        );
                      },
                      loading: () => const Text(
                        'Loading...',
                        style: TextStyle(fontSize: 16),
                      ),
                      error: (_, __) => const Text('No data'),
                    ),
                  ),
                ],
              ),
            ),
            if (isAdmin)
              _buildAdminModeToggle(
                value: adminMode,
                onChanged: (value) {
                  ref.read(adminModeProvider.notifier).setEnabled(value);
                },
              ),
            _buildOption(
              icon: Icons.edit,
              title: 'Edit Profile',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                );
              },
            ),
            _buildOption(
              icon: Icons.shopping_bag,
              title: 'My Orders',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OrdersScreen()),
                );
              },
            ),
            _buildOption(
              icon: Icons.location_on,
              title: 'My Address',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddressScreen()),
                );
              },
            ),
            _buildOption(
              icon: Icons.support_agent,
              title: 'Customer Support',
              onTap: () {},
            ),
            _buildOption(
              icon: Icons.lock_reset,
              title: 'Reset Password',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                );
              },
            ),
            if (isAdmin)
              _buildOption(
                icon: Icons.inventory_2,
                title: 'Manage Products',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminInventoryScreen(),
                    ),
                  );
                },
              ),
            if (isAdmin)
              _buildOption(
                icon: Icons.category,
                title: 'Manage Categories',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminCategoryScreen(),
                    ),
                  );
                },
              ),
            if (isAdmin)
              _buildOption(
                icon: Icons.admin_panel_settings,
                title: 'Admin Panel',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminOrdersScreen(),
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () async {
                  ref.read(adminModeProvider.notifier).disable();
                  await ref.read(authRepositoryProvider).signOut();
                },
                child: const Text('Sign out'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF6C63FF)),
        title: Text(title),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  Widget _buildAdminModeToggle({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: SwitchListTile(
        secondary: const Icon(
          Icons.admin_panel_settings,
          color: Color(0xFF6C63FF),
        ),
        title: const Text('Admin Mode'),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
