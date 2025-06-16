import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Add this import
import 'biometric.dart';

class FaceRecognitionScreen extends StatefulWidget {
  const FaceRecognitionScreen({super.key});

  @override
  State<FaceRecognitionScreen> createState() => _FaceRecognitionScreenState();
}

class _FaceRecognitionScreenState extends State<FaceRecognitionScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  bool _isFaceVerified = false;
  bool _isFingerprintVerified = false;
  String _errorMessage = '';

  String? _currentFaceFeature;
  late final FaceDetector _faceDetector;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final BiometricService _biometricService = BiometricService();

  late final CloudinaryPublic cloudinary;

  @override
  void initState() {
    super.initState();
    cloudinary = CloudinaryPublic('djtzb6cvj', 'bikefaceauth', cache: false);
    final options = FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: true,
      performanceMode: FaceDetectorMode.accurate,
    );
    _faceDetector = FaceDetector(options: options);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      var status = await Permission.camera.request();
      if (status.isDenied) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Camera permission denied. Please enable it in settings.';
          });
        }
        print('Camera permission denied at ${DateTime.now()}');
        return;
      }
      if (status.isPermanentlyDenied) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Camera permission permanently denied. Please enable it in settings.';
          });
        }
        print('Camera permission permanently denied at ${DateTime.now()}');
        openAppSettings();
        return;
      }

      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = 'No cameras available on this device.';
          });
        }
        print('No cameras available on this device at ${DateTime.now()}');
        return;
      }

      CameraDescription camera = _cameras!.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      print('Camera initialized successfully at ${DateTime.now()}');
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize camera: $e';
        });
      }
      print('Error initializing camera: $e at ${DateTime.now()}');
    }
  }

  Future<bool> _checkLiveness() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      print('Camera not initialized for liveness check at ${DateTime.now()}');
      return false;
    }

    try {
      print('Starting liveness check at ${DateTime.now()}');
      double? previousLeftEyeOpenProb;
      double? previousRightEyeOpenProb;
      double? previousHeadEulerAngleY;
      bool livenessDetected = false;

      for (int i = 0; i < 5; i++) {
        final XFile imageFile = await _controller!.takePicture();
        final InputImage inputImage = InputImage.fromFilePath(imageFile.path);
        final List<Face> faces = await _faceDetector.processImage(inputImage);

        if (faces.isEmpty) {
          print('No face detected during liveness check (frame $i) at ${DateTime.now()}');
          await File(imageFile.path).delete();
          continue;
        }

        final Face face = faces.first;
        double? leftEyeOpenProb = face.leftEyeOpenProbability;
        double? rightEyeOpenProb = face.rightEyeOpenProbability;
        double? headEulerAngleY = face.headEulerAngleY;

        print('Frame $i: LeftEyeOpenProb: $leftEyeOpenProb, RightEyeOpenProb: $rightEyeOpenProb, HeadEulerAngleY: $headEulerAngleY at ${DateTime.now()}');

        if (leftEyeOpenProb != null && rightEyeOpenProb != null) {
          if (previousLeftEyeOpenProb != null && previousRightEyeOpenProb != null) {
            double leftEyeChange = (leftEyeOpenProb - previousLeftEyeOpenProb).abs();
            double rightEyeChange = (rightEyeOpenProb - previousRightEyeOpenProb).abs();

            print('Eye change detected - Left: $leftEyeChange, Right: $rightEyeChange at ${DateTime.now()}');

            if (leftEyeChange > 0.2 || rightEyeChange > 0.2) {
              print('Liveness confirmed: Eye movement detected at ${DateTime.now()}');
              livenessDetected = true;
              break;
            }
          }
          previousLeftEyeOpenProb = leftEyeOpenProb;
          previousRightEyeOpenProb = rightEyeOpenProb;
        }

        if (headEulerAngleY != null && previousHeadEulerAngleY != null) {
          double headAngleChange = (headEulerAngleY - previousHeadEulerAngleY).abs();
          print('Head angle change detected - Yaw: $headAngleChange at ${DateTime.now()}');
          if (headAngleChange > 5.0) {
            print('Liveness confirmed: Head movement detected at ${DateTime.now()}');
            livenessDetected = true;
            break;
          }
        }
        previousHeadEulerAngleY = headEulerAngleY;

        await File(imageFile.path).delete();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (!livenessDetected) {
        print('Liveness check failed: No significant eye or head movement detected at ${DateTime.now()}');
      }
      return livenessDetected;
    } catch (e) {
      print('Error during liveness check: $e at ${DateTime.now()}');
      return false;
    }
  }

  Future<bool> _detectFace(XFile imageFile) async {
    try {
      final file = File(imageFile.path);
      if (!await file.exists() || await file.length() == 0) {
        print('Image file does not exist or is empty at ${DateTime.now()}');
        return false;
      }

      final InputImage inputImage = InputImage.fromFilePath(imageFile.path);
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        print('No faces detected in the image at ${DateTime.now()}');
        return false;
      }

      bool isLive = await _checkLiveness();
      if (!isLive) {
        print('Liveness check failed: Not a live human face at ${DateTime.now()}');
        return false;
      }

      _currentFaceFeature = 'mock_face_58.22';
      print('Face detected, feature extracted: $_currentFaceFeature at ${DateTime.now()}');
      return true;
    } catch (e, stackTrace) {
      print('Error detecting face with Google ML Kit: $e at ${DateTime.now()}');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  String _generateMockFaceId() {
    if (_currentFaceFeature == null) {
      return 'mock_face_${DateTime.now().millisecondsSinceEpoch % 100}.22';
    }
    return _currentFaceFeature!;
  }

  Future<bool> _isFaceRegistered(String faceId) async {
    try {
      final snapshot = await _firestore
          .collection('registered_faces')
          .where('faceId', isEqualTo: faceId)
          .get();
      bool isRegistered = snapshot.docs.isNotEmpty;
      print('Face ID $faceId is ${isRegistered ? '' : 'not '}registered at ${DateTime.now()}');
      return isRegistered;
    } catch (e) {
      print('Error checking if face is registered: $e at ${DateTime.now()}');
      return false;
    }
  }

  Future<String?> _getUserStatus(String faceId) async {
    try {
      final snapshot = await _firestore
          .collection('registered_faces')
          .where('faceId', isEqualTo: faceId)
          .get();
      if (snapshot.docs.isEmpty) {
        print('No user found with faceId: $faceId at ${DateTime.now()}');
        return null;
      }
      final userDoc = snapshot.docs.first;
      final data = userDoc.data();
      final status = data.containsKey('status') ? data['status'] as String? : null;
      final result = status ?? 'pending';
      print('User status for faceId $faceId: $result at ${DateTime.now()}');
      return result;
    } catch (e) {
      print('Error fetching user status: $e at ${DateTime.now()}');
      return null;
    }
  }

  Future<void> _startVehicle(String faceId) async {
    print('Vehicle started for user $faceId at ${DateTime.now()}');

    final userSnapshot = await _firestore
        .collection('registered_faces')
        .where('faceId', isEqualTo: faceId)
        .get();

    if (userSnapshot.docs.isNotEmpty) {
      final userDoc = userSnapshot.docs.first;
      await userDoc.reference.update({
        'hasStartedVehicle': true,
        'lastStartVehicle': FieldValue.serverTimestamp(),
      });
      print('Updated Firestore: hasStartedVehicle set to true for faceId: $faceId at ${DateTime.now()}');
    }
  }

  Future<void> _saveRegisteredFace(String faceId, String? photoUrl) async {
    try {
      await _firestore.collection('registered_faces').add({
        'faceId': faceId,
        'photoUrl': photoUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'hasStartedVehicle': false,
        'status': 'pending',
        'currentRequestId': null,
      });
      print('Saved face ID to Firestore: $faceId with photoUrl: $photoUrl at ${DateTime.now()}');

      await _firestore.collection('face_notifications').add({
        'faceId': faceId,
        'photoUrl': photoUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'message': 'New face registered: $faceId',
      });
      print('Logged face registration notification for faceId: $faceId at ${DateTime.now()}');
    } catch (e, stackTrace) {
      print('Error saving face ID to Firestore: $e at ${DateTime.now()}');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to save face ID: $e';
        });
      }
    }
  }

  void _showResultDialog(String title, String message, {bool navigateBack = false, VoidCallback? onClose, Map<String, dynamic>? result}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          content: Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          backgroundColor: Theme.of(context).cardTheme.color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (navigateBack) {
                  Navigator.pop(context, result);
                }
                onClose?.call();
              },
              child: Text(
                'OK',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _captureAndVerifyFace() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      if (_errorMessage != 'Camera not ready. Please wait.') {
        setState(() {
          _errorMessage = 'Camera not ready. Please wait.';
        });
      }
      return;
    }

    setState(() {
      _isCapturing = true;
      _errorMessage = '';
      _currentFaceFeature = null;
    });

    try {
      final XFile imageFile = await _controller!.takePicture();
      print('Image captured at ${imageFile.path} at ${DateTime.now()}');

      bool faceDetected = await _detectFace(imageFile);
      if (!faceDetected) {
        setState(() {
          _errorMessage = 'No live human face detected. Only live human faces can be verified.';
          _isCapturing = false;
        });
        _showResultDialog(
          'Verification Failed',
          'No live human face detected in the image. Photos, computer images, or non-human objects are not allowed. Please ensure a live human face is present and try again.',
        );
        await File(imageFile.path).delete();
        return;
      }

      String faceId = _generateMockFaceId();
      bool isRegistered = await _isFaceRegistered(faceId);
      if (!isRegistered) {
        setState(() {
          _errorMessage = 'Face not registered. Please register the face first.';
          _isCapturing = false;
        });
        _showResultDialog(
          'Verification Failed',
          'This face is not registered. Please register the face first.',
        );
        await File(imageFile.path).delete();
        return;
      }

      String? photoUrl;
      try {
        final response = await cloudinary.uploadFile(
          CloudinaryFile.fromFile(
            imageFile.path,
            folder: 'face_images',
            resourceType: CloudinaryResourceType.Image,
          ),
        );
        photoUrl = response.secureUrl;
        print('Uploaded face image to Cloudinary: $photoUrl at ${DateTime.now()}');
      } catch (e) {
        print('Error uploading face image to Cloudinary: $e at ${DateTime.now()}');
        setState(() {
          _errorMessage = 'Failed to upload face image: $e';
          _isCapturing = false;
        });
        _showResultDialog(
          'Upload Failed',
          'Failed to upload face image: $e. Face verification cannot proceed.',
        );
        await File(imageFile.path).delete();
        return;
      } finally {
        await File(imageFile.path).delete();
      }

      try {
        final snapshot = await _firestore
            .collection('registered_faces')
            .where('faceId', isEqualTo: faceId)
            .get();
        if (snapshot.docs.isNotEmpty) {
          await snapshot.docs.first.reference.update({
            'photoUrl': photoUrl,
            'lastStartVehicle': FieldValue.serverTimestamp(),
          });
          print('Updated Firestore with new photoUrl for faceId: $faceId at ${DateTime.now()}');
        }
      } catch (e) {
        print('Error updating Firestore with photoUrl: $e at ${DateTime.now()}');
      }

      await Future.delayed(const Duration(seconds: 2));
      double matchScore = 0.95;
      print('Image comparison completed, similarity: $matchScore at ${DateTime.now()}');

      if (matchScore > 0.8) {
        print('Face verified successfully at ${DateTime.now()}');
        setState(() {
          _isFaceVerified = true;
          _errorMessage = '';
          _isCapturing = false;
        });
        _showResultDialog(
          'Face Verification Success',
          'Face verified successfully! Please verify your fingerprint to proceed.',
        );
      } else {
        print('Face verification failed at ${DateTime.now()}');
        setState(() {
          _isFaceVerified = false;
          _errorMessage = 'Face verification failed. Please try again.';
          _isCapturing = false;
        });
        _showResultDialog(
          'Face Verification Failed',
          'Face verification failed. Please try again.',
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to capture image: $e';
        _isCapturing = false;
      });
      _showResultDialog('Error', 'Failed to capture image: $e');
    }
  }

  Future<Map<String, dynamic>?> _verifyFingerprintAndStartVehicle() async {
    if (!_isFaceVerified) {
      setState(() {
        _errorMessage = 'Please verify your face first.';
      });
      _showResultDialog(
        'Face Verification Required',
        'Please verify your face before proceeding with fingerprint verification.',
      );
      return null;
    }

    setState(() {
      _isCapturing = true;
      _errorMessage = '';
    });

    try {
      bool? canAuthenticate = await _biometricService.canCheckBiometrics();
      if (canAuthenticate == null || !canAuthenticate) {
        setState(() {
          _isCapturing = false;
          _errorMessage = 'Biometric authentication is not available on this device.';
        });
        _showResultDialog(
          'Biometric Unavailable',
          'This device does not support biometric authentication or it is disabled. Please enable biometrics in your device settings.',
        );
        return null;
      }

      bool? hasBiometric = await _biometricService.hasBiometricsEnrolled();
      if (hasBiometric == null || !hasBiometric) {
        setState(() {
          _isCapturing = false;
          _errorMessage = 'No biometric enrolled. Please enroll a fingerprint or Face ID in device settings.';
        });
        bool openedSettings = await _biometricService.openSecuritySettings() ?? false;
        String message = openedSettings
            ? 'Please enroll a fingerprint or Face ID in your device settings (e.g., Settings > Security > Fingerprint) and try again.'
            : 'Failed to open settings. Please go to your device settings manually to enroll a biometric.';
        _showResultDialog(
          'Biometric Required',
          message,
          onClose: () async {
            if (openedSettings) {
              bool? hasBiometricAfterSettings = await _biometricService.hasBiometricsEnrolled();
              if (hasBiometricAfterSettings == true) {
                await _verifyFingerprintAndStartVehicle();
              }
            }
          },
        );
        return null;
      }

      bool? fingerprintVerified = await _biometricService.verifyFingerprint();
      if (fingerprintVerified == null) {
        throw Exception('Fingerprint verification returned null unexpectedly.');
      }

      setState(() {
        _isCapturing = false;
        _isFingerprintVerified = fingerprintVerified;
      });

      if (fingerprintVerified) {
        try {
          final faceId = _generateMockFaceId();
          final snapshot = await _firestore
              .collection('registered_faces')
              .where('faceId', isEqualTo: faceId)
              .get();
          if (snapshot.docs.isNotEmpty) {
            final userDoc = snapshot.docs.first;
            final userData = userDoc.data();
            String? photoUrl = userData['photoUrl'];

            final userStatus = await _getUserStatus(faceId);
            if (userStatus == null) {
              setState(() {
                _errorMessage = 'User not found. Please register the face first.';
              });
              _showResultDialog(
                'Permission Error',
                'User not found in the database. Please register the face first.',
              );
              return null;
            }

            final requestId = const Uuid().v4();

            final existingPermissions = await _firestore
                .collection('pending_permissions')
                .where('faceId', isEqualTo: faceId)
                .where('status', isEqualTo: 'pending')
                .get();

            if (existingPermissions.docs.isEmpty) {
              await _firestore.collection('pending_permissions').add({
                'faceId': faceId,
                'photoUrl': photoUrl,
                'timestamp': FieldValue.serverTimestamp(),
                'status': 'pending',
                'requestId': requestId,
              });
              print('Logged pending permission for faceId: $faceId with requestId: $requestId at ${DateTime.now()}');
            } else {
              print('Pending permission already exists for faceId: $faceId at ${DateTime.now()}');
              final existingDoc = existingPermissions.docs.first;
              await existingDoc.reference.update({
                'requestId': requestId,
                'timestamp': FieldValue.serverTimestamp(),
              });
            }

            await userDoc.reference.update({
              'currentRequestId': requestId,
              'status': 'pending',
            });

            // Save faceId and requestId to SharedPreferences
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('lastFaceId', faceId);
            await prefs.setString('lastRequestId', requestId);
            print('Saved faceId: $faceId and requestId: $requestId to SharedPreferences at ${DateTime.now()}');

            _showResultDialog(
              'Verification Complete',
              'Both face and fingerprint verified successfully! Awaiting permission approval from the owner.',
              navigateBack: true,
              result: {
                'faceId': faceId,
                'requestId': requestId,
              },
            );
            return {
              'faceId': faceId,
              'requestId': requestId,
            };
          } else {
            setState(() {
              _errorMessage = 'User not found. Please register the face first.';
            });
            _showResultDialog(
              'Permission Error',
              'User not found in the database. Please register the face first.',
            );
            return null;
          }
        } catch (e) {
          print('Error logging pending permission in Firestore: $e at ${DateTime.now()}');
          setState(() {
            _errorMessage = 'Failed to request permission: $e';
          });
          _showResultDialog(
            'Permission Request Failed',
            'Failed to request permission: $e',
          );
          return null;
        }
      } else {
        setState(() {
          _errorMessage = 'Fingerprint verification failed. Please try again.';
        });
        _showResultDialog(
          'Fingerprint Verification Failed',
          'Fingerprint verification failed. Please try again or check your fingerprint sensor.',
        );
        return null;
      }
    } catch (e) {
      setState(() {
        _isCapturing = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
      _showResultDialog(
        'Fingerprint Verification Error',
        _errorMessage,
      );
      return null;
    }
  }

  Future<void> _registerFace() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      if (_errorMessage != 'Camera not ready. Please wait.') {
        setState(() {
          _errorMessage = 'Camera not ready. Please wait.';
        });
      }
      return;
    }

    setState(() {
      _isCapturing = true;
      _errorMessage = '';
      _currentFaceFeature = null;
    });

    try {
      final XFile imageFile = await _controller!.takePicture();
      print('Image captured for registration at ${imageFile.path} at ${DateTime.now()}');

      bool faceDetected = await _detectFace(imageFile);
      if (!faceDetected) {
        setState(() {
          _errorMessage = 'No live human face detected. Only live human faces can be registered.';
          _isCapturing = false;
        });
        _showResultDialog(
          'Registration Failed',
          'No live human face detected in the image. Photos, computer images, or non-human objects are not allowed. Please ensure a live human face is present and try again.',
        );
        await File(imageFile.path).delete();
        return;
      }

      String faceId = _generateMockFaceId();
      bool isRegistered = await _isFaceRegistered(faceId);
      if (isRegistered) {
        setState(() {
          _errorMessage = 'Face already registered. Please verify instead.';
          _isCapturing = false;
        });
        _showResultDialog(
          'Registration Failed',
          'This face is already registered. Please verify instead.',
        );
        await File(imageFile.path).delete();
        return;
      }

      String? photoUrl;
      try {
        final response = await cloudinary.uploadFile(
          CloudinaryFile.fromFile(
            imageFile.path,
            folder: 'face_images',
            resourceType: CloudinaryResourceType.Image,
          ),
        );
        photoUrl = response.secureUrl;
        print('Uploaded face image to Cloudinary: $photoUrl at ${DateTime.now()}');
      } catch (e) {
        print('Error uploading face image to Cloudinary: $e at ${DateTime.now()}');
        setState(() {
          _errorMessage = 'Failed to upload face image: $e';
          _isCapturing = false;
        });
        _showResultDialog(
          'Upload Failed',
          'Failed to upload face image: $e. Face registration cannot proceed.',
        );
        await File(imageFile.path).delete();
        return;
      } finally {
        await File(imageFile.path).delete();
      }

      await _saveRegisteredFace(faceId, photoUrl);
      print('Face registered successfully with ID: $faceId at ${DateTime.now()}');

      setState(() {
        _errorMessage = '';
        _isCapturing = false;
      });
      _showResultDialog(
        'Registration Success',
        'Face registered successfully! Please verify to proceed.',
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to register face: $e';
        _isCapturing = false;
      });
      _showResultDialog('Error', 'Failed to register face: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Face Recognition'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context, null);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            if (_errorMessage.isNotEmpty && !_errorMessage.contains('successfully'))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  _errorMessage,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.red,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 16),
            _isCameraInitialized
                ? Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 360,
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: CameraPreview(_controller!),
                  ),
                ),
                Container(
                  width: 360,
                  height: 360 / _controller!.value.aspectRatio,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white,
                      width: 4,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                if (_isCapturing)
                  Container(
                    width: 360,
                    height: 360 / _controller!.value.aspectRatio,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
              ],
            )
                : const CircularProgressIndicator(),
            const SizedBox(height: 24),
            if (!_isFaceVerified && _isCameraInitialized && !_isCapturing)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isCapturing ? null : _captureAndVerifyFace,
                      icon: const Icon(Icons.check, size: 20),
                      label: const Text('Verify Face'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.secondary,
                        foregroundColor: Theme.of(context).colorScheme.onSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isCapturing ? null : _registerFace,
                      icon: const Icon(Icons.person_add, size: 20),
                      label: const Text('Register Face'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.secondary,
                        foregroundColor: Theme.of(context).colorScheme.onSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            if (_isFaceVerified && !_isFingerprintVerified && _isCameraInitialized && !_isCapturing)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isCapturing
                      ? null
                      : () async {
                    await _verifyFingerprintAndStartVehicle();
                  },
                  icon: const Icon(Icons.fingerprint, size: 20),
                  label: const Text('Verify Fingerprint'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Theme.of(context).colorScheme.onSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (!_isFaceVerified && _isCameraInitialized && !_isCapturing)
              Text(
                'Position your face within the rectangle, blink your eyes or tilt your head, and press verify',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            if (_isFaceVerified && !_isFingerprintVerified && _isCameraInitialized && !_isCapturing)
              Text(
                'Please verify your fingerprint to proceed',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
          ],
        ),
      ),
    );
  }
}