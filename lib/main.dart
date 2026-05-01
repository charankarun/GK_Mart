import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'auth_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/home_screen.dart';
import 'screens/wishlist_screen.dart';
import 'screens/account_screen.dart';
import 'screens/splash_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Supermarket App',

      theme: ThemeData(
          primaryColor: Color(0xFF0C8A7B), // teal-green (modern)

          scaffoldBackgroundColor:Colors.grey.shade100,

          colorScheme: ColorScheme.fromSeed(
            seedColor: Color(0xFF0C8A7B),
            primary: Color(0xFF0C8A7B),
            secondary: Color(0xFF00C853),
          ),

          appBarTheme: AppBarTheme(
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: false,
            iconTheme: IconThemeData(color: Colors.black),
            titleTextStyle: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF0C8A7B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
          ),

          textTheme: TextTheme(
            bodyMedium: TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ),

      home: SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return MainScreen();
        }

        return AuthScreen();
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    HomePage(),
    WishlistScreen(),
    AccountPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: _screens[_selectedIndex],

      // ✅ MODERN BOTTOM NAV
      bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Color(0xFF6C63FF),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
              ),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            backgroundColor: Color(0xFF6C63FF),

            // ✅ FIX COLORS
            selectedItemColor: Colors.white,
            unselectedItemColor: Colors.white70,

            // ✅ IMPORTANT (fix icon disappearing)
            type: BottomNavigationBarType.fixed,

            // ✅ remove shifting behavior
            showUnselectedLabels: true,

            items: [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: "Home",
                ),

                BottomNavigationBarItem(
                  icon: StreamBuilder(
                    stream: user == null
                        ? null
                        : FirebaseFirestore.instance
                            .collection('wishlist')
                            .doc(user.uid)
                            .collection('items')
                            .snapshots(),
                    builder: (context, snapshot) {

                      int count = snapshot.hasData ? snapshot.data!.docs.length : 0;

                      return Stack(
                        children: [
                          Icon(Icons.favorite),

                          if (count > 0)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  "$count",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  label: "Wishlist",
                ),

                BottomNavigationBarItem(
                  icon: Icon(Icons.person),
                  label: "Account",
                ),
              ],
          ),
        ),
    );
  }
}
