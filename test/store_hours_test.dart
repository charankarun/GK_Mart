import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_app/domain/entities/store_config.dart';

void main() {
  group('StoreConfig operational hours validation', () {
    test('isOpen returns true if store is enabled and current time is within business hours', () {
      final now = DateTime.now();
      // Configure business hours to envelope current time
      final openHour = (now.hour - 1 + 24) % 24;
      final closeHour = (now.hour + 1) % 24;

      final config = StoreConfig(
        storeEnabled: true,
        openHour: openHour,
        openMinute: 0,
        closeHour: closeHour,
        closeMinute: 0,
      );

      // Unless openHour is closeHour (which happens if store open period is 0 hours),
      // the current time is guaranteed to be inside. Let's make sure openHour != closeHour.
      if (openHour != closeHour) {
        expect(config.isOpen, isTrue);
      }
    });

    test('isOpen returns false if store is enabled but current time is outside business hours', () {
      final now = DateTime.now();
      // Configure business hours to be in the past/future (outside current time)
      final openHour = (now.hour + 1) % 24;
      final closeHour = (now.hour + 2) % 24;

      final config = StoreConfig(
        storeEnabled: true,
        openHour: openHour,
        openMinute: 0,
        closeHour: closeHour,
        closeMinute: 0,
      );

      expect(config.isOpen, isFalse);
    });

    test('isOpen returns false if store is disabled regardless of operational hours', () {
      final now = DateTime.now();
      final openHour = (now.hour - 1 + 24) % 24;
      final closeHour = (now.hour + 1) % 24;

      final config = StoreConfig(
        storeEnabled: false,
        openHour: openHour,
        openMinute: 0,
        closeHour: closeHour,
        closeMinute: 0,
      );

      expect(config.isOpen, isFalse);
    });

    test('formattedOpenTime and formattedCloseTime format times in AM/PM correctly', () {
      const config1 = StoreConfig(
        storeEnabled: true,
        openHour: 6,
        openMinute: 0,
        closeHour: 22,
        closeMinute: 0,
      );

      expect(config1.formattedOpenTime, '6:00 AM');
      expect(config1.formattedCloseTime, '10:00 PM');

      const config2 = StoreConfig(
        storeEnabled: true,
        openHour: 12,
        openMinute: 30,
        closeHour: 0,
        closeMinute: 15,
      );

      expect(config2.formattedOpenTime, '12:30 PM');
      expect(config2.formattedCloseTime, '12:15 AM');
    });

    group('Overnight schedule (5:00 AM to 3:00 AM) tests', () {
      const config = StoreConfig(
        storeEnabled: true,
        openHour: 5,
        openMinute: 0,
        closeHour: 3,
        closeMinute: 0,
      );

      DateTime timeAt(int hour, int minute) {
        return DateTime(2026, 6, 4, hour, minute);
      }

      test('1:00 AM is OPEN', () {
        expect(config.isOpenAt(timeAt(1, 0)), isTrue);
      });

      test('2:30 AM is OPEN', () {
        expect(config.isOpenAt(timeAt(2, 30)), isTrue);
      });

      test('3:01 AM is CLOSED', () {
        expect(config.isOpenAt(timeAt(3, 1)), isFalse);
      });

      test('4:30 AM is CLOSED', () {
        expect(config.isOpenAt(timeAt(4, 30)), isFalse);
      });

      test('5:00 AM is OPEN', () {
        expect(config.isOpenAt(timeAt(5, 0)), isTrue);
      });
    });

    group('Admin Override (Store Active = OFF) tests', () {
      const config = StoreConfig(
        storeEnabled: false,
        openHour: 5,
        openMinute: 0,
        closeHour: 3,
        closeMinute: 0,
      );

      DateTime timeAt(int hour, int minute) {
        return DateTime(2026, 6, 4, hour, minute);
      }

      test('1:00 AM is CLOSED when store is disabled', () {
        expect(config.isOpenAt(timeAt(1, 0)), isFalse);
      });

      test('5:00 AM is CLOSED when store is disabled', () {
        expect(config.isOpenAt(timeAt(5, 0)), isFalse);
      });
    });
  });
}
