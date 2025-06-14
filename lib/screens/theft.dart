import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:location/location.dart' as location_pkg;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sensors_plus/sensors_plus.dart';
import 'alertS.dart';

class TheftPage extends StatefulWidget {
  const TheftPage({super.key});

  @override
  State<TheftPage> createState() => _TheftPageState();
}

class _TheftPageState extends State<TheftPage> {
  bool _isAlertTriggered = false;
  bool _isLiftDetectionActive = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isDetecting = false;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,
      enableClassification: false,
      enableTracking: false,
    ),
  );
  final location_pkg.Location _location = location_pkg.Location();

  // Variables for lift and shake detection
  double _averageZAcceleration = 0.0;
  int _zSampleCount = 0;
  static const double liftAccelerationThreshold = 2.0; // m/s² above gravity for lift detection
  static const int liftSampleThreshold = 10; // Number of samples to confirm lift
  static const double shakeThreshold = 10.0; // Lowered for testing (m/s²)
  static const int shakeCountThreshold = 2; // Lowered for testing
  int _shakeCount = 0;
  DateTime? _lastShakeTime;
  bool _hasTriggered = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _setupLiftAndShakeDetection();
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      _cameraController = CameraController(
        _cameras![0],
        ResolutionPreset.medium,
      );
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } else {
      _showError('No camera available');
    }
  }

  void _setupLiftAndShakeDetection() {
    accelerometerEventStream().listen((AccelerometerEvent event) {
      if (!_isLiftDetectionActive || _hasTriggered) return;

      // Log raw accelerometer data to confirm events are firing
      print('Accelerometer Event - X: ${event.x}, Y: ${event.y}, Z: ${event.z}');

      // Lift Detection: Check for sustained upward acceleration
      double accelerationZ = event.z; // z-axis acceleration (gravity is ~9.8 m/s²)
      double netAcceleration = accelerationZ - 9.8; // Adjust for gravity

      // Use a moving average to smooth out noise
      _zSampleCount++;
      _averageZAcceleration = (_averageZAcceleration * (_zSampleCount - 1) + netAcceleration) / _zSampleCount;

      print('Lift Detection - Net Z Acceleration: $netAcceleration, Average: $_averageZAcceleration, Samples: $_zSampleCount');

      if (_averageZAcceleration > liftAccelerationThreshold && _zSampleCount >= liftSampleThreshold) {
        print('Lift detected: Average Z Acceleration $_averageZAcceleration m/s² over $_zSampleCount samples');
        _hasTriggered = true;
        _triggerLiftAlert();
      }

      // Shake Detection: Detect rapid changes in acceleration across all axes
      double totalAcceleration = (event.x.abs() + event.y.abs() + event.z.abs());
      if (totalAcceleration > shakeThreshold) {
        DateTime now = DateTime.now();
        if (_lastShakeTime == null || now.difference(_lastShakeTime!).inMilliseconds > 500) {
          _shakeCount++;
          _lastShakeTime = now;
          print('Shake detected: Total Acceleration $totalAcceleration, Shake count: $_shakeCount');

          if (_shakeCount >= shakeCountThreshold) {
            print('Shake threshold reached: $_shakeCount shakes');
            _hasTriggered = true;
            _triggerLiftAlert();
          }
        }
      }
    }, onError: (error) {
      print('Accelerometer stream error: $error');
      _showError('Failed to access accelerometer: $error');
    });
  }

  Future<void> _triggerLiftAlert() async {
    setState(() {
      _isLiftDetectionActive = false;
      _averageZAcceleration = 0.0;
      _zSampleCount = 0;
      _shakeCount = 0;
      _lastShakeTime = null;
      _hasTriggered = false;
    });

    // Play alert sound
    await _playAlertSound();

    // Save lift alert details
    await _saveLiftAlert();

    // Navigate to AlertsPage to show the alert
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AlertsPage()),
    );
  }

  Future<void> _saveLiftAlert() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theftState', 'Theft Detected - Bike Lifted');
      await prefs.setString('theftTimestamp', DateTime.now().toIso8601String());

      // Fetch the current location at the time of lift detection
      String locationCoords;
      String currentPlace = 'Unknown location';
      try {
        locationCoords = await _fetchCurrentLocation();
        List<String> coords = locationCoords.split(',');
        double lat = double.parse(coords[0]);
        double lon = double.parse(coords[1]);
        currentPlace = await _reverseGeocode(lat, lon);
      } catch (e) {
        print('Failed to fetch location for lift alert: $e');
        locationCoords = '0.0,0.0';
        currentPlace = 'Location unavailable';
        _showError('Failed to fetch lift location: $e');
      }

      await prefs.setString('theftLocation', currentPlace);
      await prefs.setString('theftLatLng', locationCoords);
      print('Lift alert location saved with lat,lng: $locationCoords, place: $currentPlace');

      print('Lift alert saved at ${DateTime.now()}');
    } catch (e) {
      print('Error saving lift alert: $e');
      _showError('Failed to save lift alert: $e');
    }
  }

  Future<void> _playAlertSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/alert.mp3'));
      print('Alert sound played at ${DateTime.now()}');
    } catch (e) {
      print('Error playing alert sound: $e at ${DateTime.now()}');
      _showError('Failed to play alert sound: $e');
    }
  }

  Future<bool> _isGpsEnabled() async {
    try {
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          throw Exception('GPS not enabled');
        }
      }
      return true;
    } catch (e) {
      print('Error checking GPS: $e');
      throw Exception('Failed to check GPS: $e');
    }
  }

  Future<bool> _checkAndRequestPermission() async {
    try {
      var permission = await _location.hasPermission();
      if (permission == location_pkg.PermissionStatus.denied) {
        permission = await _location.requestPermission();
        if (permission != location_pkg.PermissionStatus.granted) {
          throw Exception('Location permission denied');
        }
      }
      return true;
    } catch (e) {
      print('Error checking/requesting permission: $e');
      throw Exception('Failed to check/request permission: $e');
    }
  }

  Future<String> _fetchCurrentLocation() async {
    int retries = 3;
    for (int i = 0; i < retries; i++) {
      try {
        print('Attempt ${i + 1} to fetch location...');
        await _isGpsEnabled();
        await _checkAndRequestPermission();

        var locationData = await _location.getLocation().timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception('Location fetch timed out'),
        );

        if (locationData.latitude != null && locationData.longitude != null) {
          print('Current location fetched: ${locationData.latitude},${locationData.longitude}');
          return '${locationData.latitude},${locationData.longitude}';
        } else {
          throw Exception('Null coordinates');
        }
      } catch (e) {
        print('Attempt ${i + 1} failed to fetch location: $e');
        if (i == retries - 1) {
          final prefs = await SharedPreferences.getInstance();
          String? lastLocation = prefs.getString('lastLocation');
          if (lastLocation != null) {
            print('Falling back to last known location: $lastLocation');
            return lastLocation;
          } else {
            throw Exception('Failed to fetch location after $retries attempts and no last known location available: $e');
          }
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    throw Exception('Failed to fetch location after $retries attempts');
  }

  Future<String> _reverseGeocode(double lat, double lon) async {
    final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon');
    try {
      print('Attempting reverse geocoding for $lat,$lon');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Reverse geocoding result: ${data['display_name']}');
        return data['display_name'] ?? 'Unknown location';
      } else {
        print('Reverse geocoding failed with status: ${response.statusCode}');
        return 'Unknown location';
      }
    } catch (e) {
      print('Error reverse geocoding: $e');
      return 'Unknown location';
    }
  }

  Future<void> _startFaceDetectionAndCapture() async {
    if (!_isCameraInitialized || _cameraController == null) return;

    setState(() {
      _isDetecting = true;
    });

    bool faceDetected = false;
    while (_isDetecting && !faceDetected) {
      try {
        final XFile image = await _cameraController!.takePicture();
        final InputImage inputImage = InputImage.fromFilePath(image.path);
        final List<Face> faces = await _faceDetector.processImage(inputImage);

        if (faces.isNotEmpty) {
          faceDetected = true;
          await _savePhotoAndAlert(image);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AlertsPage()),
          );
        }

        await File(image.path).delete();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        print('Error during face detection: $e');
        setState(() {
          _isDetecting = false;
        });
        _showError('Error detecting face: $e');
        break;
      }
    }
  }

  Future<void> _savePhotoAndAlert(XFile image) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final String fileName = 'theft_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String filePath = '${directory.path}/$fileName';
      final File newFile = await File(image.path).copy(filePath);

      if (await newFile.exists()) {
        print('Photo successfully saved at: $filePath');
      } else {
        print('Failed to save photo: File does not exist at $filePath');
        throw Exception('Photo file could not be saved');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theftPhoto', filePath);
      await prefs.setString('theftState', 'Theft Detected');
      await prefs.setString('theftTimestamp', DateTime.now().toIso8601String());

      String locationCoords;
      String currentPlace = 'Unknown location';
      try {
        locationCoords = await _fetchCurrentLocation();
        List<String> coords = locationCoords.split(',');
        double lat = double.parse(coords[0]);
        double lon = double.parse(coords[1]);
        currentPlace = await _reverseGeocode(lat, lon);
      } catch (e) {
        print('Failed to fetch location for theft alert: $e');
        locationCoords = '0.0,0.0';
        currentPlace = 'Location unavailable';
        _showError('Failed to fetch theft location: $e');
      }

      await prefs.setString('theftLocation', currentPlace);
      await prefs.setString('theftLatLng', locationCoords);
      print('Theft location saved with lat,lng: $locationCoords, place: $currentPlace');

      print('Theft alert saved with photo path: $filePath');
    } catch (e) {
      print('Error saving theft alert: $e');
      _showError('Failed to save theft alert: $e');
    }
  }

  void _showError(String message) {
    print('Showing error: $message');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('THEFT ACTIVITY'),
      ),
      body: Stack(
        children: [
          if (_isDetecting && _isCameraInitialized && _cameraController != null)
            Positioned.fill(
              child: CameraPreview(_cameraController!),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'vehicle lock',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF3E3A36),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 500,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: _isAlertTriggered ? 500 : 0,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          if (details.delta.dx > 0) {
                            setState(() {
                              _isAlertTriggered = true;
                            });
                          }
                        },
                        onHorizontalDragEnd: (details) async {
                          if (_isAlertTriggered) {
                            await _playAlertSound();
                            await _startFaceDetectionAndCapture();
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.all(5),
                          width: 50,
                          height: 50,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward,
                            color: Colors.red,
                            size: 30,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_isAlertTriggered)
                  const Text(
                    'Theft Alert Triggered!',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (_isDetecting)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Text(
                      'Detecting human face...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isLiftDetectionActive = !_isLiftDetectionActive;
                      if (!_isLiftDetectionActive) {
                        _averageZAcceleration = 0.0;
                        _zSampleCount = 0;
                        _shakeCount = 0;
                        _lastShakeTime = null;
                        _hasTriggered = false;
                      }
                    });
                  },
                  icon: Icon(
                    _isLiftDetectionActive ? Icons.stop : Icons.directions_bike,
                    color: Colors.white,
                  ),
                  label: Text(
                    _isLiftDetectionActive ? 'Stop Lift Detection' : 'Lift Bike',
                    style: const TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isLiftDetectionActive ? Colors.red : Colors.blue,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
                if (_isLiftDetectionActive)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Text(
                      'Lift detection active. Lift or shake the device to simulate bike lift...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}