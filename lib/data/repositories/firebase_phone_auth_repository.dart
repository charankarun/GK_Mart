import 'package:firebase_auth/firebase_auth.dart';

import '../../core/constants/app_constants.dart';
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
    print('--- TIMING LOG: verifyPhoneNumber started at ${DateTime.now().toIso8601String()} ---');
    return _auth
        .verifyPhoneNumber(
          phoneNumber: phoneNumber,
          verificationCompleted: (credential) async {
            print('--- TIMING LOG: verificationCompleted triggered at ${DateTime.now().toIso8601String()} ---');
            final result = await _auth
                .signInWithCredential(credential)
                .timeout(AppDurations.networkTimeout);
            final session = await _ensureSession(
              result.user,
              fallbackPhone: phoneNumber,
            );
            await onAutoVerified(session);
          },
          verificationFailed: (exception) {
            print('--- TIMING LOG: verificationFailed triggered at ${DateTime.now().toIso8601String()} ---');
            print('--- TELEPHONY AUTH EXCEPTION (Repository) ---');
            print('Code: ${exception.code}');
            print('Message: ${exception.message}');
            print('ToString: ${exception.toString()}');
            print('StackTrace: ${StackTrace.current}');
            print('---------------------------------------------');
            onVerificationFailed(
              exception.message ?? 'Phone verification failed',
            );
          },
          codeSent: (verificationId, _) {
            print('--- TIMING LOG: codeSent triggered at ${DateTime.now().toIso8601String()} ---');
            onCodeSent(verificationId);
          },
          codeAutoRetrievalTimeout: (_) {},
        )
        .timeout(AppDurations.networkTimeout);
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
    final result = await _auth
        .signInWithCredential(credential)
        .timeout(AppDurations.networkTimeout);
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
