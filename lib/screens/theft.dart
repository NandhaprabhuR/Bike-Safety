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
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'alerts.dart';

class TheftPage extends StatefulWidget {
  const TheftPage({super.key});

  @override
  State<TheftPage> createState() => _TheftPageState();
}

class _TheftPageState extends State<TheftPage> with SingleTickerProviderStateMixin {
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
  static const double liftAccelerationThreshold = 0.5;
  static const int liftSampleThreshold = 10;
  static const double shakeThreshold = 2.0;
  static const int shakeCountThreshold = 2;
  int _shakeCount = 0;
  DateTime? _lastShakeTime;
  bool _hasTriggered = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _checkLocationPermissions();
    _setupLiftAndShakeDetection();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);
    _animationController.forward();
  }

  Future<void> _checkLocationPermissions() async {
    try {
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          _showError('Location services are disabled. Please enable them to use this feature.');
          return;
        }
      }

      var permission = await _location.hasPermission();
      if (permission == location_pkg.PermissionStatus.denied) {
        permission = await _location.requestPermission();
        if (permission != location_pkg.PermissionStatus.granted) {
          _showError('Location permissions are denied. Please grant permissions to use this feature.');
          return;
        }
      }
    } catch (e) {
      print('Error checking location permissions: $e');
      _showError('Failed to check location permissions: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
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
          print('Camera initialized successfully');
        }
      } else {
        _showError('No camera available');
      }
    } catch (e) {
      print('Error initializing camera: $e');
      _showError('Failed to initialize camera: $e');
    }
  }

  void _setupLiftAndShakeDetection() {
    accelerometerEventStream().listen((AccelerometerEvent event) {
      if (!_isLiftDetectionActive || _hasTriggered) return;

      print('Accelerometer Event - X: ${event.x}, Y: ${event.y}, Z: ${event.z}');

      double accelerationZ = event.z;
      double netAcceleration = accelerationZ - 9.8;

      _zSampleCount++;
      _averageZAcceleration = (_averageZAcceleration * (_zSampleCount - 1) + netAcceleration) / _zSampleCount;

      print('Lift Detection - Net Z Acceleration: $netAcceleration, Average: $_averageZAcceleration, Samples: $_zSampleCount');

      if (_averageZAcceleration > liftAccelerationThreshold && _zSampleCount >= liftSampleThreshold) {
        print('Lift detected: Average Z Acceleration $_averageZAcceleration m/s² over $_zSampleCount samples');
        _hasTriggered = true;
        _triggerLiftAlert();
      }

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
    }, onDone: () {
      print('Accelerometer stream closed');
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

    await _playAlertSound();

    Map<String, dynamic> latestAlert = await _saveLiftAlert();
    print('latestAlert data: $latestAlert');

    print('Triggering lift alert and navigating to AlertsPage');
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => AlertsPage(latestAlert: latestAlert)),
      );
      print('Navigation to AlertsPage successful');
    } catch (e) {
      print('Navigation to AlertsPage failed: $e');
      _showError('Failed to navigate to AlertsPage: $e');
    }
  }

  Future<Map<String, dynamic>> _saveLiftAlert() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      String locationCoords;
      String currentPlace = 'Unknown location';
      LatLng? parsedLatLng;
      Set<Marker> markers = {};
      String? locationError;
      try {
        locationCoords = await _fetchCurrentLocation();
        List<String> coords = locationCoords.split(',');
        double lat = double.parse(coords[0]);
        double lon = double.parse(coords[1]);
        currentPlace = await _reverseGeocode(lat, lon);
        if (lat == 0.0 && lon == 0.0) {
          locationError = 'Theft location coordinates not available';
        } else {
          parsedLatLng = LatLng(lat, lon);
          markers = {
            Marker(
              markerId: const MarkerId('theft_location'),
              position: parsedLatLng,
              infoWindow: const InfoWindow(title: 'Theft Location'),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            ),
          };
          print('Theft location saved: $locationCoords');
        }
      } catch (e) {
        print('Failed to fetch location for lift alert: $e');
        locationCoords = '0.0,0.0';
        currentPlace = 'Location unavailable';
        locationError = 'Failed to fetch theft location: $e';
        _showError('Failed to fetch lift location: $e');
      }

      String timestamp = DateTime.now().toIso8601String();
      String formattedTimestamp = DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(timestamp));

      List<Map<String, String>> existingAlerts = [];
      String? alertsJson = prefs.getString('theftAlerts');
      if (alertsJson != null) {
        List<dynamic> decoded = jsonDecode(alertsJson);
        existingAlerts = decoded.map((item) => Map<String, String>.from(item)).toList();
      }

      int priority = existingAlerts.length + 1;

      Map<String, String> newAlert = {
        'theftState': 'Theft Detected - Bike Lifted',
        'theftTimestamp': timestamp,
        'theftPhoto': '',
        'theftLocation': currentPlace,
        'theftLatLng': locationCoords,
        'priority': priority.toString(),
      };

      existingAlerts.add(newAlert);

      await prefs.setString('theftAlerts', jsonEncode(existingAlerts));
      print('Lift alert saved at ${DateTime.now()} with location: $locationCoords, place: $currentPlace');
      print('Saved theftAlerts: ${jsonEncode(existingAlerts)}');

      return {
        'theftState': newAlert['theftState'] ?? 'Theft Detected - Bike Lifted',
        'theftTimestamp': formattedTimestamp,
        'theftPhoto': newAlert['theftPhoto']?.isNotEmpty == true ? newAlert['theftPhoto'] : null,
        'theftLocation': newAlert['theftLocation'] ?? 'Unknown location',
        'theftLatLng': parsedLatLng,
        'theftMarkers': markers,
        'theftLocationError': locationError,
        'theftStateColor': Colors.red.shade700,
        'priority': priority,
      };
    } catch (e) {
      print('Error saving lift alert: $e');
      _showError('Failed to save lift alert: $e');
      return {
        'theftState': 'Theft Detection Failed',
        'theftTimestamp': DateFormat('MMM d, yyyy h:mm a').format(DateTime.now()),
        'theftPhoto': null,
        'theftLocation': 'Error saving lift alert',
        'theftLatLng': null,
        'theftMarkers': <Marker>{},
        'theftLocationError': 'Error: $e',
        'theftStateColor': Colors.red.shade700,
        'priority': 0,
      };
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

  Future<String> _fetchCurrentLocation() async {
    int retries = 3;
    const timeoutDuration = Duration(seconds: 5); // Reduced timeout
    for (int i = 0; i < retries; i++) {
      try {
        print('Attempt ${i + 1} to fetch location...');
        bool gpsEnabled = await _location.serviceEnabled();
        if (!gpsEnabled) {
          gpsEnabled = await _location.requestService();
          if (!gpsEnabled) {
            print('GPS not enabled, falling back to default location');
            return '0.0,0.0';
          }
        }

        var permission = await _location.hasPermission();
        if (permission == location_pkg.PermissionStatus.denied) {
          permission = await _location.requestPermission();
          if (permission != location_pkg.PermissionStatus.granted) {
            print('Location permission not granted, falling back to default location');
            return '0.0,0.0';
          }
        }

        var locationData = await _location.getLocation().timeout(
          timeoutDuration,
          onTimeout: () {
            print('Location fetch timed out after ${timeoutDuration.inSeconds} seconds');
            throw Exception('Location fetch timed out');
          },
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
            print('Failed to fetch location after $retries attempts, using default location');
            return '0.0,0.0';
          }
        }
        await Future.delayed(const Duration(seconds: 2)); // Increased delay between retries
      }
    }
    print('Failed to fetch location after $retries attempts, using default location');
    return '0.0,0.0';
  }

  Future<String> _reverseGeocode(double lat, double lon) async {
    final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon');
    try {
      print('Attempting reverse geocoding for $lat,$lon');
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'DesignThinkingApp/1.0 (contact: your-email@example.com)',
        },
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Reverse geocoding result: ${data['display_name']}');
        return data['display_name'] ?? 'Unknown location';
      } else {
        print('Reverse geocoding failed with status: ${response.statusCode}');
        if (response.statusCode == 403) {
          return 'Geocoding failed: API access denied (403)';
        }
        return 'Unknown location';
      }
    } catch (e) {
      print('Error reverse geocoding: $e');
      return 'Unknown location';
    }
  }

  Future<void> _startFaceDetectionAndCapture() async {
    if (!_isCameraInitialized || _cameraController == null) {
      print('Camera not initialized, cannot start face detection');
      _showError('Camera not initialized');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AlertsPage(
            latestAlert: {
              'theftState': 'Theft Detection Failed',
              'theftTimestamp': DateFormat('MMM d, yyyy h:mm a').format(DateTime.now()),
              'theftPhoto': null,
              'theftLocation': 'Camera not initialized',
              'theftLatLng': null,
              'theftMarkers': <Marker>{},
              'theftLocationError': 'Camera not initialized',
              'theftStateColor': Colors.red.shade700,
              'priority': 0,
            },
          ),
        ),
      );
      return;
    }

    if (mounted) {
      setState(() {
        _isDetecting = true;
      });
    }

    bool faceDetected = false;
    int attempts = 0;
    const maxAttempts = 10;

    while (_isDetecting && !faceDetected && attempts < maxAttempts) {
      try {
        print('Attempt ${attempts + 1}/$maxAttempts: Taking picture for face detection...');
        final XFile image = await _cameraController!.takePicture();
        print('Picture taken: ${image.path}');
        final InputImage inputImage = InputImage.fromFilePath(image.path);
        final List<Face> faces = await _faceDetector.processImage(inputImage);
        print('Face detection completed, detected ${faces.length} faces');

        if (faces.isNotEmpty) {
          faceDetected = true;
          print('Face detected, saving alert...');
          Map<String, dynamic> latestAlert = await _savePhotoAndAlert(image);
          print('latestAlert data: $latestAlert');
          if (mounted) {
            setState(() {
              _isDetecting = false;
            });
          }
          try {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => AlertsPage(latestAlert: latestAlert)),
            );
            print('Navigation to AlertsPage successful');
          } catch (e) {
            print('Navigation to AlertsPage failed: $e');
            _showError('Failed to navigate to AlertsPage: $e');
          }
        } else {
          print('No face detected in this frame');
        }

        await File(image.path).delete();
        attempts++;
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        print('Error during face detection: $e');
        if (mounted) {
          setState(() {
            _isDetecting = false;
          });
        }
        _showError('Error detecting face: $e');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlertsPage(
              latestAlert: {
                'theftState': 'Theft Detection Failed',
                'theftTimestamp': DateFormat('MMM d, yyyy h:mm a').format(DateTime.now()),
                'theftPhoto': null,
                'theftLocation': 'Error during face detection',
                'theftLatLng': null,
                'theftMarkers': <Marker>{},
                'theftLocationError': 'Error: $e',
                'theftStateColor': Colors.red.shade700,
                'priority': 0,
              },
            ),
          ),
        );
        break;
      }
    }

    if (!faceDetected && attempts >= maxAttempts) {
      print('Max face detection attempts ($maxAttempts) reached, no face detected');
      if (mounted) {
        setState(() {
          _isDetecting = false;
        });
      }
      _showError('No face detected after $maxAttempts attempts');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AlertsPage(
            latestAlert: {
              'theftState': 'Theft Detection Attempted',
              'theftTimestamp': DateFormat('MMM d, yyyy h:mm a').format(DateTime.now()),
              'theftPhoto': null,
              'theftLocation': 'No face detected',
              'theftLatLng': null,
              'theftMarkers': <Marker>{},
              'theftLocationError': 'No face detected after $maxAttempts attempts',
              'theftStateColor': Colors.red.shade700,
              'priority': 0,
            },
          ),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _isDetecting = false;
      });
    }
  }

  Future<Map<String, dynamic>> _savePhotoAndAlert(XFile image) async {
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
      String timestamp = DateTime.now().toIso8601String();
      String formattedTimestamp = DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(timestamp));

      String locationCoords;
      String currentPlace = 'Unknown location';
      LatLng? parsedLatLng;
      Set<Marker> markers = {};
      String? locationError;
      try {
        locationCoords = await _fetchCurrentLocation();
        List<String> coords = locationCoords.split(',');
        double lat = double.parse(coords[0]);
        double lon = double.parse(coords[1]);
        currentPlace = await _reverseGeocode(lat, lon);
        if (lat == 0.0 && lon == 0.0) {
          locationError = 'Theft location coordinates not available';
        } else {
          parsedLatLng = LatLng(lat, lon);
          markers = {
            Marker(
              markerId: const MarkerId('theft_location'),
              position: parsedLatLng,
              infoWindow: const InfoWindow(title: 'Theft Location'),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            ),
          };
          print('Theft location saved: $locationCoords');
        }
      } catch (e) {
        print('Failed to fetch location for theft alert: $e');
        locationCoords = '0.0,0.0';
        currentPlace = 'Location unavailable';
        locationError = 'Failed to fetch theft location: $e';
        _showError('Failed to fetch theft location: $e');
      }

      List<Map<String, String>> existingAlerts = [];
      String? alertsJson = prefs.getString('theftAlerts');
      if (alertsJson != null) {
        List<dynamic> decoded = jsonDecode(alertsJson);
        existingAlerts = decoded.map((item) => Map<String, String>.from(item)).toList();
      }

      int priority = existingAlerts.length + 1;

      Map<String, String> newAlert = {
        'theftState': 'Theft Detected',
        'theftTimestamp': timestamp,
        'theftPhoto': filePath,
        'theftLocation': currentPlace,
        'theftLatLng': locationCoords,
        'priority': priority.toString(),
      };

      existingAlerts.add(newAlert);

      await prefs.setString('theftAlerts', jsonEncode(existingAlerts));
      print('Theft alert saved with photo path: $filePath, location: $locationCoords, place: $currentPlace');
      print('Saved theftAlerts: ${jsonEncode(existingAlerts)}');

      return {
        'theftState': newAlert['theftState'] ?? 'Theft Detected',
        'theftTimestamp': formattedTimestamp,
        'theftPhoto': newAlert['theftPhoto']?.isNotEmpty == true ? newAlert['theftPhoto'] : null,
        'theftLocation': newAlert['theftLocation'] ?? 'Unknown location',
        'theftLatLng': parsedLatLng,
        'theftMarkers': markers,
        'theftLocationError': locationError,
        'theftStateColor': Colors.red.shade700,
        'priority': priority,
      };
    } catch (e) {
      print('Error saving theft alert: $e');
      _showError('Failed to save theft alert: $e');
      return {
        'theftState': 'Theft Detection Failed',
        'theftTimestamp': DateFormat('MMM d, yyyy h:mm a').format(DateTime.now()),
        'theftPhoto': null,
        'theftLocation': 'Error saving alert',
        'theftLatLng': null,
        'theftMarkers': <Marker>{},
        'theftLocationError': 'Error: $e',
        'theftStateColor': Colors.red.shade700,
        'priority': 0,
      };
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
  void dispose() async {
    _audioPlayer.dispose();
    if (_isDetecting) {
      _isDetecting = false;
    }
    // Check if the camera controller is initialized and streaming
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        // Avoid calling stopImageStream since it's not started
        print('Camera stream not started, skipping stopImageStream');
      } catch (e) {
        print('Error stopping image stream during dispose: $e');
      }
      // Add a slight delay to ensure any pending operations complete
      await Future.delayed(const Duration(milliseconds: 100));
      await _cameraController?.dispose();
      print('Camera disposed successfully');
    }
    _faceDetector.close();
    _animationController.dispose();
    print('TheftPage disposed, camera and face detector cleaned up');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('THEFT ACTIVITY'),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
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
      ),
    );
  }
}