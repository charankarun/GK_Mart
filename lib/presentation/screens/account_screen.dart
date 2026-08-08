import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/errors/app_error_handler.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/app_user.dart';
import '../providers/admin_mode_provider.dart';
import '../providers/auth_providers.dart';
import '../providers/repository_providers.dart';
import '../providers/role_provider.dart';
import '../widgets/app_cached_network_image.dart';
import '../widgets/customer_support_sheet.dart';
import 'address_screen.dart';
import 'admin/admin_category_screen.dart';
import 'admin/admin_inventory_screen.dart';
import 'admin/admin_orders_screen.dart';
import 'admin/store_settings_screen.dart';
import 'admin/user_management_screen.dart';
import 'edit_profile_screen.dart';
import 'orders_screen.dart';

final _signOutLoadingProvider = StateProvider.autoDispose<bool>((ref) {
  return false;
});

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(AccountText.title)),
        body: const Center(child: Text(AccountText.loginRequired)),
      );
    }

    final userAsync = ref.watch(currentUserProfileProvider);
    final permissions = ref.watch(userPermissionsProvider);
    final isAdmin = permissions.isAdministrative;
    final adminMode = ref.watch(adminModeProvider);
    final isSigningOut = ref.watch(_signOutLoadingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AccountText.title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          userAsync.when(
            data: (user) {
              return _ProfileCard(
                user: user,
                fallbackEmail: session.email ?? '',
                fallbackPhone: session.phoneNumber ?? '',
              );
            },
            loading: () => const _LoadingCard(label: AccountText.loading),
            error: (_, __) => const _LoadingCard(label: AccountText.noData),
          ),
          const SizedBox(height: 14),
          userAsync.when(
            data: (user) {
              return _AddressSummaryCard(
                addresses: user?.savedAddresses ?? const <String>[],
                onTap: () => _openAddress(context),
              );
            },
            loading: () => const _LoadingCard(label: AccountText.loading),
            error: (_, __) => _AddressSummaryCard(
              addresses: const <String>[],
              onTap: () => _openAddress(context),
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 14),
            _AdminModeCard(
              value: adminMode,
              onChanged: (value) {
                ref.read(adminModeProvider.notifier).setEnabled(value);
              },
            ),
          ],
          const SizedBox(height: 14),
          _AccountOption(
            icon: Icons.edit_outlined,
            title: AccountText.editProfile,
            subtitle: AccountText.editProfileSubtitle,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
          ),
          _AccountOption(
            icon: Icons.shopping_bag_outlined,
            title: AccountText.myOrders,
            subtitle: AccountText.myOrdersSubtitle,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrdersScreen()),
              );
            },
          ),
          _AccountOption(
            icon: Icons.location_on_outlined,
            title: AccountText.myAddress,
            subtitle: AccountText.myAddressSubtitle,
            onTap: () => _openAddress(context),
          ),
          _AccountOption(
            icon: Icons.support_agent_rounded,
            title: AccountText.customerSupport,
            subtitle: CustomerSupportText.phone,
            onTap: () => showCustomerSupportSheet(context),
          ),

          if (permissions.isAdministrative) ...[
            const SizedBox(height: 8),
            _SectionLabel(label: AccountText.adminTools),
            if (permissions.canManageInventory)
              _AccountOption(
                icon: Icons.inventory_2_outlined,
                title: AccountText.manageProducts,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminInventoryScreen(),
                    ),
                  );
                },
              ),
            if (permissions.canManageCategories)
              _AccountOption(
                icon: Icons.category_outlined,
                title: AccountText.manageCategories,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminCategoryScreen(),
                    ),
                  );
                },
              ),
            if (permissions.canManageOrders)
              _AccountOption(
                icon: Icons.admin_panel_settings_outlined,
                title: AccountText.adminPanel,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminOrdersScreen(),
                    ),
                  );
                },
              ),
            if (permissions.canManageStoreSettings)
              _AccountOption(
                icon: Icons.storefront_outlined,
                title: 'Store Settings',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StoreSettingsScreen(),
                    ),
                  );
                },
              ),
            if (permissions.canManageUsers)
              _AccountOption(
                icon: Icons.people_outline_rounded,
                title: 'User Management',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const UserManagementScreen(),
                    ),
                  );
                },
              ),
          ],

          const SizedBox(height: 18),
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: isSigningOut
                  ? null
                  : () => _signOut(
                        context: context,
                        ref: ref,
                      ),
              icon: isSigningOut
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
              label: Text(
                isSigningOut ? AccountText.signingOut : AccountText.signOut,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openAddress(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddressScreen()),
    );
  }

  Future<void> _signOut({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final loadingNotifier = ref.read(_signOutLoadingProvider.notifier);
    if (loadingNotifier.state) return;

    loadingNotifier.state = true;
    
    // Capture dependencies before any async gap
    final authRepository = ref.read(authRepositoryProvider);
    final adminModeNotifier = ref.read(adminModeProvider.notifier);
    final currentSession = ref.read(currentSessionProvider);

    try {
      adminModeNotifier.disable();
      await NotificationService.instance.unregisterDeviceForUser(
        currentSession?.uid ?? '',
      );
      await authRepository.signOut();
    } catch (error) {
      if (!context.mounted) return;

      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: AccountText.signOutError,
      );
    } finally {
      if (context.mounted) {
        loadingNotifier.state = false;
      }
    }
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.user,
    required this.fallbackEmail,
    required this.fallbackPhone,
  });

  final AppUser? user;
  final String fallbackEmail;
  final String fallbackPhone;

  @override
  Widget build(BuildContext context) {
    final displayName = user?.displayName ?? AccountText.user;
    final phone = user?.phone.trim().isNotEmpty == true
        ? user!.phone.trim()
        : fallbackPhone;

    return _CardSurface(
      child: Row(
        children: [
          _ProfileAvatar(imageUrl: user?.photoUrl ?? ''),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.mutedText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = imageUrl.trim();

    return ClipOval(
      child: SizedBox(
        width: 66,
        height: 66,
        child: AppCachedNetworkImage(
          imageUrl: trimmedUrl,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          memCacheWidth: AccountConfig.avatarImageCacheExtent,
          memCacheHeight: AccountConfig.avatarImageCacheExtent,
          maxWidthDiskCache: AccountConfig.avatarImageDiskCacheExtent,
          maxHeightDiskCache: AccountConfig.avatarImageDiskCacheExtent,
          placeholder: const _ProfileAvatarFallback(),
          errorPlaceholder: const _ProfileAvatarFallback(),
        ),
      ),
    );
  }
}

class _ProfileAvatarFallback extends StatelessWidget {
  const _ProfileAvatarFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: AppColors.softGreen),
      child: Icon(
        Icons.person_rounded,
        color: AppColors.primary,
        size: 34,
      ),
    );
  }
}

