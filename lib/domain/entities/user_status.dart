enum UserStatus {
  active,
  suspended;

  static UserStatus fromString(String? val) {
    switch (val?.trim().toLowerCase()) {
      case 'suspended':
        return UserStatus.suspended;
      case 'active':
      default:
        return UserStatus.active;
    }
  }

  String toJson() => name;
}
