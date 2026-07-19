// ==============================================================================
// FILE: lib/services/rbac_migration_service.dart
// PURPOSE: Administrative helper to migrate legacy user profiles to newer RBAC structures.
// LAYER: Business / Maintenance Services
// DEPENDENCIES: cloud_firestore, userPermissionsProvider
//
// ARCHITECTURAL ROLE:
// Provides batch data migration routines. Upgrades user schema configurations
// to ensure every customer profile holds valid roles and active status descriptors.
// Restricts execution access strictly to authenticated Owner UIDs.
// ==============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/user_role.dart';
import '../domain/entities/user_status.dart';
import '../presentation/providers/role_provider.dart';

/// Provider for RbacMigrationService.
final rbacMigrationServiceProvider = Provider<RbacMigrationService>((ref) {
  return RbacMigrationService(ref);
});

/// Service providing batch migrations for roles/status settings.
class RbacMigrationService {
  final Ref _ref;

  RbacMigrationService(this._ref);

  Future<int> runLegacyMigration() async {
    final permissions = _ref.read(userPermissionsProvider);
    if (!permissions.canManageUsers) {
      throw StateError('Access denied. Only Owners can run the migration.');
    }

    final firestore = FirebaseFirestore.instance;
    final usersSnapshot = await firestore.collection('users').get();
    
    var batch = firestore.batch();
    int updatedCount = 0;
    int batchSize = 0;
    
    for (final doc in usersSnapshot.docs) {
      final data = doc.data();
      final currentRole = data['role']?.toString().trim();
      final currentStatus = data['status']?.toString().trim();
      
      bool needsUpdate = false;
      final updates = <String, dynamic>{};
      
      if (currentRole == null || currentRole.isEmpty) {
        updates['role'] = UserRole.customer.toJson();
        needsUpdate = true;
      }
      
      if (currentStatus == null || currentStatus.isEmpty) {
        updates['status'] = UserStatus.active.toJson();
        needsUpdate = true;
      }
      
      if (needsUpdate) {
        updates['updatedAt'] = FieldValue.serverTimestamp();
        batch.update(doc.reference, updates);
        updatedCount++;
        batchSize++;
        
        if (batchSize >= 400) {
          await batch.commit();
          batch = firestore.batch();
          batchSize = 0;
        }
      }
    }
    
    if (batchSize > 0) {
      await batch.commit();
    }
    
    return updatedCount;
  }
}
