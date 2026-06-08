import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supermarket_app/core/theme/app_theme.dart';
import 'package:supermarket_app/domain/entities/product.dart';
import 'package:supermarket_app/presentation/widgets/product_card.dart';

void main() {
  final widths = [360.0, 393.0, 412.0];

  for (final width in widths) {
    testWidgets('GkProductCard does not overflow on width $width', (tester) async {
      // Set the viewport size
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final product = const Product(
        id: 'p1',
        name: 'Extremely Long Product Name That Will Wrap Multiple Lines To Check If It Overflows Properly',
        categoryId: 'cat1',
        price: 150.0,
        discountPrice: 120.0,
        unit: 'kg',
        quantityValue: 1.0,
        isAvailable: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width / 2 - 20, // simulate narrow grid column width
                  height: 250,
                  child: GkProductCard(
                    product: product,
                    quantity: 2,
                    onTap: () {},
                    onAdd: () {},
                    onIncrement: () {},
                    onDecrement: () {},
                    isWishlisted: true,
                    onToggleWishlist: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
