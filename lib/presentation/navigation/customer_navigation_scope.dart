import 'package:flutter/widgets.dart';

typedef CustomerTabSelector = void Function(
  int index, {
  bool resetCurrentStack,
  bool resetTargetStack,
});

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
  static const accountTab = 3;

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

  @override
  bool updateShouldNotify(CustomerNavigationScope oldWidget) {
    return selectedIndex != oldWidget.selectedIndex ||
        selectTab != oldWidget.selectTab;
  }
}
