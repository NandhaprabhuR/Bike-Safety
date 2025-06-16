import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:designthinking/screens/home.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    try {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
      print('User signed out at ${DateTime.now()}');
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      print('Error signing out: $e at ${DateTime.now()}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to sign out: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          // User is signed in, redirect to HomeScreen
          final user = snapshot.data!;
          print('User signed in: ${user.email} at ${DateTime.now()}');
          return HomeScreen(
            userName: user.displayName ?? "Nandhaprabhur",
            initialWeatherData: null,
          );
        }

        // User is not signed in, show sign-in option
        return Scaffold(
          backgroundColor: const Color(0xFFF5F0E5),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'You are not signed in',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF3E3A36),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                    icon: const Icon(Icons.login, size: 20),
                    label: const Text('Go to Login'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD0C3A6),
                      foregroundColor: const Color(0xFF3E3A36),
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}// TODO Implement this library.