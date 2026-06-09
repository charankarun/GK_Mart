import 'user_role.dart';
import 'user_status.dart';

class AppUser {
  const AppUser({
    required this.uid,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.addresses = const <String>[],
    this.photoUrl = '',
    this.createdAt,
    this.updatedAt,
    this.role = UserRole.customer,
    this.roleUpdatedAt,
    this.roleUpdatedBy = '',
    this.status = UserStatus.active,
  });

  final String uid;
  final String name;
  final String email;
  final String phone;
  final String address;
  final List<String> addresses;
  final String photoUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final UserRole role;
  final DateTime? roleUpdatedAt;
  final String roleUpdatedBy;
  final UserStatus status;

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (email.trim().isNotEmpty) return email.trim();
    if (phone.trim().isNotEmpty) return phone.trim();
    return 'User';
  }

  List<String> get savedAddresses {
    if (addresses.isNotEmpty) return addresses;
    final primaryAddress = address.trim();
    if (primaryAddress.isEmpty) return const <String>[];
    return <String>[primaryAddress];
  }

  AppUser copyWith({
    String? uid,
    String? name,
    String? email,
    String? phone,
    String? address,
    List<String>? addresses,
    String? photoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    UserRole? role,
    DateTime? roleUpdatedAt,
    String? roleUpdatedBy,
    UserStatus? status,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      addresses: addresses ?? this.addresses,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      role: role ?? this.role,
      roleUpdatedAt: roleUpdatedAt ?? this.roleUpdatedAt,
      roleUpdatedBy: roleUpdatedBy ?? this.roleUpdatedBy,
      status: status ?? this.status,
    );
  }
}