class _AddressSummaryCard extends StatelessWidget {
  const _AddressSummaryCard({
    required this.addresses,
    required this.onTap,
  });

  final List<String> addresses;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visibleAddresses = addresses.where((address) {
      return address.trim().isNotEmpty;
    }).toList();
    final primaryAddress =
        visibleAddresses.isEmpty ? '' : visibleAddresses.first.trim();
    final hasAddress = primaryAddress.isNotEmpty;

    return _CardSurface(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: hasAddress ? AppColors.softGreen : AppColors.softOrange,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Icon(
                Icons.location_on_rounded,
                color: hasAddress ? AppColors.primary : AppColors.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    AccountText.savedAddress,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    hasAddress ? primaryAddress : AccountText.noAddressSaved,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          hasAddress ? AppColors.mutedText : AppColors.accent,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (visibleAddresses.length > 1) ...[
                    const SizedBox(height: 7),
                    Text(
                      '${visibleAddresses.length} ${AccountText.addressesSaved}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.mutedText),
          ],
        ),
      ),
    );
  }
}

class _AdminModeCard extends StatelessWidget {
  const _AdminModeCard({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _CardSurface(
      padding: EdgeInsets.zero,
      child: SwitchListTile(
        secondary: const Icon(
          Icons.admin_panel_settings_rounded,
          color: AppColors.primary,
        ),
        title: const Text(
          AccountText.adminMode,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _AccountOption extends StatelessWidget {
  const _AccountOption({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _CardSurface(
        padding: EdgeInsets.zero,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 4,
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.mutedText,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return _CardSurface(
      child: SizedBox(
        height: 54,
        child: Center(child: Text(label)),
      ),
    );
  }
}

class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AccountConfig {
  const AccountConfig._();

  static const avatarImageCacheExtent = 140;
  static const avatarImageDiskCacheExtent = 180;
}

class AccountText {
  const AccountText._();

  static const title = 'My Account';
  static const loginRequired = 'Please login to view your account';
  static const loading = 'Loading...';
  static const noData = 'No data';
  static const user = 'User';
  static const noEmail = 'No email added';
  static const savedAddress = 'Saved Address';
  static const noAddressSaved = 'Add your delivery address';
  static const addressesSaved = 'addresses saved';
  static const adminMode = 'Admin Mode';
  static const editProfile = 'Edit Profile';
  static const editProfileSubtitle = 'Name, mobile number and profile picture';
  static const myOrders = 'My Orders';
  static const myOrdersSubtitle = 'Track status and order summaries';
  static const myAddress = 'My Address';
  static const myAddressSubtitle = 'Add or update delivery addresses';
  static const customerSupport = 'Customer Support';
  static const resetPassword = 'Reset Password';
  static const resetPasswordSubtitle = 'For email-password accounts';
  static const adminTools = 'Admin tools';
  static const manageProducts = 'Manage Products';
  static const manageCategories = 'Manage Categories';
  static const adminPanel = 'Admin Panel';
  static const signOut = 'Sign out';
  static const signingOut = 'Signing out...';
  static const signOutError = 'Unable to sign out';
}
