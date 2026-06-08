import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_app/core/theme/app_theme.dart';
import 'package:supermarket_app/domain/entities/auth_session.dart';
import 'package:supermarket_app/domain/entities/cart_item.dart';
import 'package:supermarket_app/domain/entities/cart_pricing.dart';
import 'package:supermarket_app/presentation/providers/auth_providers.dart';
import 'package:supermarket_app/presentation/providers/commerce_providers.dart';
import 'package:supermarket_app/presentation/screens/cart_screen.dart';

void main() {
  Widget createCartScreen({required List<CartItem> items, required CartPricingSummary pricing}) {
    return ProviderScope(
      overrides: [
        currentSessionProvider.overrideWithValue(
          const AuthSession(uid: 'test-user', phoneNumber: '+919876543210'),
        ),
        cartItemsProvider.overrideWithValue(items),
        cartPricingSummaryProvider.overrideWithValue(pricing),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const CartScreen(),
      ),
    );
  }

  testWidgets('Cart screen shows compact summary rows and no expandable Bill Details card', (tester) async {
    final cartItems = [
      const CartItem(productId: 'p1', name: 'Apples', price: 120.0, quantity: 2, unit: '1 kg', imageUrl: ''),
    ];

    final pricing = const CartPricingSummary(
      originalAmount: 240.0,
      productSavings: 40.0,
      cartDiscount: 10.0,
      deliveryFee: 0.0, // Free delivery
    );

    await tester.pumpWidget(createCartScreen(items: cartItems, pricing: pricing));
    await tester.pumpAndSettle();

    // Verify subtotal row is shown
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('₹240'), findsOneWidget);

    // Verify savings row is shown (productSavings (40) + cartDiscount (10) = 50)
    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('-₹50'), findsOneWidget);

    // Verify delivery row shows "Free"
    expect(find.text('Delivery'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);

    // Verify total row is shown (finalPayable = 240 - 10 + 0 = 230)
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('₹230'), findsOneWidget);

    // Verify compact chip Saved ₹50 is shown
    expect(find.text('Saved ₹50'), findsOneWidget);

    // Verify no expandable banner or "Bill Details" title is shown
    expect(find.text('Bill Details'), findsNothing);
    expect(find.textContaining('You saved'), findsNothing);
  });
}
