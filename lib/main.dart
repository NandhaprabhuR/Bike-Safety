import 'package:designthinking/screens/face.dart';
import 'package:designthinking/screens/fmap.dart';
import 'package:designthinking/screens/home.dart';
import 'package:designthinking/screens/alerts.dart';
import 'package:designthinking/screens/theft.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart'; // Add Firebase Core
import 'firebase_options.dart'; // Import the generated Firebase options

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  try {
    cameras = await availableCameras();
  } catch (e) {
    print('Error initializing cameras: $e');
  }
  runApp(FaceRecognitionApp());
}

class FaceRecognitionApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BikeSafety',
      theme: ThemeData(
        primaryColor: Color(0xFFF3EFEF),
        scaffoldBackgroundColor: Color(0xFFF5F0E5),
        colorScheme: ColorScheme.dark(
          primary: Color(0xFFF5F0E5),
          secondary: Color(0xFFE5DBC8),
          tertiary: Color(0xFFD0C3A6),
          surface: Color(0xFFFFFBF3),
          background: Color(0xFFF5F0E5),
          onPrimary: Color(0xFF3E3A36),
          onSecondary: Color(0xFF3E3A36),
          onSurface: Color(0xFF3E3A36),
        ),
        textTheme: TextTheme(
          displayLarge: TextStyle(
            color: Color(0xFF3E3A36),
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
          ),
          displayMedium: TextStyle(
            color: Color(0xFF3E3A36),
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
          ),
          bodyLarge: TextStyle(
            color: Color(0xFF3E3A36),
            letterSpacing: 0.15,
          ),
          bodyMedium: TextStyle(
            color: Color(0xFF3E3A36),
            letterSpacing: 0.1,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFFD0C3A6),
            foregroundColor: Color(0xFF3E3A36),
            elevation: 0,
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            minimumSize: Size(120, 48),
            textStyle: TextStyle(
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
        cardTheme: CardTheme(
          color: Color(0xFFFFFBF3),
          elevation: 1,
          shadowColor: Colors.black.withOpacity(0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFFF5F0E5),
          foregroundColor: Color(0xFF3E3A36),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF3E3A36),
            fontSize: 20,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.15,
          ),
          iconTheme: IconThemeData(
            color: Color(0xFF3E3A36),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFFFFBF3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Color(0xFFE5DBC8), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Color(0xFFD0C3A6), width: 1.5),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          hintStyle: TextStyle(
            color: Color(0xFF3E3A36).withOpacity(0.5),
            fontSize: 14,
          ),
        ),
        iconTheme: IconThemeData(
          color: Color(0xFFD0C3A6),
          size: 24,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Color(0xFFFFFBF3),
          selectedItemColor: Color(0xFFD0C3A6),
          unselectedItemColor: Color(0xFFAEA699),
          selectedLabelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: 12,
            letterSpacing: 0.2,
          ),
          elevation: 4,
          type: BottomNavigationBarType.fixed,
        ),
        dividerColor: Color(0xFFE5DBC8),
        dialogTheme: DialogTheme(
          backgroundColor: Color(0xFFFFFBF3),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      initialRoute: '/home',
      routes: {
        '/home': (context) => const HomeScreen(
          userName: "Nandhaprabhur",
          initialWeatherData: null,
        ),
        '/face': (context) => cameras.isNotEmpty
            ? FaceRecognitionScreen()
            : const Center(child: Text('No cameras available')),
        '/map': (context) => const MapScreen(),
        '/alerts': (context) => const AlertsPage(),
        '/theft': (context) => const TheftPage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/home') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => HomeScreen(
              userName: args?['userName'] ?? "Nandhaprabhur",
              initialWeatherData: args?['initialWeatherData'],
            ),
          );
        }
        return null;
      },
    );
  }
}