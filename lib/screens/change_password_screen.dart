import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoading = false;
  bool obscureCurrent = true;
  bool obscureNew = true;
  bool obscureConfirm = true;

  @override
  void dispose() {
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim();
    final currentPassword = currentPasswordController.text.trim();
    final newPassword = newPasswordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (user == null) return;

    if (email == null || email.isEmpty) {
      _showMessage("This account uses mobile OTP. No password to change.");
      return;
    }

    if (currentPassword.isEmpty ||
        newPassword.isEmpty ||
        confirmPassword.isEmpty) {
      _showMessage("Please fill all password fields");
      return;
    }

    if (newPassword.length < 6) {
      _showMessage("New password must be at least 6 characters");
      return;
    }

    if (newPassword != confirmPassword) {
      _showMessage("New passwords do not match");
      return;
    }

    setState(() => isLoading = true);

    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);

      if (!mounted) return;

      currentPasswordController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();

      _showMessage("Password updated successfully");
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message = "Unable to update password";

      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = "Current password is incorrect";
      } else if (e.code == 'weak-password') {
        message = "New password is too weak";
      } else if (e.code == 'requires-recent-login') {
        message = "Please login again before changing password";
      } else if (e.message != null && e.message!.isNotEmpty) {
        message = e.message!;
      }

      _showMessage(message);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscureText,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock),
        suffixIcon: IconButton(
          icon: Icon(obscureText ? Icons.visibility : Icons.visibility_off),
          onPressed: onToggle,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim();
    final hasEmailPassword = email != null && email.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text("Reset Password")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hasEmailPassword)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  "This account uses mobile OTP. There is no email password to reset.",
                ),
              )
            else ...[
              _passwordField(
                controller: currentPasswordController,
                label: "Current Password",
                obscureText: obscureCurrent,
                onToggle: () {
                  setState(() => obscureCurrent = !obscureCurrent);
                },
              ),
              const SizedBox(height: 15),
              _passwordField(
                controller: newPasswordController,
                label: "New Password",
                obscureText: obscureNew,
                onToggle: () {
                  setState(() => obscureNew = !obscureNew);
                },
              ),
              const SizedBox(height: 15),
              _passwordField(
                controller: confirmPasswordController,
                label: "Confirm New Password",
                obscureText: obscureConfirm,
                onToggle: () {
                  setState(() => obscureConfirm = !obscureConfirm);
                },
              ),
              const SizedBox(height: 10),
              const Text(
                "If you forgot your password, login using mobile OTP from the login screen.",
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Update Password"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
