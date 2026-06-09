import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supermarket_app/domain/entities/app_user.dart';
import 'package:supermarket_app/domain/entities/user_role.dart';
import 'package:supermarket_app/domain/entities/user_status.dart';
import 'package:supermarket_app/presentation/providers/auth_providers.dart';
import 'package:supermarket_app/presentation/providers/role_provider.dart';

void main() {
  group('RBAC Enums and Mappers Unit Tests', () {
    test('UserRole parsing from string is correct and case-insensitive', () {
      expect(UserRole.fromString('owner'), UserRole.owner);
      expect(UserRole.fromString('OWNER '), UserRole.owner);
      expect(UserRole.fromString('admin'), UserRole.admin);
      expect(UserRole.fromString('ADMIN'), UserRole.admin);
      expect(UserRole.fromString('customer'), UserRole.customer);
      expect(UserRole.fromString('invalid_role'), UserRole.customer);
      expect(UserRole.fromString(null), UserRole.customer);
    });

    test('UserStatus parsing from string is correct and case-insensitive', () {
      expect(UserStatus.fromString('active'), UserStatus.active);
      expect(UserStatus.fromString('ACTIVE '), UserStatus.active);
      expect(UserStatus.fromString('suspended'), UserStatus.suspended);
      expect(UserStatus.fromString('SUSPENDED'), UserStatus.suspended);
      expect(UserStatus.fromString('invalid_status'), UserStatus.active);
      expect(UserStatus.fromString(null), UserStatus.active);
    });
  });

  group('UserPermissions Logic Tests', () {
    test('Suspended user is blocked from all active tasks regardless of role', () {
      final suspendedOwner = UserPermissions(UserRole.owner, UserStatus.suspended);
      final suspendedAdmin = UserPermissions(UserRole.admin, UserStatus.suspended);
      final suspendedCustomer = UserPermissions(UserRole.customer, UserStatus.suspended);

      for (final perm in [suspendedOwner, suspendedAdmin, suspendedCustomer]) {
        expect(perm.isSuspended, isTrue);
        expect(perm.canPlaceOrders, isFalse);
        expect(perm.canCheckout, isFalse);
        expect(perm.isAdministrative, isFalse);
        expect(perm.canManageProducts, isFalse);
        expect(perm.canManageInventory, isFalse);
        expect(perm.canManageCategories, isFalse);
        expect(perm.canManageOrders, isFalse);
        expect(perm.canManageNotifications, isFalse);
        expect(perm.canManageUsers, isFalse);
        expect(perm.canManageStoreSettings, isFalse);
        expect(perm.canViewAnalytics, isFalse);
        expect(perm.isOwner, isFalse);
        expect(perm.isAdmin, isFalse);
        expect(perm.isCustomer, isTrue); // Suspended behaves as customer (restricted)
      }
    });

    test('Customer role permissions are restricted to shopping features only', () {
      final customer = UserPermissions(UserRole.customer, UserStatus.active);

      expect(customer.canPlaceOrders, isTrue);
      expect(customer.canCheckout, isTrue);
      expect(customer.isAdministrative, isFalse);
      expect(customer.canManageProducts, isFalse);
      expect(customer.canManageInventory, isFalse);
      expect(customer.canManageCategories, isFalse);
      expect(customer.canManageOrders, isFalse);
      expect(customer.canManageNotifications, isFalse);
      expect(customer.canManageUsers, isFalse);
      expect(customer.canManageStoreSettings, isFalse);
      expect(customer.canViewAnalytics, isFalse);
      expect(ownerMatchesAdmin(customer), isFalse);
    });

    test('Admin role permissions are restricted to operations, blocked from owner features', () {
      final admin = UserPermissions(UserRole.admin, UserStatus.active);

      expect(admin.canPlaceOrders, isTrue);
      expect(admin.canCheckout, isTrue);
      expect(admin.isAdministrative, isTrue);
      expect(admin.canManageProducts, isTrue);
      expect(admin.canManageInventory, isTrue);
      expect(admin.canManageCategories, isTrue);
      expect(admin.canManageOrders, isTrue);
      expect(admin.canManageNotifications, isTrue);

      // Blocked owner features
      expect(admin.canManageUsers, isFalse);
      expect(admin.canManageStoreSettings, isFalse);
      expect(admin.canViewAnalytics, isFalse);
      expect(admin.isOwner, isFalse);
      expect(admin.isAdmin, isTrue);
      expect(admin.isCustomer, isFalse);
    });

    test('Owner role permissions have full access to everything', () {
      final owner = UserPermissions(UserRole.owner, UserStatus.active);

      expect(owner.canPlaceOrders, isTrue);
      expect(owner.canCheckout, isTrue);
      expect(owner.isAdministrative, isTrue);
      expect(owner.canManageProducts, isTrue);
      expect(owner.canManageInventory, isTrue);
      expect(owner.canManageCategories, isTrue);
      expect(owner.canManageOrders, isTrue);
      expect(owner.canManageNotifications, isTrue);
      expect(owner.canManageUsers, isTrue);
      expect(owner.canManageStoreSettings, isTrue);
      expect(owner.canViewAnalytics, isTrue);
      expect(owner.isOwner, isTrue);
      expect(owner.isAdmin, isFalse);
      expect(owner.isCustomer, isFalse);
    });
  });

  group('Provider Layer Permission Verification Tests', () {
    test('currentUserRoleProvider defaults to customer if user profile is null', () {
      final container = ProviderContainer(
        overrides: [
          currentUserProfileProvider.overrideWithValue(const AsyncValue<AppUser?>.data(null)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentUserRoleProvider), UserRole.customer);
      expect(container.read(currentUserStatusProvider), UserStatus.active);
      
      final permissions = container.read(userPermissionsProvider);
      expect(permissions.isCustomer, isTrue);
      expect(permissions.isAdministrative, isFalse);
    });

    test('userPermissionsProvider reflects active profile role and status', () {
      const user = AppUser(
        uid: 'user-123',
        name: 'John Doe',
        role: UserRole.admin,
        status: UserStatus.active,
      );

      final container = ProviderContainer(
        overrides: [
          currentUserProfileProvider.overrideWithValue(const AsyncValue<AppUser?>.data(user)),
        ],
      );
      addTearDown(container.dispose);

      final permissions = container.read(userPermissionsProvider);
      expect(permissions.isAdmin, isTrue);
      expect(permissions.isAdministrative, isTrue);
      expect(permissions.canManageProducts, isTrue);
      expect(permissions.canManageUsers, isFalse);
    });
  });
}

bool ownerMatchesAdmin(UserPermissions perm) {
  return perm.isOwner && perm.isAdmin;
}
