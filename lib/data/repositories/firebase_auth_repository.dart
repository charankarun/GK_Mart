import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/entities/app_user.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/user_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    required FirebaseAuth auth,
    required UserRepository userRepository,
  })  : _auth = auth,
        _userRepository = userRepository;

  final FirebaseAuth _auth;
  final UserRepository _userRepository;

  @override
  Stream<AuthSession?> authStateChanges() {
    return _auth.authStateChanges().map(_toSession);
  }

  @override
  AuthSession? get currentSession => _toSession(_auth.currentUser);

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
  }

  @override
  Future<AuthSession> createAccountWithEmail({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
    final user = credential.user;

    if (user == null) {
      throw StateError('Account was created without an authenticated user.');
    }

    await _userRepository.upsertUser(
      AppUser(
        uid: user.uid,
        name: name.trim(),
        email: email.trim(),
        phone: phone.trim(),
      ),
    );

    return _toSession(user)!;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email?.trim();

    if (user == null || email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'no-email-password-provider',
        message: 'This account uses mobile OTP. No password to change.',
      );
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword.trim(),
    );

    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword.trim());
  }

  @override
  Future<void> signOut() {
    return _auth.signOut();
  }

  AuthSession? _toSession(User? user) {
    if (user == null) return null;

    return AuthSession(
      uid: user.uid,
      email: user.email,
      phoneNumber: user.phoneNumber,
      displayName: user.displayName,
    );
  }
}
