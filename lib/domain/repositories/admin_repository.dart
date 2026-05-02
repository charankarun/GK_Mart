import '../entities/auth_session.dart';

abstract class AdminRepository {
  Stream<bool> watchIsAdmin(AuthSession session);
}
