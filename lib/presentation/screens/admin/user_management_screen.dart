import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/errors/app_error_handler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/app_user.dart';
import '../../../domain/entities/user_role.dart';
import '../../../services/rbac_migration_service.dart';
import '../../providers/auth_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/role_provider.dart';
import '../../widgets/app_state_widgets.dart';
import 'access_denied_screen.dart';

final userSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');
final userRoleFilterProvider = StateProvider.autoDispose<UserRole?>((ref) => null);

final usersStreamProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  final query = ref.watch(userSearchQueryProvider);
  final roleFilter = ref.watch(userRoleFilterProvider);
  return ref.watch(userRepositoryProvider).watchUsers(
        searchQuery: query,
        filterRole: roleFilter,
        limit: 100,
      );
});

class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(userPermissionsProvider);
    if (!permissions.canManageUsers) {
      return const AccessDeniedScreen();
    }

    final usersAsync = ref.watch(usersStreamProvider);
    final currentUid = ref.watch(currentSessionProvider)?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('User Management'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Normalize Legacy Users',
            onPressed: () => _runMigration(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          const _FilterBar(),
          Expanded(
            child: usersAsync.when(
              data: (users) {
                if (users.isEmpty) {
                  return const _EmptyUsersState();
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final isSelf = user.uid == currentUid;
                    return _UserCard(user: user, isSelf: isSelf);
                  },
                );
              },
              loading: () => const AppLoadingState(),
              error: (error, stack) => AppRetryState(
                icon: Icons.error_outline_rounded,
                title: 'Unable to load users',
                message: AppErrorHandler.messageFor(error),
                onRetry: () => ref.invalidate(usersStreamProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runMigration(BuildContext context, WidgetRef ref) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Normalizing legacy user profiles...')),
            ],
          ),
        );
      },
    );

    try {
      final updated = await ref.read(rbacMigrationServiceProvider).runLegacyMigration();
      if (context.mounted) {
        Navigator.of(context).pop(); // pop loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Migration complete! Normalized $updated users.'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // pop loading
        AppErrorHandler.showErrorSnackBar(
          context,
          e,
          fallbackMessage: 'Migration failed',
        );
      }
    }
  }

}

class _FilterBar extends ConsumerStatefulWidget {
  const _FilterBar();

  @override
  ConsumerState<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<_FilterBar> {
  late final TextEditingController _searchController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: ref.read(userSearchQueryProvider));
    _focusNode = FocusNode();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(userSearchQueryProvider, (previous, next) {
      if (_searchController.text != next) {
        _searchController.text = next;
      }
    });

    final currentFilter = ref.watch(userRoleFilterProvider);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            focusNode: _focusNode,
            onChanged: (val) => ref.read(userSearchQueryProvider.notifier).state = val,
            decoration: InputDecoration(
              hintText: 'Search by name or phone number...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(userSearchQueryProvider.notifier).state = '';
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Filter Role:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.mutedText),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: currentFilter == null,
                        onSelected: () => ref.read(userRoleFilterProvider.notifier).state = null,
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Owner',
                        selected: currentFilter == UserRole.owner,
                        onSelected: () => ref.read(userRoleFilterProvider.notifier).state = UserRole.owner,
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Admin',
                        selected: currentFilter == UserRole.admin,
                        onSelected: () => ref.read(userRoleFilterProvider.notifier).state = UserRole.admin,
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Customer',
                        selected: currentFilter == UserRole.customer,
                        onSelected: () => ref.read(userRoleFilterProvider.notifier).state = UserRole.customer,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.softGreen,
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.mutedText,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? AppColors.primary.withValues(alpha: 0.3) : Colors.transparent,
        ),
      ),
      showCheckmark: false,
    );
  }
}

class _UserCard extends ConsumerWidget {
  const _UserCard({
    required this.user,
    required this.isSelf,
  });

