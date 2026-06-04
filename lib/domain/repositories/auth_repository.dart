import '../entities/auth_session.dart';

abstract class AuthRepository {
  Stream<AuthSession?> authStateChanges();

  AuthSession? get currentSession;

  Future<void> signOut();
}
