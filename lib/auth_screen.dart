import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/phone_auth_screen.dart';

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  void openOtpLogin({bool fromForgotPassword = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhoneAuthScreen(
          title: fromForgotPassword ? "Login with OTP" : "Login with Phone",
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

    void submit() async {
      try {
        // 🔒 Basic validation
        if (emailController.text.trim().isEmpty ||
            passwordController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Email & Password required")),
          );
          return;
        }

        if (!isLogin &&
            (nameController.text.trim().isEmpty ||
                phoneController.text.trim().isEmpty)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("All fields required")),
          );
          return;
        }

        if (isLogin) {
          // 🔑 LOGIN
          await _auth.signInWithEmailAndPassword(
            email: emailController.text.trim(),
            password: passwordController.text.trim(),
          );
        } else {
          // 🆕 SIGNUP
          UserCredential userCredential =
              await _auth.createUserWithEmailAndPassword(
            email: emailController.text.trim(),
            password: passwordController.text.trim(),
          );

          // ✅ SAVE USER DATA
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid)
              .set({
            'name': nameController.text.trim(),
            'email': emailController.text.trim(),
            'phone': phoneController.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
          });

          // ✅ Optional success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Account created successfully")),
          );
        }
      } on FirebaseAuthException catch (e) {
        String message = "Something went wrong";

        if (e.code == 'email-already-in-use') {
          message = "Email already in use";
        } else if (e.code == 'invalid-email') {
          message = "Invalid email";
        } else if (e.code == 'weak-password') {
          message = "Password too weak";
        } else if (e.code == 'user-not-found') {
          message = "User not found";
        } else if (e.code == 'wrong-password') {
          message = "Wrong password";
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error occurred")),
        );
      }
    }

Widget _buildTextField(TextEditingController controller, String hint,
    IconData icon,
    {bool isPassword = false}) {
  return TextField(
    controller: controller,
    obscureText: isPassword,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              SizedBox(height: 40),

              // 🟣 APP TITLE
              Text(
                "SLVSuperMarket",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6C63FF),
                ),
              ),

              SizedBox(height: 10),

              Text(
                isLogin ? "Welcome back 👋" : "Create your account",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),

              SizedBox(height: 40),

              // 👤 NAME (Signup only)
              if (!isLogin)
                _buildTextField(nameController, "Full Name", Icons.person),

              if (!isLogin) SizedBox(height: 15),

              // 📱 PHONE (Signup only)
              if (!isLogin)
                _buildTextField(phoneController, "Phone", Icons.phone),

              if (!isLogin) SizedBox(height: 15),

              // 📧 EMAIL
              _buildTextField(emailController, "Email", Icons.email),

              SizedBox(height: 15),

              // 🔒 PASSWORD
              _buildTextField(passwordController, "Password", Icons.lock,
                  isPassword: true),

              if (isLogin)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => openOtpLogin(fromForgotPassword: true),
                    child: Text(
                      "Forgot password? Use mobile OTP",
                      style: TextStyle(
                        color: Color(0xFF6C63FF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

              SizedBox(height: 30),

              // 🔘 BUTTON
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF6C63FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isLogin ? "Login" : "Sign Up",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),

              SizedBox(height: 20),
              SizedBox(height: 10),

// 📱 LOGIN WITH PHONE
                  Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text("OR"),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),

                  SizedBox(height: 15),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        openOtpLogin();
                      },
                      icon: Icon(Icons.phone, color: Color(0xFF6C63FF)),
                      label: Text(
                        "Login with Phone",
                        style: TextStyle(
                          color: Color(0xFF6C63FF),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Color(0xFF6C63FF)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

              // 🔄 SWITCH
              Center(
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      isLogin = !isLogin;
                    });
                  },
                  child: Text(
                    isLogin
                        ? "Don't have an account? Sign Up"
                        : "Already have an account? Login",
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
