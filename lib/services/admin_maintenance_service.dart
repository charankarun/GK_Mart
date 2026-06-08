import 'dart:developer' as developer;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final adminMaintenanceServiceProvider =
    Provider<AdminMaintenanceService>((ref) {
  return AdminMaintenanceService();
});

class AdminMaintenanceService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  Future<void> recalibrateInventoryStats() async {
    try {
      final callable = _functions.httpsCallable('recalibrateInventoryStats');
      await callable.call();
    } on FirebaseFunctionsException catch (e) {
      // Log only actionable errors
      developer.log(
        'FirebaseFunctionsException in recalibrateInventoryStats: ${e.code} - ${e.message}',
        name: 'AdminMaintenanceService',
        error: e,
      );
      rethrow;
    }
  }

  Future<void> recalibrateOrderAnalytics() async {
    try {
      final callable = _functions.httpsCallable('recalibrateOrderAnalytics');
      await callable.call();
    } on FirebaseFunctionsException catch (e) {
      // Log only actionable errors
      developer.log(
        'FirebaseFunctionsException in recalibrateOrderAnalytics: ${e.code} - ${e.message}',
        name: 'AdminMaintenanceService',
        error: e,
      );
      rethrow;
    }
  }
}


