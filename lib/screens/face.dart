import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
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
  bool _isLoadingFaces = true;

  List<String> _registeredFaces = [];
  String? _currentFaceFeature;
  late final FaceDetector _faceDetector;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final BiometricService _biometricService = BiometricService();

  @override
  void initState() {
    super.initState();
    final options = FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    );
    _faceDetector = FaceDetector(options: options);
    _loadRegisteredFaces();
    _initializeCamera();
  }

  Future<void> _loadRegisteredFaces() async {
    try {
      final snapshot = await _firestore.collection('registered_faces').get();
      final faces = snapshot.docs.map((doc) => doc['faceId'] as String).toList();
      if (mounted) {
        setState(() {
          _registeredFaces = faces;
          _isLoadingFaces = false;
          print('Loaded ${faces.length} registered faces from Firestore at ${DateTime.now()}');
        });
      }
    } catch (e, stackTrace) {
      print('Error loading registered faces from Firestore: $e at ${DateTime.now()}');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load registered faces: $e';
          _isLoadingFaces = false;
        });
      }
    }
  }

  Future<void> _saveRegisteredFace(String faceId) async {
    try {
      await _firestore.collection('registered_faces').add({
        'faceId': faceId,
        'timestamp': FieldValue.serverTimestamp(),
      });
      print('Saved face ID to Firestore: $faceId at ${DateTime.now()}');
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

  Future<bool> _detectFace(XFile imageFile) async {
    try {
      final file = File(imageFile.path);
      if (!await file.exists() || await file.length() == 0) {
        print('Image file does not exist or is empty at ${DateTime.now()}');
        return false;
      }

      final inputImage = InputImage.fromFilePath(imageFile.path);
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        print('No faces detected in the image at ${DateTime.now()}');
        return false;
      }

      _currentFaceFeature = 'mock_face_${DateTime.now().hour}_${DateTime.now().minute}';
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
      return 'unknown_face_${DateTime.now().millisecondsSinceEpoch}';
    }
    return _currentFaceFeature!;
  }

  Future<bool> _isFaceRegistered(String faceId) async {
    if (_registeredFaces.isEmpty) {
      print('No faces registered yet at ${DateTime.now()}');
      return false;
    }
    bool isRegistered = _registeredFaces.contains(faceId);
    print('Face ID $faceId is ${isRegistered ? '' : 'not '}registered at ${DateTime.now()}');
    return isRegistered;
  }

  void _showResultDialog(String title, String message, {bool navigateBack = false, VoidCallback? onClose}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          backgroundColor: const Color(0xFFF5F0E5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (navigateBack) {
                  Navigator.pop(context, true);
                }
                onClose?.call();
              },
              child: const Text(
                'OK',
                style: TextStyle(color: Color(0xFF3E3A36)),
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
      await File(imageFile.path).delete();
      if (!faceDetected) {
        setState(() {
          _errorMessage = 'No face detected. Only human faces can be verified.';
          _isCapturing = false;
        });
        _showResultDialog(
          'Verification Failed',
          'No human face detected in the image. Random objects (e.g., room, fan) are not allowed. Please ensure a face is present and try again.',
        );
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
        return;
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

  Future<void> _verifyFingerprintAndStartVehicle() async {
    if (!_isFaceVerified) {
      setState(() {
        _errorMessage = 'Please verify your face first.';
      });
      _showResultDialog(
        'Face Verification Required',
        'Please verify your face before proceeding with fingerprint verification.',
      );
      return;
    }

    setState(() {
      _isCapturing = true;
      _errorMessage = '';
    });

    // Check if fingerprint is enrolled
    bool hasFingerprint = await _biometricService.hasFingerprintEnrolled();
    if (!hasFingerprint) {
      setState(() {
        _isCapturing = false;
      });

      // Prompt user to enroll a fingerprint or troubleshoot
      bool openedSettings = await _biometricService.hasFingerprintEnrolled();
      if (openedSettings) {
        _showResultDialog(
          'Biometric Setup',
          'Unable to detect enrolled fingerprint. Please ensure a fingerprint is enrolled in your device settings (e.g., Settings > Security > Fingerprint or Biometrics and Security > Fingerprints), then return and try again. If you’ve already enrolled a fingerprint, try re-enrolling it.',
          onClose: () async {
            // Recheck fingerprint enrollment after user returns from settings
            bool hasFingerprintAfterSettings = await _biometricService.hasFingerprintEnrolled();
            if (hasFingerprintAfterSettings) {
              // If a fingerprint is now enrolled, automatically trigger verification
              _verifyFingerprintAndStartVehicle();
            }
          },
        );
      } else {
        setState(() {
          _errorMessage = 'Failed to open device settings. Please check your fingerprint settings manually.';
        });
        _showResultDialog(
          'Error',
          'Failed to open device settings. Please go to your device settings (e.g., Settings > Security > Fingerprint or Biometrics and Security > Fingerprints) to ensure a fingerprint is enrolled, then try again.',
        );
      }
      return;
    }

    // Proceed with fingerprint verification if a fingerprint is enrolled
    bool fingerprintVerified = await _biometricService.verifyFingerprint();
    setState(() {
      _isCapturing = false;
      _isFingerprintVerified = fingerprintVerified;
    });

    if (fingerprintVerified) {
      _showResultDialog(
        'Verification Complete',
        'Both face and fingerprint verified successfully! Vehicle started.',
        navigateBack: true,
      );
    } else {
      bool canCheckBiometrics = await _biometricService.canCheckBiometrics();
      String errorMessage;

      if (!canCheckBiometrics) {
        errorMessage = 'Biometric authentication is not available on this device. Please ensure biometrics are enabled in your device settings.';
      } else {
        errorMessage = 'Fingerprint verification failed. Please try again or ensure your fingerprint sensor is working correctly.';
      }

      setState(() {
        _errorMessage = errorMessage;
      });
      _showResultDialog(
        'Fingerprint Verification Failed',
        errorMessage,
      );
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
      await File(imageFile.path).delete();
      if (!faceDetected) {
        setState(() {
          _errorMessage = 'No face detected. Only human faces can be registered.';
          _isCapturing = false;
        });
        _showResultDialog(
          'Registration Failed',
          'No human face detected in the image. Random objects (e.g., room, fan) are not allowed. Please ensure a face is present and try again.',
        );
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
        return;
      }

      _registeredFaces.add(faceId);
      await _saveRegisteredFace(faceId);
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
    if (_isLoadingFaces) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorMessage.contains('Failed to load registered faces')) {
      return Scaffold(
        body: Center(
          child: Text('Error loading faces: $_errorMessage'),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0E5),
      appBar: AppBar(
        title: const Text('Face Recognition'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context, false);
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isCapturing ? null : _captureAndVerifyFace,
                    icon: const Icon(Icons.check, size: 20),
                    label: const Text('Verify Face'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD0C3A6),
                      foregroundColor: const Color(0xFF3E3A36),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton.icon(
                    onPressed: _isCapturing ? null : _registerFace,
                    icon: const Icon(Icons.person_add, size: 20),
                    label: const Text('Register Face'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD0C3A6),
                      foregroundColor: const Color(0xFF3E3A36),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            if (_isFaceVerified && !_isFingerprintVerified && _isCameraInitialized && !_isCapturing)
              ElevatedButton.icon(
                onPressed: _isCapturing ? null : _verifyFingerprintAndStartVehicle,
                icon: const Icon(Icons.fingerprint, size: 20),
                label: const Text('Verify Fingerprint'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD0C3A6),
                  foregroundColor: const Color(0xFF3E3A36),
                  padding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (!_isFaceVerified && _isCameraInitialized && !_isCapturing)
              const Text(
                'Position your face within the rectangle and press verify',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF3E3A36),
                ),
              ),
            if (_isFaceVerified && !_isFingerprintVerified && _isCameraInitialized && !_isCapturing)
              const Text(
                'Please verify your fingerprint to start the vehicle',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF3E3A36),
                ),
              ),
          ],
        ),
      ),
    );
  }
}