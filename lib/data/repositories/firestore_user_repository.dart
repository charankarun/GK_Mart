import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/app_user.dart';
import '../../domain/repositories/user_repository.dart';
import '../mappers/firestore_value_parser.dart';

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users {
    return _firestore.collection('users');
  }

  @override
  Stream<AppUser?> watchUser(String uid) {
    return _users.doc(uid).snapshots().map(_fromDocument);
  }

  @override
  Future<AppUser?> getUser(String uid) async {
    final doc = await _users.doc(uid).get();
    return _fromDocument(doc);
  }

  @override
  Future<void> upsertUser(AppUser user) {
    return _users.doc(user.uid).set({
      'name': user.name,
      'email': user.email,
      'phone': user.phone,
      if (user.address.isNotEmpty) 'address': user.address,
      'createdAt': user.createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> updateProfile({
    required String uid,
    required String name,
    required String phone,
  }) {
    return _users.doc(uid).set({
      'name': name.trim(),
      'phone': phone.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> updateAddress({
    required String uid,
    required String address,
  }) {
    return _users.doc(uid).set({
      'address': address.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  AppUser? _fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (!doc.exists || data == null) return null;

    return AppUser(
      uid: doc.id,
      name: readString(data, 'name'),
      email: readString(data, 'email'),
      phone: readString(data, 'phone'),
      address: readString(data, 'address'),
      createdAt: readDateTime(data['createdAt']),
      updatedAt: readDateTime(data['updatedAt']),
    );
  }
}