  final AppUser user;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfUid = ref.watch(currentSessionProvider)?.uid ?? '';
    final roleColor = _getRoleColor(user.role);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.softGreen,
                child: Text(
                  user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : 'U',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName + (isSelf ? ' (You)' : ''),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                    if (user.phone.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        user.phone,
                        style: const TextStyle(color: AppColors.mutedText, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  user.role.name.toUpperCase(),
                  style: TextStyle(
                    color: roleColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: AppColors.border),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Joined: ${_formatDate(user.createdAt)}',
                style: const TextStyle(color: AppColors.mutedText, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              if (!isSelf) ...[
                DropdownButtonHideUnderline(
                  child: DropdownButton<UserRole>(
                    value: user.role,
                    icon: const Icon(Icons.arrow_drop_down_rounded, color: AppColors.primary),
                    onChanged: (UserRole? newRole) {
                      if (newRole != null && newRole != user.role) {
                        _showRoleConfirmDialog(context, ref, newRole, selfUid);
                      }
                    },
                    items: _buildDropdownItems(user.role),
                  ),
                ),
              ] else ...[
                const Text(
                  'Cannot Demote Self',
                  style: TextStyle(color: AppColors.mutedText, fontSize: 12, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  List<DropdownMenuItem<UserRole>> _buildDropdownItems(UserRole currentRole) {
    switch (currentRole) {
      case UserRole.customer:
        return [
          const DropdownMenuItem(
            value: UserRole.customer,
            child: Text('Customer', style: TextStyle(fontSize: 13, color: AppColors.mutedText)),
          ),
          const DropdownMenuItem(
            value: UserRole.admin,
            child: Text('Promote to Admin', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          const DropdownMenuItem(
            value: UserRole.owner,
            child: Text('Promote to Owner', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ];
      case UserRole.admin:
        return [
          const DropdownMenuItem(
            value: UserRole.admin,
            child: Text('Admin', style: TextStyle(fontSize: 13, color: AppColors.mutedText)),
          ),
          const DropdownMenuItem(
            value: UserRole.customer,
            child: Text('Demote to Customer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          const DropdownMenuItem(
            value: UserRole.owner,
            child: Text('Promote to Owner', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ];
      case UserRole.owner:
        return [
          const DropdownMenuItem(
            value: UserRole.owner,
            child: Text('Owner', style: TextStyle(fontSize: 13, color: AppColors.mutedText)),
          ),
          const DropdownMenuItem(
            value: UserRole.admin,
            child: Text('Demote to Admin', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          const DropdownMenuItem(
            value: UserRole.customer,
            child: Text('Demote to Customer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ];
    }
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return AppColors.danger;
      case UserRole.admin:
        return AppColors.accent;
      case UserRole.customer:
        return AppColors.primary;
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '--/--/----';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  void _showRoleConfirmDialog(BuildContext context, WidgetRef ref, UserRole targetRole, String selfUid) {
    final roleName = targetRole.name.toUpperCase();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Confirm Role Change'),
          content: Text(
            'Are you sure you want to change the role of ${user.displayName} to $roleName?\n\n'
            'This action will be recorded in the audit trail.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await ref.read(userRepositoryProvider).updateUserRole(
                        uid: user.uid,
                        role: targetRole,
                        updatedBy: selfUid,
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Successfully updated role for ${user.displayName}!'),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    AppErrorHandler.showErrorSnackBar(
                      context,
                      e,
                      fallbackMessage: 'Failed to update role',
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyUsersState extends StatelessWidget {
  const _EmptyUsersState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(color: AppColors.softOrange, shape: BoxShape.circle),
            child: const Icon(Icons.people_alt_outlined, color: AppColors.accent, size: 36),
          ),
          const SizedBox(height: 16),
          const Text('No users found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          const Text('Try adjusting your search or filters.', style: TextStyle(color: AppColors.mutedText, fontSize: 14)),
        ],
      ),
    );
  }
}
