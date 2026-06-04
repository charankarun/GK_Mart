import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../providers/repository_providers.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @visibleForTesting
  static void resetRateLimit() {
    _AuthScreenState.resetRateLimit();
  }

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final phoneController = TextEditingController();
  final otpController = TextEditingController();

  String verificationId = '';
  bool otpSent = false;
  bool isLoading = false;

  Timer? _timer;
  int _secondsRemaining = 30;

  static final List<DateTime> _otpSendTimestamps = [];

  @visibleForTesting
  static void resetRateLimit() {
    _otpSendTimestamps.clear();
  }

  String get _e164Phone => '+91${phoneController.text.trim()}';

  @override
  void dispose() {
    _timer?.cancel();
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() {
      _secondsRemaining = 30;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        if (_secondsRemaining > 0) {
          setState(() {
            _secondsRemaining--;
          });
        } else {
          _timer?.cancel();
        }
      }
    });
  }

  bool _isRateLimited() {
    final now = DateTime.now();
    _otpSendTimestamps.removeWhere((time) => now.difference(time).inMinutes >= 10);
    return _otpSendTimestamps.length >= 3;
  }

  Future<void> sendOTP({bool isResend = false}) async {
    final phone = phoneController.text.trim();
    if (phone.isEmpty || isLoading) return;

    if (phone.length != 10 || !RegExp(r'^[0-9]+$').hasMatch(phone)) {
      _showMessage('Enter a valid 10-digit mobile number');
      return;
    }

    if (_isRateLimited()) {
      _showMessage('Too many OTP requests. Please try again after a few minutes.');
      return;
    }

    setState(() => isLoading = true);

    try {
      await ref.read(phoneAuthRepositoryProvider).sendOtp(
            phoneNumber: _e164Phone,
            onCodeSent: (verId) {
              if (!mounted) return;

              _otpSendTimestamps.add(DateTime.now());

              setState(() {
                verificationId = verId;
                otpSent = true;
                isLoading = false;
              });
              _startTimer();
              _showMessage(isResend ? 'OTP Resent Successfully' : 'OTP Sent Successfully');
            },
            onVerificationFailed: (message) {
              if (!mounted) return;

              setState(() => isLoading = false);
              _showMessage(_getFriendlyMessageFromString(message));
            },
            onAutoVerified: (_) async {
              if (!mounted) return;
              setState(() => isLoading = false);
            },
          );
    } catch (error) {
      if (!mounted) return;

      setState(() => isLoading = false);
      _showMessage(_getFriendlyErrorMessage(error));
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
    } catch (error) {
      if (!mounted) return;
      _showMessage(_getFriendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void editPhoneNumber() {
    _timer?.cancel();
    setState(() {
      otpSent = false;
      verificationId = '';
      otpController.clear();
      isLoading = false;
    });
  }

  String _getFriendlyErrorMessage(Object error) {
    if (error is FirebaseAuthException) {
      final code = error.code;
      final message = (error.message ?? '').toLowerCase();

      if (code == 'too-many-requests' ||
          message.contains('blocked all requests') ||
          message.contains('unusual activity') ||
          message.contains('too many requests')) {
        return 'Too many verification attempts detected. Please try again later.';
      }

      switch (code) {
        case 'invalid-verification-code':
        case 'invalid-credential':
          return 'Incorrect OTP entered.';
        case 'session-expired':
          return 'OTP expired. Request a new OTP.';
        case 'network-request-failed':
          return 'Please check your internet connection.';
        default:
          return 'An error occurred. Please try again.';
      }
    }

    return _getFriendlyMessageFromString(error.toString());
  }

  String _getFriendlyMessageFromString(String message) {
    final lowerMessage = message.toLowerCase();
    if (lowerMessage.contains('blocked') ||
        lowerMessage.contains('unusual activity') ||
        lowerMessage.contains('too-many-requests') ||
        lowerMessage.contains('too many requests')) {
      return 'Too many verification attempts detected. Please try again later.';
    }
    if (lowerMessage.contains('invalid-verification-code') ||
        lowerMessage.contains('invalid-credential') ||
        lowerMessage.contains('invalid code') ||
        lowerMessage.contains('incorrect')) {
      return 'Incorrect OTP entered.';
    }
    if (lowerMessage.contains('network') ||
        lowerMessage.contains('connection') ||
        lowerMessage.contains('network-request-failed')) {
      return 'Please check your internet connection.';
    }
    if (lowerMessage.contains('session-expired') ||
        lowerMessage.contains('expired')) {
      return 'OTP expired. Request a new OTP.';
    }
    return 'An error occurred. Please try again.';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
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
                      if (otpSent) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'OTP sent to +91${phoneController.text}',
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: isLoading ? null : editPhoneNumber,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Change Number',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
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
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (_secondsRemaining > 0)
                              Text(
                                'Resend OTP in $_secondsRemaining seconds',
                                style: const TextStyle(
                                  color: AppColors.mutedText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            else
                              TextButton(
                                onPressed: isLoading ? null : () => sendOTP(isResend: true),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Resend OTP',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ] else ...[
                        TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          enabled: !isLoading,
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
                            : () => sendOTP(),
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
                      isLoading
                          ? (otpSent ? 'Verifying...' : 'Sending OTP...')
                          : (otpSent ? 'Verify & Login' : 'Send Verification OTP'),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                if (otpSent) ...[
                  const SizedBox(height: 24),
                  const Text(
                    "Didn't receive OTP?",
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "- Wait for SMS delivery\n"
                    "- Check entered mobile number\n"
                    "- Use Resend OTP after countdown",
                    style: TextStyle(
                      color: AppColors.mutedText,
                      fontSize: 13,
                      height: 1.6,
                      fontWeight: FontWeight.w500,
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
