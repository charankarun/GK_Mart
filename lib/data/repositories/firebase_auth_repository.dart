import 'package:firebase_auth/firebase_auth.dart';

import '../../core/constants/app_constants.dart';
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
  Future<void> signOut() {
    return _auth.signOut().timeout(AppDurations.networkTimeout);
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
