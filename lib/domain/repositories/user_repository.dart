import '../entities/app_user.dart';
import '../entities/user_role.dart';

abstract class UserRepository {
  Stream<AppUser?> watchUser(String uid);

  Future<AppUser?> getUser(String uid);

  Future<void> upsertUser(AppUser user);

  Future<void> updateProfile({
    required String uid,
    required String name,
    required String phone,
  });

  Future<void> updateAddress({
    required String uid,
    required String address,
  });

  Stream<List<AppUser>> watchUsers({
    int? limit,
    String? searchQuery,
    UserRole? filterRole,
  });

  Future<void> updateUserRole({
    required String uid,
    required UserRole role,
    required String updatedBy,
  });
}

