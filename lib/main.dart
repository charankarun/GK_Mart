// ==============================================================================
// FILE: lib/main.dart
// PURPOSE: Application entry point and startup initialization configuration.
// LAYER: Presentation / Application Root
// DEPENDENCIES: flutter, flutter_riverpod, firebase_core, firebase_messaging
//
// ARCHITECTURAL ROLE:
// Bootstraps the Flutter framework, initializes external Firebase services 
// (Authentication, Firestore, Cloud Messaging, App Check), sets up application-wide
// error boundaries via AppErrorHandler, and wraps the UI with ProviderScope.
// Configures top-level routing shells (AuthWrapper, MainScreen) and hooks up
// notification listeners and custom authorization claim updates.
// ==============================================================================

import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'core/constants/app_constants.dart';
import 'core/errors/app_error_handler.dart';
import 'core/notifications/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'domain/entities/auth_session.dart';
import 'presentation/navigation/customer_navigation_scope.dart';
import 'presentation/navigation/notification_navigation_service.dart';
import 'presentation/providers/auth_providers.dart';
import 'presentation/providers/admin_mode_provider.dart';
import 'presentation/providers/commerce_providers.dart';
import 'presentation/providers/wishlist_provider.dart';
import 'presentation/screens/account_screen.dart';
import 'presentation/screens/admin_shell_screen.dart';
import 'presentation/screens/auth_screen.dart';
import 'presentation/screens/cart_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/orders_screen.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/wishlist_screen.dart';
import 'presentation/widgets/app_bottom_nav_icon.dart';

/// The main execution callback called when the application is launched.
/// Runs inside runZonedGuarded to catch unhandled asynchronous exceptions.
Future<void> main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    AppErrorHandler.initialize();
    runApp(const ProviderScope(child: MyApp()));
  }, AppErrorHandler.report);
}

/// Firebase Initialization setup sequence.
/// Activates Firebase App Check, enables offline caching storage settings, 
/// and configures push notification channels.
Future<void> _initializeFirebase() async {
  await Firebase.initializeApp().timeout(AppDurations.startupTimeout);
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode
          ? AppleProvider.debug
          : AppleProvider.deviceCheck, // Cleaned up the name here!
    );
  } catch (error, stackTrace) {
    developer.log(
      'Firebase App Check failed to initialize.',
      error: error,
      stackTrace: stackTrace,
      name: 'AppCheckInit',
      // Safe logger callback for monitoring validation integrity
    );
  }
  // PERFORMANCE: Offline persistence enabled for Firestore queries
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );
  await _initializeNotifications();
}

/// Sets up local and background notification routing capabilities.
Future<void> _initializeNotifications() async {
  try {
    await NotificationService.instance.initialize(
      onNotificationSelected: NotificationNavigationService.instance.open,
    );
  } catch (error, stackTrace) {
    AppErrorHandler.report(error, stackTrace);
  }
}

/// The root Widget of the GK Mart application.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Future<void> _firebaseInitialization;

  @override
  void initState() {
    super.initState();
    _firebaseInitialization = _initializeFirebase();
  }

  void _retryStartup() {
    setState(() {
      _firebaseInitialization = _initializeFirebase();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GK Mart',
      theme: AppTheme.light(),
      navigatorKey: NotificationNavigationService.navigatorKey,
      scaffoldMessengerKey: AppErrorHandler.scaffoldMessengerKey,
      home: SplashScreen(
        startup: _firebaseInitialization,
        onRetry: _retryStartup,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// AuthWrapper coordinates access control on launch or session updates.
/// Listens to authentication state streams and redirects user to
/// either the AuthScreen or the MainScreen navigation container.
class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // SECURITY & BUSINESS RULE: Detects login changes.
    // Unregisters obsolete messaging tokens and registers new FCM tokens.
    ref.listen<AuthSession?>(currentSessionProvider, (previous, next) {
      final previousUid = previous?.uid;
      final nextUid = next?.uid;
      if (previousUid != null && previousUid != nextUid) {
        unawaited(
          NotificationService.instance.unregisterDeviceForUser(previousUid),
        );
      }
      if (nextUid != null) {
        unawaited(NotificationService.instance.registerDeviceForUser(nextUid));
        NotificationService.instance.startOrderNotificationListeners(
          uid: nextUid,
          isAdmin: false,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NotificationNavigationService.instance.processPending();
        });
      }
    });

    // SECURITY: Checks isAdmin claims updates from backend token revisions.
    // Directs administrators to active admin screens options.
    ref.listen<AsyncValue<bool>>(isAdminProvider, (previous, next) {
      final uid = ref.read(currentSessionProvider)?.uid;
      if (uid == null || uid.trim().isEmpty) return;

      final previousAdmin = previous?.maybeWhen(
            data: (v) => v,
            orElse: () => false,
          ) ??
          false;
      final isAdmin = next.maybeWhen(
        data: (value) => value,
        orElse: () => false,
      );
      NotificationService.instance.setAdminNotificationsEnabled(
        uid: uid,
        enabled: isAdmin,
      );
      if (isAdmin && !previousAdmin) {
        ref.read(adminModeProvider.notifier).setEnabled(true);
      }
    });

    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (session) =>
          session == null ? const AuthScreen() : const MainScreen(),
      loading: () => const _AuthLoadingScreen(),
      error: (_, __) => const AuthScreen(),
    );
  }
}

