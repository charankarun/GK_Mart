import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_app/domain/entities/product.dart';

void main() {
  group('Product Quantity and Unit Formatting Tests', () {
    test('Should hide gracefully if quantityValue is missing', () {
      const product = Product(
        id: 'test-1',
        name: 'Milk',
        categoryId: 'cat-1',
        price: 50.0,
        unit: 'ml',
        quantityValue: null,
      );
      expect(product.formattedQuantityUnit, '');
    });

    test('Should hide gracefully if unit is empty', () {
      const product = Product(
        id: 'test-2',
        name: 'Rice',
        categoryId: 'cat-1',
        price: 80.0,
        unit: '',
        quantityValue: 5.0,
      );
      expect(product.formattedQuantityUnit, '');
    });

    test('Should strip trailing .0 from whole numbers', () {
      const product = Product(
        id: 'test-3',
        name: 'Sugar',
        categoryId: 'cat-1',
        price: 45.0,
        unit: 'Kg',
        quantityValue: 5.0,
      );
      expect(product.formattedQuantityUnit, '5 Kg');
    });

    test('Should keep decimals for non-whole numbers', () {
      const product = Product(
        id: 'test-4',
        name: 'Oil',
        categoryId: 'cat-1',
        price: 180.0,
        unit: 'L',
        quantityValue: 1.5,
      );
      expect(product.formattedQuantityUnit, '1.5 L');
    });

    test('Should pluralize count-based units when quantity > 1', () {
      final testCases = [
        {'qty': 1.0, 'unit': 'Piece', 'expected': '1 Piece'},
        {'qty': 12.0, 'unit': 'Piece', 'expected': '12 Pieces'},
        {'qty': 1.0, 'unit': 'Pack', 'expected': '1 Pack'},
        {'qty': 3.0, 'unit': 'Pack', 'expected': '3 Packs'},
        {'qty': 1.0, 'unit': 'Packet', 'expected': '1 Packet'},
        {'qty': 2.0, 'unit': 'Packet', 'expected': '2 Packets'},
        {'qty': 1.0, 'unit': 'Bottle', 'expected': '1 Bottle'},
        {'qty': 6.0, 'unit': 'Bottle', 'expected': '6 Bottles'},
        {'qty': 1.0, 'unit': 'Box', 'expected': '1 Box'},
        {'qty': 5.0, 'unit': 'Box', 'expected': '5 Boxes'},
        {'qty': 1.0, 'unit': 'Dozen', 'expected': '1 Dozen'},
        {'qty': 2.0, 'unit': 'Dozen', 'expected': '2 Dozens'},
      ];

      for (final tc in testCases) {
        final product = Product(
          id: 'test-plural',
          name: 'Item',
          categoryId: 'cat-1',
          price: 10.0,
          unit: tc['unit'] as String,
          quantityValue: tc['qty'] as double,
        );
        expect(product.formattedQuantityUnit, tc['expected'] as String);
      }
    });

    test('Should NOT pluralize measurement units when quantity > 1', () {
      final testCases = [
        {'qty': 5.0, 'unit': 'Kg', 'expected': '5 Kg'},
        {'qty': 500.0, 'unit': 'g', 'expected': '500 g'},
        {'qty': 2.0, 'unit': 'L', 'expected': '2 L'},
        {'qty': 500.0, 'unit': 'ml', 'expected': '500 ml'},
      ];

      for (final tc in testCases) {
        final product = Product(
          id: 'test-measurement',
          name: 'Item',
          categoryId: 'cat-1',
          price: 10.0,
          unit: tc['unit'] as String,
          quantityValue: tc['qty'] as double,
        );
        expect(product.formattedQuantityUnit, tc['expected'] as String);
      }
    });
  });
}
