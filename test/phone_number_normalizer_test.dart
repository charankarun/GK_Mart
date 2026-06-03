import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_app/core/utils/phone_number_normalizer.dart';

void main() {
  test('normalizes Indian phone formats to local 10 digit numbers', () {
    expect(
      PhoneNumberNormalizer.toIndianLocalNumber('+919390296609'),
      '9390296609',
    );
    expect(
      PhoneNumberNormalizer.toIndianLocalNumber('9390296609'),
      '9390296609',
    );
    expect(
      PhoneNumberNormalizer.toIndianLocalNumber('+91 93902-96609'),
      '9390296609',
    );
  });

  test('validates normalized local phone numbers', () {
    expect(
      PhoneNumberNormalizer.isIndianLocalNumber('+919390296609'),
      isTrue,
    );
    expect(
      PhoneNumberNormalizer.isIndianLocalNumber('9390296609'),
      isTrue,
    );
    expect(
      PhoneNumberNormalizer.isIndianLocalNumber('+91939029660'),
      isFalse,
    );
  });

  test('keeps OTP-compatible E164 conversion available without storing it', () {
    expect(
      PhoneNumberNormalizer.toIndianE164Number('9390296609'),
      '+919390296609',
    );
  });
}
