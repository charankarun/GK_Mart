import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supermarket_app/core/theme/app_theme.dart';
import 'package:supermarket_app/domain/entities/product.dart';
import 'package:supermarket_app/presentation/widgets/product_card.dart';

void main() {
  testWidgets('GkProductCard renders all required elements without clipping or overflow at optimized heights', (tester) async {
    // Set a phone layout viewport
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final product = const Product(
      id: 'p1',
      name: 'Super Premium Extra Long Grain Basmati Rice Bag 5kg Pack', // Long name
      categoryId: 'staples',
      price: 900.0,
      discountPrice: 750.0, // Discount badge will show 17% OFF
      unit: 'kg',
      quantityValue: 5.0,
      trackStock: true,
      stockQuantity: 5, // Low stock label will show 'Only 5 left!'
      isAvailable: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 142, // Width of card in horizontal scroll
                height: 225, // Height of card in horizontal scroll (optimized from 240)
                child: GkProductCard(
                  product: product,
                  quantity: 1,
                  onTap: () {},
                  onAdd: () {},
                  onIncrement: () {},
                  onDecrement: () {},
                  isWishlisted: true, // Wishlist icon will be active
                  onToggleWishlist: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify no overflow exception was thrown
    expect(tester.takeException(), isNull);

    // Verify all required elements are found and visible in the card
    // 1. Discount Badge
    expect(find.text('17% OFF'), findsOneWidget);

    // 2. Wishlist Icon
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    // 3. Product Name (or substring)
    expect(find.textContaining('Super Premium Extra Long'), findsOneWidget);

    // 4. Unit
    expect(find.text('5 kg'), findsOneWidget);

    // 5. Low stock warning
    expect(find.text('Only 5 left!'), findsOneWidget);

    // 6. Price section
    expect(find.text('₹750'), findsOneWidget); // selling price
    expect(find.text('₹900'), findsOneWidget); // original price

    // 7. Quantity stepper/Add button
    expect(find.text('1'), findsOneWidget); // quantity indicator
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
  });

  testWidgets('GkProductCard hides low stock warning and displays Out of Stock when stockQuantity is 0', (tester) async {
    final product = const Product(
      id: 'p2',
      name: 'Test Milk Bottle',
      categoryId: 'dairy',
      price: 50.0,
      unit: 'ml',
      quantityValue: 500.0,
      trackStock: true,
      stockQuantity: 0,
      isAvailable: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 142,
                height: 225,
                child: GkProductCard(
                  product: product,
                  quantity: 0,
                  onTap: () {},
                  onAdd: () {},
                  onIncrement: () {},
                  onDecrement: () {},
                  isWishlisted: false,
                  onToggleWishlist: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify low stock warning is not shown
    expect(find.textContaining('left!'), findsNothing);

    // Verify Out of Stock state is shown
    expect(find.text('Out of Stock'), findsOneWidget);
  });
}
