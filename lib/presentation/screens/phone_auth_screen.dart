import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error_handler.dart';
import '../../core/theme/app_theme.dart';
import '../providers/repository_providers.dart';

class PhoneAuthScreen extends ConsumerStatefulWidget {
  const PhoneAuthScreen({
    super.key,
    this.title = 'Login with Phone',
  });

  final String title;

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  final phoneController = TextEditingController();
  final otpController = TextEditingController();

  String verificationId = '';
  bool otpSent = false;
  bool isLoading = false;

  String get _e164Phone => '+91${phoneController.text.trim()}';

  Future<void> sendOTP() async {
    if (phoneController.text.trim().isEmpty || isLoading) return;

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
            },
            onVerificationFailed: (message) {
              if (!mounted) return;

              setState(() => isLoading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            },
            onAutoVerified: (_) async {
              if (!mounted) return;
              Navigator.pop(context);
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
    if (otpController.text.trim().isEmpty || isLoading) return;

    setState(() => isLoading = true);

    try {
      await ref.read(phoneAuthRepositoryProvider).verifyOtp(
            verificationId: verificationId,
            smsCode: otpController.text,
            fallbackPhone: _e164Phone,
          );

      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;

      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: 'Invalid OTP',
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.title)),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: AppColors.border),
                boxShadow: AppShadows.soft,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.softOrange,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                    ),
                    child: const Icon(
                      Icons.phone_iphone_rounded,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Mobile OTP login',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 22,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enter your mobile number to continue securely.',
                    style: TextStyle(
                      color: AppColors.mutedText,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixText: '+91 ',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  if (otpSent) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Enter OTP',
                        prefixIcon: Icon(Icons.password_rounded),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: isLoading
                    ? null
                    : otpSent
                        ? verifyOTP
                        : sendOTP,
                icon: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
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
                label: Text(otpSent ? 'Verify OTP' : 'Send OTP'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
