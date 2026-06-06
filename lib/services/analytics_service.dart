import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService();
});

class AnalyticsService {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  Future<void> logLogin(String method) async {
    await _analytics.logLogin(loginMethod: method);
  }

  Future<void> logAddToCart({
    required String itemId,
    required String itemName,
    required double price,
    required int quantity,
  }) async {
    await _analytics.logAddToCart(
      items: [
        AnalyticsEventItem(
          itemId: itemId,
          itemName: itemName,
          price: price,
          quantity: quantity,
        ),
      ],
      value: price * quantity,
      currency: 'INR',
    );
  }

  Future<void> logRemoveFromCart({
    required String itemId,
    required String itemName,
    required double price,
    required int quantity,
  }) async {
    await _analytics.logRemoveFromCart(
      items: [
        AnalyticsEventItem(
          itemId: itemId,
          itemName: itemName,
          price: price,
          quantity: quantity,
        ),
      ],
      value: price * quantity,
      currency: 'INR',
    );
  }

  Future<void> logBeginCheckout({
    required double value,
    required int totalItems,
  }) async {
    await _analytics.logBeginCheckout(
      value: value,
      currency: 'INR',
      items: [
        // Optional: Can include specific items here, but value is sufficient for top level
        AnalyticsEventItem(
          itemId: 'checkout',
          itemName: 'checkout_items',
          quantity: totalItems,
          price: value,
        )
      ]
    );
  }

  Future<void> logPurchaseAttempt({
    required String orderId,
    required double value,
  }) async {
    await _analytics.logEvent(
      name: 'purchase_attempt',
      parameters: {
        'order_id': orderId,
        'value': value,
        'currency': 'INR',
      },
    );
  }
}
