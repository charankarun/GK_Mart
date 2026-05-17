import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
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
import 'presentation/providers/wishlist_provider.dart';
import 'presentation/screens/account_screen.dart';
import 'presentation/screens/admin_shell_screen.dart';
import 'presentation/screens/auth_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/orders_screen.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/wishlist_screen.dart';

Future<void> main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    AppErrorHandler.initialize();
    runApp(const ProviderScope(child: MyApp()));
  }, AppErrorHandler.report);
}

Future<void> _initializeFirebase() async {
  await Firebase.initializeApp().timeout(AppDurations.startupTimeout);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );
  await _initializeNotifications();
}

Future<void> _initializeNotifications() async {
  try {
    await NotificationService.instance.initialize(
      onNotificationSelected: NotificationNavigationService.instance.open,
    );
  } catch (error, stackTrace) {
    AppErrorHandler.report(error, stackTrace);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<void> _firebaseInitialization;

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
      home: FutureBuilder<void>(
        future: _firebaseInitialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AppStartLogoScreen();
          }

          if (snapshot.hasError) {
            return _AppStartErrorScreen(onRetry: _retryStartup);
          }

          return const SplashScreen();
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppStartLogoScreen extends StatelessWidget {
  const AppStartLogoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.cream,
      body: Center(
        child: _GkLogoMark(),
      ),
    );
  }
}

class _GkLogoMark extends StatelessWidget {
  const _GkLogoMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 82,
          height: 82,
          decoration: const BoxDecoration(
            color: AppColors.softGreen,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.shopping_cart_rounded,
            color: AppColors.primary,
            size: 42,
          ),
        ),
        const SizedBox(height: 16),
        const Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'GK ',
                style: TextStyle(color: AppColors.primary),
              ),
              TextSpan(
                text: 'MART',
                style: TextStyle(color: AppColors.accent),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _AppStartErrorScreen extends StatelessWidget {
  const _AppStartErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Unable to start GK Mart. Please try again.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NotificationNavigationService.instance.processPending();
        });
      }
    });

    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (session) =>
          session == null ? const AuthScreen() : const MainScreen(),
      loading: () => const AppStartLogoScreen(),
      error: (_, __) => const AuthScreen(),
    );
  }
}

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

  void _resetTabStack(int index) {
    if (index < 0 || index >= _tabNavigatorKeys.length) return;

    _tabNavigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
  }

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

    if (isAdminMode) {
      return const AdminShellScreen();
    }

    final wishlistCount =
        session == null ? 0 : ref.watch(wishlistCountProvider(session.uid));

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
                  icon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Stack(
                    children: [
                      const Icon(Icons.favorite_border_rounded),
                      if (wishlistCount > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$wishlistCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  label: 'Wishlist',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.receipt_long_rounded),
                  label: 'Orders',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline_rounded),
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
