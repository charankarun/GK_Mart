import '../entities/auth_session.dart';

abstract class PhoneAuthRepository {
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onVerificationFailed,
    required Future<void> Function(AuthSession session) onAutoVerified,
  });

  Future<AuthSession> verifyOtp({
    required String verificationId,
    required String smsCode,
    required String fallbackPhone,
  });
}
