enum UserRole {
  owner,
  admin,
  customer;

  static UserRole fromString(String? val) {
    switch (val?.trim().toLowerCase()) {
      case 'owner':
        return UserRole.owner;
      case 'admin':
        return UserRole.admin;
      case 'customer':
      default:
        return UserRole.customer;
    }
  }

  String toJson() => name;
}
