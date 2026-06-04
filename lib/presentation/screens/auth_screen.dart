import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_error_handler.dart';
import '../../core/theme/app_theme.dart';
import '../providers/repository_providers.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final phoneController = TextEditingController();
  final otpController = TextEditingController();

  String verificationId = '';
  bool otpSent = false;
  bool isLoading = false;

  String get _e164Phone => '+91${phoneController.text.trim()}';

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  Future<void> sendOTP() async {
    final phone = phoneController.text.trim();
    if (phone.isEmpty || isLoading) return;

    if (phone.length != 10 || !RegExp(r'^[0-9]+$').hasMatch(phone)) {
      _showMessage('Enter a valid 10-digit mobile number');
      return;
    }

    setState(() => isLoading = true);

    try {
      await ref.read(phoneAuthRepositoryProvider).sendOtp(
            phoneNumber: _e164Phone,
            onCodeSent: (verId) {
              if (!mounted) return;

              setState(() {
                verificationId = verId;
                otpSent = true;
                isLoading = false;
              });
              _showMessage('OTP sent successfully');
            },
            onVerificationFailed: (message) {
              if (!mounted) return;

              setState(() => isLoading = false);
              _showMessage(message);
            },
            onAutoVerified: (_) async {
              // Automatically verified, stream will update main screen
              if (!mounted) return;
              setState(() => isLoading = false);
            },
          );
    } catch (error) {
      if (!mounted) return;

      setState(() => isLoading = false);
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: 'Unable to send OTP',
      );
    }
  }

  Future<void> verifyOTP() async {
    final otp = otpController.text.trim();
    if (otp.isEmpty || isLoading) return;

    if (otp.length < 6) {
      _showMessage('Enter a valid 6-digit OTP');
      return;
    }

    setState(() => isLoading = true);

    try {
      await ref.read(phoneAuthRepositoryProvider).verifyOtp(
            verificationId: verificationId,
            smsCode: otp,
            fallbackPhone: _e164Phone,
          );
      // Success: Riverpod auth state listener will automatically redirect to MainScreen
    } catch (error) {
      if (!mounted) return;

      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: 'Invalid OTP. Please try again.',
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
                const SizedBox(height: 40),
                Text(
                  otpSent ? 'Verify Mobile OTP' : 'Welcome to GK Mart',
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
                  otpSent
                      ? 'Enter the 6-digit verification code sent to your mobile.'
                      : 'Enter your 10-digit mobile number to continue.',
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        enabled: !otpSent && !isLoading,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Mobile Number',
                          prefixText: '+91 ',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      if (otpSent) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: otpController,
                          keyboardType: TextInputType.number,
                          enabled: !isLoading,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Enter 6-Digit OTP',
                            prefixIcon: Icon(Icons.password_rounded),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: isLoading
                        ? null
                        : otpSent
                            ? verifyOTP
                            : sendOTP,
                    icon: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            otpSent
                                ? Icons.verified_user_rounded
                                : Icons.sms_rounded,
                          ),
                    label: Text(
                      otpSent ? 'Verify & Login' : 'Send Verification OTP',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                if (otpSent) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      onPressed: isLoading
                          ? null
                          : () {
                              setState(() {
                                otpSent = false;
                                otpController.clear();
                              });
                            },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Change Mobile Number'),
                    ),
                  ),
                ],
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
