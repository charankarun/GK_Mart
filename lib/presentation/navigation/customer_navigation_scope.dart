// ==============================================================================
// FILE: lib/presentation/navigation/customer_navigation_scope.dart
// PURPOSE: InheritedWidget defining scoped navigation selectors for customer tabs.
// LAYER: Presentation / Navigation Scopes
// DEPENDENCIES: flutter widgets
//
// ARCHITECTURAL ROLE:
// Exposes scoped methods to reset view states and trigger tab navigation actions
// (e.g. redirecting from checkout completion to the orders list tab).
// ==============================================================================

import 'package:flutter/widgets.dart';

typedef CustomerTabSelector = void Function(
  int index, {
  bool resetCurrentStack,
  bool resetTargetStack,
});

/// Navigation context scope for managing bottom tab selections and deep link redirections.
class CustomerNavigationScope extends InheritedWidget {
  const CustomerNavigationScope({
    super.key,
    required this.selectedIndex,
    required this.selectTab,
    required super.child,
  });

  static const homeTab = 0;
  static const wishlistTab = 1;
  static const ordersTab = 2;
  static const cartTab = 3;
  static const accountTab = 4;

  final int selectedIndex;
  final CustomerTabSelector selectTab;

  static CustomerNavigationScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CustomerNavigationScope>();
  }

  static void openHome(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    scope.selectTab(
      homeTab,
      resetCurrentStack: true,
      resetTargetStack: true,
    );
  }

  static void openOrders(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    scope.selectTab(
      ordersTab,
      resetCurrentStack: true,
      resetTargetStack: true,
    );
  }

  static void openCart(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    scope.selectTab(
      cartTab,
      resetCurrentStack: true,
      resetTargetStack: true,
    );
  }

  @override
  bool updateShouldNotify(CustomerNavigationScope oldWidget) {
    return selectedIndex != oldWidget.selectedIndex ||
        selectTab != oldWidget.selectTab;
  }
}
