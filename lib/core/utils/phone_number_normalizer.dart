class PhoneNumberNormalizer {
  const PhoneNumberNormalizer._();

  static final RegExp _localTenDigitPattern = RegExp(r'^[0-9]{10}$');
  static final RegExp _indianMobilePattern = RegExp(r'^[6-9][0-9]{9}$');

  static String toIndianLocalNumber(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');

    if (digits.length == 10) return digits;
    if (digits.length == 11 && digits.startsWith('0')) {
      return digits.substring(1);
    }
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }

    return '';
  }

  static bool isIndianLocalNumber(String value) {
    return _localTenDigitPattern.hasMatch(toIndianLocalNumber(value));
  }

  static bool isIndianMobileNumber(String value) {
    return _indianMobilePattern.hasMatch(toIndianLocalNumber(value));
  }

  static String toIndianE164Number(String value) {
    final localNumber = toIndianLocalNumber(value);
    if (localNumber.isEmpty) return '';
    return '+91$localNumber';
  }
}
