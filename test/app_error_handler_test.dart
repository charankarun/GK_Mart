import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_app/core/errors/app_error_handler.dart';
import 'package:supermarket_app/presentation/navigation/notification_navigation_service.dart';

void main() {
  group('AppErrorHandler Tests', () {
    testWidgets('showGlobalError does not crash when no scaffold messenger is mounted', (tester) async {
      // Setup: Ensure we do not crash when there is no MaterialApp/ScaffoldMessenger
      expect(() => AppErrorHandler.showGlobalError('Test Error'), returnsNormally);
    });

    testWidgets('showGlobalError displays SnackBar post-frame if called during rebuild', (tester) async {
      final scaffoldKey = AppErrorHandler.scaffoldMessengerKey;
      final navKey = NotificationNavigationService.navigatorKey;

      final rebuildNotifier = ValueNotifier<int>(0);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          scaffoldMessengerKey: scaffoldKey,
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: rebuildNotifier,
              builder: (context, value, child) {
                if (value > 0) {
                  // Call showGlobalError synchronously during this build phase with fallbackMessage
                  AppErrorHandler.showGlobalError('Some Error', fallbackMessage: 'Error during build');
                }
                return Text('Value: $value');
              },
            ),
          ),
        ),
      );

      // Verify the initial widget builds successfully and key is populated
      expect(find.text('Value: 0'), findsOneWidget);
      expect(scaffoldKey.currentState, isNotNull);

      // Trigger a rebuild (so we are in a build phase but the ScaffoldMessenger exists)
      rebuildNotifier.value = 1;
      await tester.pump(); // Executes the rebuild and triggers postFrameCallback
      await tester.pump(); // Executes the frame scheduled by showSnackBar to render it

      // Verify the SnackBar was safely displayed
      expect(find.text('Error during build'), findsOneWidget);
    });

    testWidgets('showErrorSnackBar does not crash when context is unmounted', (tester) async {
      // Build a widget to get a valid context
      BuildContext? capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(capturedContext, isNotNull);

      // Now unmount the widget tree by pumping a different widget
      await tester.pumpWidget(const SizedBox());

      // Context is now unmounted. Calling showErrorSnackBar should return cleanly.
      expect(
        () => AppErrorHandler.showErrorSnackBar(capturedContext!, 'Unmounted Error'),
        returnsNormally,
      );
    });
  });
}
