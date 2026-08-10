import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sendotp_flutter_sdk/sendotp_flutter_sdk.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/phone_auth_repository.dart';
import '../../domain/repositories/user_repository.dart';

class Msg91PhoneAuthRepository implements PhoneAuthRepository {
  Msg91PhoneAuthRepository({
    required FirebaseAuth auth,
    required FirebaseFunctions functions,
    required UserRepository userRepository,
  })  : _auth = auth,
        _functions = functions,
        _userRepository = userRepository {
    // Initialize MSG91 SDK with client-side widget credentials.
    // These are NOT the MSG91 Auth Key (which remains server-side in Firebase Secret Manager).
    OTPWidget.initializeWidget(_msg91WidgetId, _msg91WidgetToken);
    print(
        '[MSG91 AUTH] Widget initialized: widgetId length=${_msg91WidgetId.length}, tokenAuth length=${_msg91WidgetToken.length}');
  }

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final UserRepository _userRepository;

  // Client-side widget SDK credentials (NOT the server-side MSG91 Auth Key).
  static const String _msg91WidgetId = '366869647252383739363831';
  static const String _msg91WidgetToken = '558664TMhQh1Xv6a781343P1';

  String? _currentReqId;
  String? _currentAccessToken;
  bool _isVerifying = false;

  void clearSession() {
    _currentReqId = null;
    _currentAccessToken = null;
    _isVerifying = false;
  }

