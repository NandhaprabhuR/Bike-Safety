import 'package:designthinking/screens/face.dart';
import 'package:designthinking/screens/fmap.dart';
import 'package:designthinking/screens/home.dart';
import 'package:designthinking/screens/alerts.dart';
import 'package:designthinking/screens/theft.dart';
import 'package:designthinking/screens/profile.dart';
import 'package:designthinking/screens/users.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:permission_handler/permission_handler.dart';
import 'firebase_options.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await _requestPermissions();

  try {
    cameras = await availableCameras();
  } catch (e) {
    print('Error initializing cameras: $e');
  }

  runApp(FaceRecognitionApp());
}

Future<void> _requestPermissions() async {
  final locationStatus = await Permission.location.request();
  final cameraStatus = await Permission.camera.request();

  if (locationStatus.isDenied || cameraStatus.isDenied) {
    await openAppSettings();
  }
}

class FaceRecognitionApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BikeSafety',
      theme: ThemeData(
        primaryColor: Color(0xFFFFFFFF), // White background
        scaffoldBackgroundColor: Color(0xFFFFFFFF), // Matching scaffold background
        colorScheme: ColorScheme.light(
          primary: Color(0xFFFFFFFF), // White for primary elements
          secondary: Color(0xFF42A5F5), // Soft blue for accents
          tertiary: Color(0xFF616161), // Dark gray for text/icons
          surface: Color(0xFFE0E0E0), // Light gray for cards/surfaces
          background: Color(0xFFFFFFFF),
          onPrimary: Color(0xFF616161), // Dark gray text on primary color
          onSecondary: Color(0xFFFFFFFF), // White text on secondary color
          onSurface: Color(0xFF616161), // Dark gray text on surfaces
        ),
        textTheme: TextTheme(
          displayLarge: TextStyle(
            color: Color(0xFF616161),
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
          ),
          displayMedium: TextStyle(
            color: Color(0xFF616161),
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
          ),
          bodyLarge: TextStyle(
            color: Color(0xFF616161),
            letterSpacing: 0.15,
          ),
          bodyMedium: TextStyle(
            color: Color(0xFF616161),
            letterSpacing: 0.1,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF42A5F5), // Soft blue for buttons
            foregroundColor: Color(0xFFFFFFFF), // White text/icon on buttons
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
          color: Color(0xFFE0E0E0), // Light gray for cards
          elevation: 1,
          shadowColor: Colors.black.withOpacity(0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFFFFFFFF),
          foregroundColor: Color(0xFF616161),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF616161),
            fontSize: 20,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.15,
          ),
          iconTheme: IconThemeData(
            color: Color(0xFF616161),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFE0E0E0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Color(0xFFE0E0E0), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Color(0xFF42A5F5), width: 1.5),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          hintStyle: TextStyle(
            color: Color(0xFF616161).withOpacity(0.5),
            fontSize: 14,
          ),
        ),
        iconTheme: IconThemeData(
          color: Color(0xFF42A5F5),
          size: 24,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.transparent,
          selectedItemColor: Color(0xFF42A5F5),
          unselectedItemColor: Color(0xFF616161).withOpacity(0.5),
          selectedLabelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: 12,
            letterSpacing: 0.2,
          ),
          elevation: 0,
          type: BottomNavigationBarType.fixed,
        ),
        dividerColor: Color(0xFFE0E0E0),
        dialogTheme: DialogTheme(
          backgroundColor: Color(0xFFE0E0E0),
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
        '/profile': (context) => const ProfileScreen(),
        '/users': (context) => const UsersScreen(),
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