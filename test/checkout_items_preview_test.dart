import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_app/core/theme/app_theme.dart';
import 'package:supermarket_app/domain/entities/auth_session.dart';
import 'package:supermarket_app/domain/entities/app_user.dart';
import 'package:supermarket_app/domain/entities/cart_item.dart';
import 'package:supermarket_app/domain/entities/cart_pricing.dart';
import 'package:supermarket_app/domain/entities/store_config.dart';
import 'package:supermarket_app/presentation/providers/auth_providers.dart';
import 'package:supermarket_app/presentation/providers/commerce_providers.dart';
import 'package:supermarket_app/presentation/providers/order_providers.dart';
import 'package:supermarket_app/presentation/providers/store_providers.dart';
import 'package:supermarket_app/presentation/screens/checkout_screen.dart';
import 'package:supermarket_app/presentation/widgets/app_cached_network_image.dart';
import 'package:supermarket_app/services/analytics_service.dart';

void main() {
  late FakeAnalyticsService fakeAnalytics;

  setUp(() {
    fakeAnalytics = FakeAnalyticsService();
  });

  Widget createCheckoutScreen({required List<CartItem> items}) {
    final originalAmount = items.fold<double>(0, (sum, item) => sum + item.price * item.quantity);
    final finalPayable = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final totalSavings = originalAmount - finalPayable;

    final pricing = CartPricingSummary(
      originalAmount: originalAmount,
      productSavings: totalSavings,
      cartDiscount: 0,
      deliveryFee: 0,
    );

    return ProviderScope(
      overrides: [
        currentSessionProvider.overrideWithValue(
          const AuthSession(uid: 'test-user', phoneNumber: '+919876543210'),
        ),
        currentUserProfileProvider.overrideWithValue(
          const AsyncValue.data(
            AppUser(
              uid: 'test-user',
              name: 'John Doe',
              phone: '+919876543210',
              address: '123 Test Street 515301',
            ),
          ),
        ),
        activeAddressProvider.overrideWith((ref) => ActiveAddressNotifier(ref)),
        cartItemsProvider.overrideWithValue(items),
        cartPricingSummaryProvider.overrideWithValue(pricing),
        storeConfigProvider.overrideWithValue(
          const AsyncValue.data(
            StoreConfig(
              storeEnabled: true,
              openHour: 0,
              openMinute: 0,
              closeHour: 23,
              closeMinute: 59,
            ),
          ),
        ),
        serviceablePincodesProvider.overrideWithValue({'515301'}),
        analyticsServiceProvider.overrideWithValue(fakeAnalytics),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const CheckoutScreen(),
      ),
    );
  }

  group('Checkout Screen Items Preview bottom sheet', () {
    testWidgets('Tapping on thumbnail preview opens modal bottom sheet with correct items and subtotal', (tester) async {
      final cartItems = [
        const CartItem(productId: 'p1', name: 'Apples', price: 120.0, quantity: 2, unit: '1 kg', imageUrl: ''),
        const CartItem(productId: 'p2', name: 'Bananas', price: 60.0, quantity: 3, unit: '500 g', imageUrl: ''),
        const CartItem(productId: 'p3', name: 'Oranges', price: 80.0, quantity: 1, unit: '1 kg', imageUrl: ''),
        const CartItem(productId: 'p4', name: 'Milk', price: 30.0, quantity: 2, unit: '1 L', imageUrl: ''),
      ];

      await tester.pumpWidget(createCheckoutScreen(items: cartItems));
      await tester.pumpAndSettle();

      // Find the "+1 more" block or thumbnails
      final moreFinder = find.text('+1\nmore');
      expect(moreFinder, findsOneWidget);

      // Tap on the "+1 more" block to trigger bottom sheet
      await tester.tap(moreFinder);
      await tester.pumpAndSettle();

      // Verify bottom sheet is displayed
      final bottomSheetFinder = find.byType(BottomSheet);
      expect(bottomSheetFinder, findsOneWidget);
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('Items in Cart (4)')), findsOneWidget);

      // Verify all items are rendered inside bottom sheet
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('Apples')), findsOneWidget);
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('Bananas')), findsOneWidget);
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('Oranges')), findsOneWidget);
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('Milk')), findsOneWidget);

      // Verify quantities are shown correctly
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('x2')), findsNWidgets(2)); // Apples (x2) and Milk (x2)
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('x3')), findsOneWidget); // Bananas (x3)
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('x1')), findsOneWidget); // Oranges (x1)

      // Verify individual subtotal values
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('₹240')), findsOneWidget); // Apples line total
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('₹180')), findsOneWidget); // Bananas line total
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('₹80')), findsOneWidget);  // Oranges line total
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('₹60')), findsOneWidget);  // Milk line total

      // Verify sticky subtotal row at the bottom
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('Subtotal')), findsOneWidget);
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('8 items')), findsOneWidget); // Total qty: 2 + 3 + 1 + 2 = 8
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('₹560')), findsOneWidget);  // Total sum: 240 + 180 + 80 + 60 = 560

      // Tap close button to dismiss bottom sheet
      final closeButtonFinder = find.byIcon(Icons.close_rounded);
      expect(closeButtonFinder, findsOneWidget);
      await tester.tap(closeButtonFinder);
      await tester.pumpAndSettle();

      // Bottom sheet should be dismissed
      expect(find.text('Items in Cart (4)'), findsNothing);
    });

    testWidgets('Tapping on any product thumbnail also opens bottom sheet', (tester) async {
      final cartItems = [
        const CartItem(productId: 'p1', name: 'Apples', price: 120.0, quantity: 2, unit: '1 kg', imageUrl: ''),
      ];

      await tester.pumpWidget(createCheckoutScreen(items: cartItems));
      await tester.pumpAndSettle();

      // Find individual item preview thumbnail
      final thumbnailFinder = find.byType(AppCachedNetworkImage);
      expect(thumbnailFinder, findsOneWidget);

      // Tap on it
      await tester.tap(thumbnailFinder);
      await tester.pumpAndSettle();

      // Verify bottom sheet is displayed
      final bottomSheetFinder = find.byType(BottomSheet);
      expect(bottomSheetFinder, findsOneWidget);
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('Items in Cart (1)')), findsOneWidget);
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('Apples')), findsOneWidget);
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('2 items')), findsOneWidget);
      expect(find.descendant(of: bottomSheetFinder, matching: find.text('₹240')), findsNWidgets(2)); // line total and subtotal total
    });

    testWidgets('Bill details card is collapsed by default and expands/collapses on tapping the header', (tester) async {
      final cartItems = [
        const CartItem(productId: 'p1', name: 'Apples', price: 120.0, quantity: 2, unit: '1 kg', imageUrl: ''),
        const CartItem(productId: 'p2', name: 'Bananas', price: 60.0, quantity: 3, unit: '500 g', imageUrl: ''),
      ];

      final pricing = const CartPricingSummary(
        originalAmount: 450.0,
        productSavings: 30.0,
        cartDiscount: 10.0,
        deliveryFee: 15.0,
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentSessionProvider.overrideWithValue(
            const AuthSession(uid: 'test-user', phoneNumber: '+919876543210'),
          ),
          currentUserProfileProvider.overrideWithValue(
            const AsyncValue.data(
              AppUser(
                uid: 'test-user',
                name: 'John Doe',
                phone: '+919876543210',
                address: '123 Test Street 515301',
              ),
            ),
          ),
          activeAddressProvider.overrideWith((ref) => ActiveAddressNotifier(ref)),
          cartItemsProvider.overrideWithValue(cartItems),
          cartPricingSummaryProvider.overrideWithValue(pricing),
          storeConfigProvider.overrideWithValue(
            const AsyncValue.data(
              StoreConfig(
                storeEnabled: true,
                openHour: 0,
                openMinute: 0,
                closeHour: 23,
                closeMinute: 59,
              ),
            ),
          ),
          serviceablePincodesProvider.overrideWithValue({'515301'}),
          analyticsServiceProvider.overrideWithValue(fakeAnalytics),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const CheckoutScreen(),
        ),
      ));
      await tester.pumpAndSettle();

      // Check that "Bill Details" header is visible
      expect(find.text('Bill Details'), findsOneWidget);

      // Check savings chip in header is visible (totalSavings = productSavings (30) + cartDiscount (10) = 40)
      expect(find.text('Saved ₹40'), findsOneWidget);

      // Check Final Payable is visible (Final Payable = 450 - 10 + 15 = 455)
      expect(find.text('₹455'), findsOneWidget);

      // Breakdown rows should NOT be visible by default (collapsed)
      expect(find.text('Original Amount'), findsNothing);
      expect(find.text('Product Savings'), findsNothing);
      expect(find.text('Cart Discount'), findsNothing);
      expect(find.text('Delivery Fee'), findsNothing);

      // Tap on the header to expand
      await tester.tap(find.text('Bill Details'));
      await tester.pumpAndSettle();

      // Breakdown rows should now be visible
      expect(find.text('Original Amount'), findsOneWidget);
      expect(find.text('Product Savings'), findsOneWidget);
      expect(find.text('Cart Discount'), findsOneWidget);
      expect(find.text('Delivery Fee'), findsOneWidget);

      // Verify breakdown values
      expect(find.text('₹450'), findsOneWidget);
      expect(find.text('-₹30'), findsOneWidget);
      expect(find.text('-₹10'), findsOneWidget);
      expect(find.text('₹15'), findsOneWidget);

      // Tap on the header again to collapse
      await tester.tap(find.text('Bill Details'));
      await tester.pumpAndSettle();

      // Breakdown rows should be hidden again
      expect(find.text('Original Amount'), findsNothing);
      expect(find.text('Product Savings'), findsNothing);
      expect(find.text('Cart Discount'), findsNothing);
      expect(find.text('Delivery Fee'), findsNothing);
    });
  });
}

class FakeAnalyticsService implements AnalyticsService {
  @override
  dynamic get _analytics => null;

  @override
  Future<void> logLogin(String method) async {}

  @override
  Future<void> logAddToCart({
    required String itemId,
    required String itemName,
    required double price,
    required int quantity,
  }) async {}

  @override
  Future<void> logRemoveFromCart({
    required String itemId,
    required String itemName,
    required double price,
    required int quantity,
  }) async {}

  @override
  Future<void> logBeginCheckout({
    required double value,
    required int totalItems,
  }) async {}

  @override
  Future<void> logPurchaseAttempt({
    required String orderId,
    required double value,
  }) async {}
}