/// Fallback loading screen displayed during session extraction.
class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.cream,
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.6,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

/// MainScreen provides the tab-scoped navigation shell for customers.
/// Hosts the bottom navigation bar and coordinates active screen indexes.
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    HomePage(),
    WishlistScreen(),
    OrdersScreen(),
    CartScreen(),
    AccountPage(),
  ];

  late final List<GlobalKey<NavigatorState>> _tabNavigatorKeys =
      List.generate(_screens.length, (_) => GlobalKey<NavigatorState>());

  void _onItemTapped(int index) {
    if (index == _selectedIndex) {
      _resetTabStack(index);
      return;
    }

    _selectTab(index);
  }

  void _selectTab(
    int index, {
    bool resetCurrentStack = false,
    bool resetTargetStack = false,
  }) {
    if (index < 0 || index >= _screens.length) return;

    if (resetCurrentStack) _resetTabStack(_selectedIndex);
    if (resetTargetStack) _resetTabStack(index);

    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  /// Popping nested view stacks on tab re-selection.
  void _resetTabStack(int index) {
    if (index < 0 || index >= _tabNavigatorKeys.length) return;

    _tabNavigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
  }

  /// System back button intercepter, routes to primary Home tab 
  /// before exiting the application completely.
  void _handleBackNavigation(bool didPop, Object? result) {
    if (didPop) return;

    final currentNavigator = _tabNavigatorKeys[_selectedIndex].currentState;
    if (currentNavigator?.canPop() == true) {
      currentNavigator!.pop();
      return;
    }

    if (_selectedIndex != CustomerNavigationScope.homeTab) {
      setState(() => _selectedIndex = CustomerNavigationScope.homeTab);
      return;
    }

    SystemNavigator.pop();
  }

  Widget _buildTabNavigator(int index) {
    return Navigator(
      key: _tabNavigatorKeys[index],
      onGenerateRoute: (settings) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => _screens[index],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);
    final isAdminMode = ref.watch(effectiveAdminModeProvider);

    // SECURITY: Auto-routes to administrative interface shell if admin mode is activated.
    if (isAdminMode) {
      return const AdminShellScreen();
    }

    final wishlistCount =
        session == null ? 0 : ref.watch(wishlistCountProvider(session.uid));
    final cartCount = ref.watch(cartItemCountProvider);

    return CustomerNavigationScope(
      selectedIndex: _selectedIndex,
      selectTab: _selectTab,
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: _handleBackNavigation,
        child: Scaffold(
          body: IndexedStack(
            index: _selectedIndex,
            children: List.generate(_screens.length, _buildTabNavigator),
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              items: [
                const BottomNavigationBarItem(
                  icon: AppBottomNavIcon(
                    icon: Icons.home_rounded,
                    selected: false,
                  ),
                  activeIcon: AppBottomNavIcon(
                    icon: Icons.home_rounded,
                    selected: true,
                  ),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: AppBottomNavIcon(
                    icon: Icons.favorite_border_rounded,
                    selected: false,
                    badgeCount: wishlistCount,
                  ),
                  activeIcon: AppBottomNavIcon(
                    icon: Icons.favorite_rounded,
                    selected: true,
                    badgeCount: wishlistCount,
                  ),
                  label: 'Wishlist',
                ),
                BottomNavigationBarItem(
                  icon: AppBottomNavIcon(
                    icon: Icons.receipt_long_rounded,
                    selected: false,
                  ),
                  activeIcon: AppBottomNavIcon(
                    icon: Icons.receipt_long_rounded,
                    selected: true,
                  ),
                  label: 'Orders',
                ),
                BottomNavigationBarItem(
                  icon: AppBottomNavIcon(
                    icon: Icons.shopping_cart_outlined,
                    selected: false,
                    badgeCount: cartCount,
                  ),
                  activeIcon: AppBottomNavIcon(
                    icon: Icons.shopping_cart_rounded,
                    selected: true,
                    badgeCount: cartCount,
                  ),
                  label: 'Cart',
                ),
                const BottomNavigationBarItem(
                  icon: AppBottomNavIcon(
                    icon: Icons.person_outline_rounded,
                    selected: false,
                  ),
                  activeIcon: AppBottomNavIcon(
                    icon: Icons.person_rounded,
                    selected: true,
                  ),
                  label: 'Account',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
