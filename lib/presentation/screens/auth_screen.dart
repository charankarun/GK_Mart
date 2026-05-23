import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error_handler.dart';
import '../../core/theme/app_theme.dart';
import '../providers/repository_providers.dart';
import 'phone_auth_screen.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool isLogin = true;
  bool isSubmitting = false;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();

  void openOtpLogin({bool fromForgotPassword = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhoneAuthScreen(
          title: fromForgotPassword ? 'Login with OTP' : 'Login with Phone',
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (isSubmitting) return;

    try {
      if (emailController.text.trim().isEmpty ||
          passwordController.text.trim().isEmpty) {
        _showMessage('Email & Password required');
        return;
      }

      if (!isLogin &&
          (nameController.text.trim().isEmpty ||
              phoneController.text.trim().isEmpty)) {
        _showMessage('All fields required');
        return;
      }

      setState(() => isSubmitting = true);

      final authRepository = ref.read(authRepositoryProvider);

      if (isLogin) {
        await authRepository.signInWithEmail(
          email: emailController.text,
          password: passwordController.text,
        );
      } else {
        await authRepository.createAccountWithEmail(
          name: nameController.text,
          phone: phoneController.text,
          email: emailController.text,
          password: passwordController.text,
        );

        _showMessage('Account created successfully');
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(_authMessage(e));
    } catch (error) {
      if (AppErrorHandler.isPermissionDenied(error)) return;
      _showMessage(
        AppErrorHandler.messageFor(error, fallback: 'Error occurred'),
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _authMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Email already in use';
      case 'invalid-email':
        return 'Invalid email';
      case 'weak-password':
        return 'Password too weak';
      case 'user-not-found':
        return 'User not found';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Wrong password';
      default:
        return e.message?.isNotEmpty == true
            ? e.message!
            : 'Something went wrong';
    }
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool isPassword = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _AuthBrandHeader(),
                const SizedBox(height: 30),
                Text(
                  isLogin ? 'Welcome back' : 'Create your account',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 26,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isLogin
                      ? 'Fresh groceries are waiting for you.'
                      : 'Join GK Mart for faster checkout and easy orders.',
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 28),
                if (!isLogin)
                  _buildTextField(
                    nameController,
                    'Full Name',
                    Icons.person_outline_rounded,
                  ),
                if (!isLogin) const SizedBox(height: 14),
                if (!isLogin)
                  _buildTextField(
                    phoneController,
                    'Phone',
                    Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                if (!isLogin) const SizedBox(height: 14),
                _buildTextField(
                  emailController,
                  'Email',
                  Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  passwordController,
                  'Password',
                  Icons.lock_outline_rounded,
                  isPassword: true,
                ),
                if (isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: isSubmitting
                          ? null
                          : () => openOtpLogin(fromForgotPassword: true),
                      child: const Text(
                        'Forgot password? Use mobile OTP',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isSubmitting ? null : submit,
                    child: isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            isLogin ? 'Login' : 'Sign Up',
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.border)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          color: AppColors.mutedText,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider(color: AppColors.border)),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: isSubmitting ? null : () => openOtpLogin(),
                    icon: const Icon(Icons.phone_iphone_rounded),
                    label: const Text('Login with Phone'),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: isSubmitting
                        ? null
                        : () {
                            setState(() {
                              isLogin = !isLogin;
                            });
                          },
                    child: Text(
                      isLogin
                          ? "Don't have an account? Sign Up"
                          : 'Already have an account? Login',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthBrandHeader extends StatelessWidget {
  const _AuthBrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: AppShadows.soft,
          ),
          child: const Icon(
            Icons.shopping_basket_rounded,
            color: Colors.white,
            size: 27,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'GK ',
                      style: TextStyle(color: AppColors.primary),
                    ),
                    TextSpan(
                      text: 'MART',
                      style: TextStyle(color: AppColors.accent),
                    ),
                  ],
                ),
                style: TextStyle(
                  fontSize: 24,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Supermarket',
                style: TextStyle(
                  color: AppColors.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
