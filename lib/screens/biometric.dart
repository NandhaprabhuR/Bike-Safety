import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();
  static const MethodChannel _channel = MethodChannel('com.example.designthinking/biometric');

  /// Check if biometric authentication is available
  Future<bool> canCheckBiometrics() async {
    try {
      final bool canAuthenticate = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      debugPrint('Biometric available: $canAuthenticate');
      return canAuthenticate;
    } on PlatformException catch (e) {
      debugPrint('Error checking biometrics: $e');
      return false;
    }
  }

  /// Check if any biometric (e.g., fingerprint or Face ID) is enrolled
  Future<bool> hasBiometricsEnrolled() async {
    try {
      final List<BiometricType> availableBiometrics = await _auth.getAvailableBiometrics();
      final bool hasBiometric = availableBiometrics.contains(BiometricType.fingerprint) ||
          availableBiometrics.contains(BiometricType.strong) ||
          availableBiometrics.contains(BiometricType.face);
      debugPrint('Biometric enrolled: $hasBiometric');
      return hasBiometric;
    } on PlatformException catch (e) {
      debugPrint('Error checking enrolled biometrics: $e');
      return false;
    }
  }

  /// Open device security settings using MethodChannel
  Future<bool> openSecuritySettings() async {
    try {
      final bool success = await _channel.invokeMethod('openSecuritySettings');
      debugPrint('Opened security settings successfully: $success');
      return success;
    } catch (e) {
      debugPrint('Error opening security settings: $e');
      return false;
    }
  }

  /// Authenticate user with fingerprint
  Future<bool> verifyFingerprint() async {
    try {
      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'Please authenticate with your fingerprint to start the vehicle',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true, // Let platform handle error dialogs
          sensitiveTransaction: true,
        ),
      );
      debugPrint('Fingerprint authentication result: $didAuthenticate');
      return didAuthenticate;
    } on PlatformException catch (e) {
      debugPrint('Authentication error: $e');
      String errorMessage;
      switch (e.code) {
        case auth_error.notAvailable:
          errorMessage = 'Biometric authentication is not available on this device.';
          break;
        case auth_error.notEnrolled:
          errorMessage = 'No biometrics enrolled. Please enroll a fingerprint or Face ID in device settings.';
          break;
        case auth_error.lockedOut:
          errorMessage = 'Biometric authentication is locked out. Please try again later or use device PIN.';
          break;
        case auth_error.passcodeNotSet:
          errorMessage = 'No device passcode set. Please set a passcode in device settings.';
          break;
        default:
          errorMessage = 'Authentication error: ${e.message}';
      }
      throw Exception(errorMessage);
    }
  }
}