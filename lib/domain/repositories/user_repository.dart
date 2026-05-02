import '../entities/app_user.dart';

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
}
