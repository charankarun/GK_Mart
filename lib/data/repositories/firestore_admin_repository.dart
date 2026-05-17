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

  @override
  Stream<bool> watchIsAdmin(AuthSession session) async* {
    yield* RepositoryGuard.watch(
      message: 'Unable to verify admin access.',
      create: () async* {
        try {
          await for (final doc in _adminConfigRef.snapshots()) {
            final data = doc.data();
            if (data == null) {
              yield false;
              continue;
            }

            yield _matchesAdminConfig(session, data);
          }
        } catch (_) {
          yield false;
        }
      },
    );
  }

  bool _matchesAdminConfig(
    AuthSession session,
    Map<String, dynamic> data,
  ) {
    final adminEmails = _adminEmails(data);
    final adminPhones = _adminPhones(data);
    final email = session.email?.trim().toLowerCase();
    final phone = session.phoneNumber?.trim();

    return (email != null && adminEmails.contains(email)) ||
        (phone != null && _containsPhone(adminPhones, phone));
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
