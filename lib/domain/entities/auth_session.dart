class AuthSession {
  const AuthSession({
    required this.uid,
    this.email,
    this.phoneNumber,
    this.displayName,
  });

  final String uid;
  final String? email;
  final String? phoneNumber;
  final String? displayName;
}
