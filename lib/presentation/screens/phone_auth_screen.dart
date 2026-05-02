import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid OTP')),
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
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number'),
            ),
            if (otpSent)
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Enter OTP'),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : otpSent
                      ? verifyOTP
                      : sendOTP,
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(otpSent ? 'Verify OTP' : 'Send OTP'),
            ),
          ],
        ),
      ),
    );
  }
}
