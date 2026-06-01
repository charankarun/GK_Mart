import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/repository_exception.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/admin_repository.dart';
import '../mappers/firestore_value_parser.dart';

class FirestoreAdminRepository implements AdminRepository {
  FirestoreAdminRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _adminConfigRef {
    return _firestore
        .collection(FirestoreCollections.adminConfig)
        .doc(FirestoreDocuments.admins);
  }

  DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return _firestore.collection(FirestoreCollections.users).doc(uid);
  }

  @override
  Stream<bool> watchIsAdmin(AuthSession session) {
    return RepositoryGuard.watch(
      message: 'Unable to verify admin access.',
      create: () => _watchAdminAccess(session),
    );
  }

  Stream<bool> _watchAdminAccess(AuthSession session) {
    final uid = session.uid.trim();
    if (uid.isEmpty) return Stream.value(false);

    late StreamController<bool> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
        adminConfigSubscription;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
        userProfileSubscription;
    Map<String, dynamic>? adminConfig;
    Map<String, dynamic>? userProfile;
    bool? lastValue;
    bool hasEmittedInitialValue = false;
    Timer? initialLoadTimer;

    void emit() {
      if (controller.isClosed) return;

      final isAdmin = _matchesAdminConfig(session, adminConfig) ||
          _hasAdminRole(userProfile);
      if (lastValue == isAdmin) return;

      lastValue = isAdmin;
      hasEmittedInitialValue = true;
      initialLoadTimer?.cancel();
      controller.add(isAdmin);
    }

    controller = StreamController<bool>(
      onListen: () {
        initialLoadTimer = Timer(AppDurations.dashboardTimeout, () {
          if (hasEmittedInitialValue || controller.isClosed) return;
          controller.addError(
            TimeoutException('Admin access verification timed out.'),
          );
        });

        adminConfigSubscription = _adminConfigRef.snapshots().listen(
          (doc) {
            adminConfig = doc.data();
            emit();
          },
          onError: (_) {
            adminConfig = null;
            emit();
          },
        );

        userProfileSubscription = _userRef(uid).snapshots().listen(
          (doc) {
            userProfile = doc.data();
            emit();
          },
          onError: (_) {
            userProfile = null;
            emit();
          },
        );
      },
      onCancel: () async {
        initialLoadTimer?.cancel();
        await adminConfigSubscription?.cancel();
        await userProfileSubscription?.cancel();
      },
    );

    return controller.stream;
  }

  bool _matchesAdminConfig(
    AuthSession session,
    Map<String, dynamic>? data,
  ) {
    if (data == null || data.isEmpty) return false;

    final adminUids = _adminUids(data);
    final adminEmails = _adminEmails(data);
    final adminPhones = _adminPhones(data);
    final uid = session.uid.trim();
    final email = session.email?.trim().toLowerCase();
    final phone = session.phoneNumber?.trim();

    return (uid.isNotEmpty && adminUids.contains(uid)) ||
        (email != null && adminEmails.contains(email)) ||
        (phone != null && _containsPhone(adminPhones, phone));
  }

  bool _hasAdminRole(Map<String, dynamic>? data) {
    final role = data?['role']?.toString().trim().toLowerCase();
    return role == 'admin' || role == 'owner';
  }

  Set<String> _adminUids(Map<String, dynamic> data) {
    return {
      ...readStringList(data['uids']),
      ...readStringList(data['adminUids']),
      ...readStringList(data['admin_uids']),
    }.map((uid) => uid.trim()).where((uid) {
      return uid.isNotEmpty;
    }).toSet();
  }

  Set<String> _adminEmails(Map<String, dynamic> data) {
    return {
      ...readStringList(data['emails']),
      ...readStringList(data['adminEmails']),
      ...readStringList(data['admin_emails']),
    }.map((email) => email.trim().toLowerCase()).where((email) {
      return email.isNotEmpty;
    }).toSet();
  }

  Set<String> _adminPhones(Map<String, dynamic> data) {
    return {
      ...readStringList(data['phones']),
      ...readStringList(data['adminPhones']),
      ...readStringList(data['admin_phones']),
    }.map(_normalizePhone).where((phone) {
      return phone.isNotEmpty;
    }).toSet();
  }

  bool _containsPhone(Set<String> adminPhones, String phone) {
    final normalized = _normalizePhone(phone);
    final digitsOnly = _phoneDigits(phone);

    return adminPhones.contains(normalized) ||
        adminPhones.any((adminPhone) => _phoneDigits(adminPhone) == digitsOnly);
  }

  String _normalizePhone(String value) {
    return value.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  String _phoneDigits(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }
}
