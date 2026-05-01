import 'package:firebase_auth/firebase_auth.dart';

bool isAdminUser() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;

  const adminPhones = [
    "+919876543210",
  ];

  const adminEmails = [
    "charankarun01@gmail.com",
    "nuthanapatikarunsai@gmail.com",
  ];

  final email = user.email?.trim().toLowerCase();
  final phone = user.phoneNumber;

  return (email != null && adminEmails.contains(email)) ||
      (phone != null && adminPhones.contains(phone));
}
