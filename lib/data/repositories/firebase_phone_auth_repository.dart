import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/entities/app_user.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/phone_auth_repository.dart';
import '../../domain/repositories/user_repository.dart';

class FirebasePhoneAuthRepository implements PhoneAuthRepository {
  FirebasePhoneAuthRepository({
    required FirebaseAuth auth,
    required UserRepository userRepository,
  })  : _auth = auth,
        _userRepository = userRepository;

  final FirebaseAuth _auth;
  final UserRepository _userRepository;

  @override
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onVerificationFailed,
    required Future<void> Function(AuthSession session) onAutoVerified,
  }) {
    return _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) async {
        final result = await _auth.signInWithCredential(credential);
        final session = await _ensureSession(
          result.user,
          fallbackPhone: phoneNumber,
        );
        await onAutoVerified(session);
      },
      verificationFailed: (exception) {
        onVerificationFailed(exception.message ?? 'Phone verification failed');
      },
      codeSent: (verificationId, _) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  @override
  Future<AuthSession> verifyOtp({
    required String verificationId,
    required String smsCode,
    required String fallbackPhone,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
    final result = await _auth.signInWithCredential(credential);
    return _ensureSession(result.user, fallbackPhone: fallbackPhone);
  }

  Future<AuthSession> _ensureSession(
    User? user, {
    required String fallbackPhone,
  }) async {
    if (user == null) {
      throw StateError('Phone authentication did not return a user.');
    }

    await _userRepository.upsertUser(
      AppUser(
        uid: user.uid,
        email: user.email ?? '',
        phone: user.phoneNumber ?? fallbackPhone,
      ),
    );

    return AuthSession(
      uid: user.uid,
      email: user.email,
      phoneNumber: user.phoneNumber ?? fallbackPhone,
      displayName: user.displayName,
    );
  }
}
