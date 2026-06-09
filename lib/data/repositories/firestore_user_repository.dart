import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/repository_exception.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/user_role.dart';
import '../../domain/entities/user_status.dart';
import '../../domain/repositories/user_repository.dart';
import '../mappers/firestore_value_parser.dart';

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users {
    return _firestore.collection(FirestoreCollections.users);
  }

  @override
  Stream<AppUser?> watchUser(String uid) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return Stream.value(null);

    return RepositoryGuard.watch(
      message: 'Unable to load profile.',
      create: () => _users.doc(normalizedUid).snapshots().map(_fromDocument),
    );
  }

  @override
  Future<AppUser?> getUser(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return null;

    return RepositoryGuard.run(
      message: 'Unable to load profile.',
      action: () async {
        final doc = await _users.doc(normalizedUid).get().timeout(
              AppDurations.networkTimeout,
            );
        return _fromDocument(doc);
      },
    );
  }

  @override
  Future<void> upsertUser(AppUser user) async {
    final normalizedUid = user.uid.trim();
    if (normalizedUid.isEmpty) {
      throw ArgumentError.value(user.uid, 'user.uid', 'Required');
    }

    return RepositoryGuard.run(
      message: 'Unable to save profile.',
      action: () async {
        final doc = await _users.doc(normalizedUid).get().timeout(
              AppDurations.networkTimeout,
            );

        if (!doc.exists) {
          // New User: initialize role and status
          return _users.doc(normalizedUid).set({
            'name': user.name,
            'email': user.email,
            'phone': user.phone,
            if (user.address.isNotEmpty) 'address': user.address,
            if (user.addresses.isNotEmpty) 'addresses': user.addresses,
            if (user.photoUrl.isNotEmpty) 'photoUrl': user.photoUrl,
            'role': UserRole.customer.toJson(),
            'status': UserStatus.active.toJson(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }).timeout(AppDurations.networkTimeout);
        } else {
          // Existing User: only update profile fields, do not overwrite role/status
          return _users.doc(normalizedUid).set({
            'name': user.name,
            'email': user.email,
            'phone': user.phone,
            if (user.address.isNotEmpty) 'address': user.address,
            if (user.addresses.isNotEmpty) 'addresses': user.addresses,
            if (user.photoUrl.isNotEmpty) 'photoUrl': user.photoUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).timeout(AppDurations.networkTimeout);
        }
      },
    );
  }

  @override
  Future<void> updateProfile({
    required String uid,
    required String name,
    required String phone,
  }) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Required');
    }

    return RepositoryGuard.run(
      message: 'Unable to update profile.',
      action: () {
        return _users.doc(normalizedUid).set({
          'name': name.trim(),
          'phone': phone.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(AppDurations.networkTimeout);
      },
    );
  }

  @override
  Future<void> updateAddress({
    required String uid,
    required String address,
  }) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Required');
    }

    return RepositoryGuard.run(
      message: 'Unable to update address.',
      action: () {
        return _users.doc(normalizedUid).set({
          'address': address.trim(),
          'addresses':
              address.trim().isEmpty ? <String>[] : <String>[address.trim()],
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(AppDurations.networkTimeout);
      },
    );
  }

  @override
  Stream<List<AppUser>> watchUsers({
    int? limit,
    String? searchQuery,
    UserRole? filterRole,
  }) {
    return RepositoryGuard.watch(
      message: 'Unable to load users.',
      create: () {
        Query<Map<String, dynamic>> query = _users;

        if (filterRole != null) {
          query = query.where('role', isEqualTo: filterRole.toJson());
        }

        return query.snapshots().map((snapshot) {
          var users = snapshot.docs
              .map(_fromDocument)
              .whereType<AppUser>()
              .toList();

          if (searchQuery != null && searchQuery.trim().isNotEmpty) {
            final queryLower = searchQuery.trim().toLowerCase();
            users = users.where((user) {
              final nameMatch = user.name.toLowerCase().contains(queryLower);
              final phoneMatch = user.phone.contains(queryLower);
              return nameMatch || phoneMatch;
            }).toList();
          }

          if (limit != null && users.length > limit) {
            users = users.sublist(0, limit);
          }

          return users;
        });
      },
    );
  }

  @override
  Future<void> updateUserRole({
    required String uid,
    required UserRole role,
    required String updatedBy,
  }) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Required');
    }

    return RepositoryGuard.run(
      message: 'Unable to update user role.',
      action: () {
        return _users.doc(normalizedUid).update({
          'role': role.toJson(),
          'roleUpdatedAt': FieldValue.serverTimestamp(),
          'roleUpdatedBy': updatedBy,
          'updatedAt': FieldValue.serverTimestamp(),
        }).timeout(AppDurations.networkTimeout);
      },
    );
  }

  AppUser? _fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (!doc.exists || data == null) return null;

    final address = readString(data, 'address');
    final addresses = readStringList(data['addresses']);

    return AppUser(
      uid: doc.id,
      name: readString(data, 'name'),
      email: readString(data, 'email'),
      phone: readString(data, 'phone'),
      address: address,
      addresses: addresses.isEmpty && address.isNotEmpty
          ? <String>[address]
          : addresses,
      photoUrl: readString(data, 'photoUrl'),
      createdAt: readDateTime(data['createdAt']),
      updatedAt: readDateTime(data['updatedAt']),
      role: UserRole.fromString(readString(data, 'role')),
      roleUpdatedAt: readDateTime(data['roleUpdatedAt']),
      roleUpdatedBy: readString(data, 'roleUpdatedBy'),
      status: UserStatus.fromString(readString(data, 'status')),
    );
  }
}
