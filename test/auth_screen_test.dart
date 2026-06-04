import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_app/domain/entities/auth_session.dart';
import 'package:supermarket_app/domain/repositories/phone_auth_repository.dart';
import 'package:supermarket_app/presentation/providers/repository_providers.dart';
import 'package:supermarket_app/presentation/screens/auth_screen.dart';

void main() {
  late _FakePhoneAuthRepository fakeRepository;

  setUp(() {
    fakeRepository = _FakePhoneAuthRepository();
    AuthScreen.resetRateLimit();
  });

  Widget createAuthScreen() {
    return ProviderScope(
      overrides: [
        phoneAuthRepositoryProvider.overrideWithValue(fakeRepository),
      ],
      child: const MaterialApp(
        home: AuthScreen(),
      ),
    );
  }

  group('AuthScreen Production-Ready Features Tests', () {
    testWidgets('Entering phone number and sending OTP works correctly', (tester) async {
      await tester.pumpWidget(createAuthScreen());

      // Enter valid 10-digit number
      final phoneField = find.byType(TextField);
      expect(phoneField, findsOneWidget);
      await tester.enterText(phoneField, '9876543210');
      await tester.pump();

      // Tap Send OTP
      final sendButton = find.widgetWithText(ElevatedButton, 'Send Verification OTP');
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      
      // Pump to render updated state
      await tester.pump();

      // Check success SnackBar message and screen transition
      expect(find.text('OTP Sent Successfully'), findsOneWidget);
      expect(find.text('Enter 6-Digit OTP'), findsOneWidget);
      expect(find.text('OTP sent to +919876543210'), findsOneWidget);
    });

    testWidgets('Change Number clears input fields and returns to phone screen', (tester) async {
      await tester.pumpWidget(createAuthScreen());

      // Go to OTP screen
      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Verification OTP'));
      await tester.pump();

      // Verify on OTP screen
      expect(find.text('Enter 6-Digit OTP'), findsOneWidget);

      // Tap Change Number
      final changeNumberButton = find.widgetWithText(TextButton, 'Change Number');
      expect(changeNumberButton, findsOneWidget);
      await tester.tap(changeNumberButton);
      await tester.pump();

      // Verify back on phone screen
      expect(find.widgetWithText(ElevatedButton, 'Send Verification OTP'), findsOneWidget);
      expect(find.text('Enter 6-Digit OTP'), findsNothing);
    });

    testWidgets('Local rate limiting prevents more than 3 OTP requests within 10 minutes', (tester) async {
      await tester.pumpWidget(createAuthScreen());

      // Attempt 1
      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Verification OTP'));
      await tester.pump();
      expect(fakeRepository.sendOtpCalls, 1);

      // Return to screen via Change Number
      await tester.tap(find.widgetWithText(TextButton, 'Change Number'));
      await tester.pump();

      // Attempt 2
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Verification OTP'));
      await tester.pump();
      expect(fakeRepository.sendOtpCalls, 2);

      // Return to screen via Change Number
      await tester.tap(find.widgetWithText(TextButton, 'Change Number'));
      await tester.pump();

      // Attempt 3
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Verification OTP'));
      await tester.pump();
      expect(fakeRepository.sendOtpCalls, 3);

      // Return to screen via Change Number
      await tester.tap(find.widgetWithText(TextButton, 'Change Number'));
      await tester.pump();

      // Attempt 4 (should be rate-limited)
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Verification OTP'));
      await tester.pump();

      // Should show the local rate limit warning message
      expect(find.text('Too many OTP requests. Please try again after a few minutes.'), findsOneWidget);
      // Firebase sendOtp should NOT have been called for the 4th time
      expect(fakeRepository.sendOtpCalls, 3);
    });

    testWidgets('Friendly error messages are shown for Firebase exceptions', (tester) async {
      await tester.pumpWidget(createAuthScreen());

      // Go to OTP screen
      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Verification OTP'));
      await tester.pump();

      // Test incorrect OTP
      fakeRepository.failVerify = true;
      fakeRepository.failVerifyCode = 'invalid-verification-code';
      
      await tester.enterText(find.byType(TextField), '111111');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Verify & Login'));
      await tester.pump();

      // Check friendly message
      expect(find.text('Incorrect OTP entered.'), findsOneWidget);
      
      // Test OTP expired
      fakeRepository.failVerifyCode = 'session-expired';
      await tester.tap(find.widgetWithText(ElevatedButton, 'Verify & Login'));
      await tester.pump();
      expect(find.text('OTP expired. Request a new OTP.'), findsOneWidget);

      // Test network error
      fakeRepository.failVerifyCode = 'network-request-failed';
      await tester.tap(find.widgetWithText(ElevatedButton, 'Verify & Login'));
      await tester.pump();
      expect(find.text('Please check your internet connection.'), findsOneWidget);
    });

    testWidgets('Countdown renders and enables Resend OTP button after 30 seconds', (tester) async {
      await tester.pumpWidget(createAuthScreen());

      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Verification OTP'));
      await tester.pump();

      // Check countdown text is shown
      expect(find.text('Resend OTP in 30 seconds'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Resend OTP'), findsNothing);

      // Tick the timer by 15 seconds
      await tester.pump(const Duration(seconds: 15));
      expect(find.text('Resend OTP in 15 seconds'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Resend OTP'), findsNothing);

      // Tick the timer past 30 seconds
      await tester.pump(const Duration(seconds: 16));

      // Countdown text should disappear, and Resend OTP button should appear
      expect(find.textContaining('Resend OTP in'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Resend OTP'), findsOneWidget);
    });

    testWidgets('Login help text and bullet points are displayed when otpSent is true', (tester) async {
      await tester.pumpWidget(createAuthScreen());

      // Help text should not be visible on the mobile entry screen
      expect(find.text("Didn't receive OTP?"), findsNothing);

      // Send OTP
      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Verification OTP'));
      await tester.pump();

      // Help text should now be visible
      expect(find.text("Didn't receive OTP?"), findsOneWidget);
      expect(find.textContaining('- Wait for SMS delivery'), findsOneWidget);
      expect(find.textContaining('- Check entered mobile number'), findsOneWidget);
      expect(find.textContaining('- Use Resend OTP after countdown'), findsOneWidget);
    });
  });
}

class _FakePhoneAuthRepository implements PhoneAuthRepository {
  bool failSend = false;
  String failSendMessage = '';
  bool failVerify = false;
  String failVerifyCode = '';

  int sendOtpCalls = 0;
  int verifyOtpCalls = 0;

  @override
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onVerificationFailed,
    required Future<void> Function(AuthSession session) onAutoVerified,
  }) async {
    sendOtpCalls++;
    if (failSend) {
      onVerificationFailed(failSendMessage);
      return;
    }
    onCodeSent('test-verification-id');
  }

  @override
  Future<AuthSession> verifyOtp({
    required String verificationId,
    required String smsCode,
    required String fallbackPhone,
  }) async {
    verifyOtpCalls++;
    if (failVerify) {
      throw FirebaseAuthException(
        code: failVerifyCode,
        message: 'Fake Firebase Auth Exception',
      );
    }
    return AuthSession(
      uid: 'fake-uid-123',
      phoneNumber: fallbackPhone,
    );
  }
}
