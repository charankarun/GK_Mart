import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user_role.dart';
import '../../domain/entities/user_status.dart';
import 'auth_providers.dart';

class UserPermissions {
  final UserRole role;
  final UserStatus status;

  UserPermissions(this.role, this.status);

  bool get isSuspended => status == UserStatus.suspended;

  // Shopping features
  bool get canPlaceOrders => !isSuspended;
  bool get canCheckout => !isSuspended;

  // Admin/Owner permissions (must not be suspended)
  bool get isAdministrative => !isSuspended && (role == UserRole.owner || role == UserRole.admin);
  bool get canManageProducts => isAdministrative;
  bool get canManageInventory => isAdministrative;
  bool get canManageCategories => isAdministrative;
  bool get canManageOrders => isAdministrative;
  bool get canManageNotifications => isAdministrative;

  // Owner-only permissions
  bool get canManageUsers => !isSuspended && role == UserRole.owner;
  bool get canManageStoreSettings => !isSuspended && role == UserRole.owner;
  bool get canViewAnalytics => !isSuspended && role == UserRole.owner;
  
  bool get isOwner => !isSuspended && role == UserRole.owner;
  bool get isAdmin => !isSuspended && role == UserRole.admin;
  bool get isCustomer => role == UserRole.customer || isSuspended;
}

final currentUserRoleProvider = Provider<UserRole>((ref) {
  final userProfile = ref.watch(currentUserProfileProvider).value;
  if (userProfile == null) return UserRole.customer;
  return userProfile.role;
});

final currentUserStatusProvider = Provider<UserStatus>((ref) {
  final userProfile = ref.watch(currentUserProfileProvider).value;
  if (userProfile == null) return UserStatus.active;
  return userProfile.status;
});

final userPermissionsProvider = Provider<UserPermissions>((ref) {
  final role = ref.watch(currentUserRoleProvider);
  final status = ref.watch(currentUserStatusProvider);
  return UserPermissions(role, status);
});