  @override
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onVerificationFailed,
    required Future<void> Function(AuthSession session) onAutoVerified,
  }) async {
    try {
      // Normalize phone number (SDK expects digits only, without '+')
      final normalizedPhone =
          phoneNumber.startsWith('+') ? phoneNumber.substring(1) : phoneNumber;
      final maskedPhone =
          '+91******${normalizedPhone.length > 4 ? normalizedPhone.substring(normalizedPhone.length - 4) : ''}';

      print('[MSG91 AUTH] sendOtp called for $maskedPhone');
      print('[MSG91 AUTH] Widget ID exists: ${_msg91WidgetId.isNotEmpty}');
      print('[MSG91 AUTH] TokenAuth exists: ${_msg91WidgetToken.isNotEmpty}');

      // Clear any previous access token when requesting a new OTP
      _currentAccessToken = null;
      _isVerifying = false;

      if (_currentReqId != null) {
        print('[MSG91 AUTH] Retrying with existing reqId');
        final response = await OTPWidget.retryOTP({'reqId': _currentReqId!});
        if (response != null && response['type'] == 'success') {
          onCodeSent(phoneNumber);
          return;
        }
        print('[MSG91 AUTH] Retry failed, sending fresh OTP');
      }

      final response = await OTPWidget.sendOTP({'identifier': normalizedPhone});
      print('[MSG91 DEBUG] raw sendOTP response: $response');

      print('[MSG91 AUTH] sendOTP response type: ${response?['type']}');
      print('[MSG91 AUTH] sendOTP response code: ${response?['code']}');

      if (response != null && response['type'] == 'success') {
        _currentReqId = response['message'];
        print('[MSG91 AUTH] reqId received: ${_currentReqId != null}');
        onCodeSent(phoneNumber);
      } else {
        final errorMsg =
            response?['message']?.toString() ?? 'Failed to send OTP via MSG91.';
        print('[MSG91 AUTH] sendOTP failed: $errorMsg');
        onVerificationFailed('msg91-error: $errorMsg');
      }
    } catch (e) {
      print('[MSG91 AUTH] sendOTP exception: ${e.runtimeType}: $e');
      onVerificationFailed('msg91-error: $e');
    }
  }

  @override
  Future<AuthSession> verifyOtp({
    required String verificationId,
    required String smsCode,
    required String fallbackPhone,
  }) async {
    final maskedPhone = fallbackPhone.length > 4
        ? '${fallbackPhone.substring(0, 3)}******${fallbackPhone.substring(fallbackPhone.length - 4)}'
        : '***';

    print('[MSG91 AUTH] verifyOtp called');
    print('[MSG91 AUTH]   reqId exists: ${_currentReqId != null}');
    print('[MSG91 AUTH]   masked phone: $maskedPhone');
    print('[MSG91 AUTH]   OTP length: ${smsCode.length}');
    print('[MSG91 AUTH]   cached token exists: ${_currentAccessToken != null}');

    if (_currentReqId == null) {
      throw Exception('Missing request ID. Please request OTP again.');
    }

    String accessToken;

    // PHASE 4: Use cached token if available (prevents duplicate MSG91 verifyOTP calls)
    if (_currentAccessToken != null) {
      accessToken = _currentAccessToken!;
      print(
          '[MSG91 AUTH] Using cached access token (length=${accessToken.length})');
    } else {
      // Guard against concurrent verifyOTP calls
      if (_isVerifying) {
        print(
            '[MSG91 AUTH] Duplicate verifyOTP call blocked — already in progress');
        throw Exception('Verification already in progress. Please wait.');
      }

      _isVerifying = true;
      try {
        print('[MSG91 AUTH] Calling OTPWidget.verifyOTP...');
        final response = await OTPWidget.verifyOTP(
            {'reqId': _currentReqId!, 'otp': smsCode.trim()});
        _isVerifying = false;

        print('[MSG91 AUTH] verifyOTP response type: ${response?['type']}');
        print('[MSG91 AUTH] verifyOTP response code: ${response?['code']}');

        if (response == null) {
          throw Exception(
              'No response from MSG91. Widget may not be initialized.');
        }

        final message = response['message']?.toString() ?? '';
        final responseType = response['type']?.toString() ?? '';
        final responseCode = response['code']?.toString() ?? '';

        // Handle code 703: "otp already verified" — MSG91 still returns the access token
        if (responseType == 'error' &&
            responseCode == '703' &&
            message.isNotEmpty) {
          print(
              '[MSG91 AUTH] Code 703: OTP already verified — extracting token');
          // MSG91 returns the access token in the message even for 703
          accessToken = message;
        } else if (responseType == 'success' && message.isNotEmpty) {
          accessToken = message;
        } else if (responseType == 'error') {
          // Real errors (invalid OTP, expired, etc.)
          throw Exception(message.isNotEmpty ? message : 'Incorrect OTP.');
        } else {
          throw Exception('Unexpected MSG91 response.');
        }

        if (accessToken.isEmpty) {
          throw Exception('Failed to retrieve access token from MSG91.');
        }

        // Cache the token so we don't call MSG91 verifyOTP again
        _currentAccessToken = accessToken;
        print(
            '[MSG91 AUTH] Access token cached (length=${accessToken.length})');
      } catch (e) {
        _isVerifying = false;
        print('[MSG91 AUTH] verifyOTP exception: ${e.runtimeType}');
        rethrow;
      }
    }

    // PHASE 5: Call backend validateMsg91Session
    try {
      print('[MSG91 AUTH] Calling validateMsg91Session cloud function...');
      final callable = _functions.httpsCallable('validateMsg91Session');

      final result = await callable.call({
        'accessToken': accessToken,
      }).timeout(AppDurations.networkTimeout);

      print('[MSG91 AUTH] validateMsg91Session succeeded');

      final token = result.data['token'] as String;

      // Clear session only after complete success
      _currentReqId = null;
      _currentAccessToken = null;
      _isVerifying = false;

      print('[MSG91 AUTH] Signing in with custom token...');
      final authResult = await _auth
          .signInWithCustomToken(token)
          .timeout(AppDurations.networkTimeout);

      print('[MSG91 AUTH] Firebase sign-in complete');
      return _ensureSession(authResult.user, fallbackPhone: fallbackPhone);
    } on FirebaseFunctionsException catch (e) {
      print(
          '[MSG91 AUTH] Cloud function error: code=${e.code}, message=${e.message}');
      // Do NOT clear _currentAccessToken here — allow retry with cached token
      if (e.code == 'permission-denied') {
        throw Exception('Backend session validation failed. Please try again.');
      } else if (e.code == 'resource-exhausted') {
        throw Exception('Too many attempts. Please try again later.');
      } else if (e.code == 'unauthenticated') {
        throw Exception('App verification failed. Please restart the app.');
      }
      throw Exception(e.message ?? 'Verification failed on server.');
    } on FirebaseAuthException catch (e) {
      print('[MSG91 AUTH] Firebase auth error: code=${e.code}');
      // Clear everything on auth failure — token may be invalid
      clearSession();
      throw Exception('Authentication failed. Please try again.');
    } catch (e) {
      print('[MSG91 AUTH] Unexpected error: ${e.runtimeType}: $e');
      // Do NOT clear _currentAccessToken — allow retry with cached token
      throw Exception('Unable to complete verification. Please try again.');
    }
  }

  Future<AuthSession> _ensureSession(
    User? user, {
    required String fallbackPhone,
  }) async {
    if (user == null) {
      throw StateError('Phone authentication did not return a user.');
    }

    await _userRepository.upsertUser(
      AppUser(
        uid: user.uid,
        email: user.email ?? '',
        phone: user.phoneNumber ?? fallbackPhone,
      ),
    );

    return AuthSession(
      uid: user.uid,
      email: user.email,
      phoneNumber: user.phoneNumber ?? fallbackPhone,
      displayName: user.displayName,
    );
  }
}
