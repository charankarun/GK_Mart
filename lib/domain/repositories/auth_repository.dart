import '../entities/auth_session.dart';

abstract class AuthRepository {
  Stream<AuthSession?> authStateChanges();

  AuthSession? get currentSession;

  Future<void> signInWithEmail({
    required String email,
    required String password,
  });

  Future<AuthSession> createAccountWithEmail({
    required String name,
    required String phone,
    required String email,
    required String password,
  });

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  Future<void> signOut();
}
