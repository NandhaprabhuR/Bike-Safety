import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'fmap.dart';
import 'alerts.dart';
import 'dart:math' as math;

class HomeScreen extends StatefulWidget {
  final String userName;
  final Map<String, dynamic>? initialWeatherData;

  const HomeScreen({required this.userName, this.initialWeatherData, super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _weatherCondition = 'Loading...';
  String _temperature = '--';
  String _feelsLike = '--';
  String _humidity = '--';
  IconData _weatherIcon = Icons.cloud;
  bool _isLoading = false;
  final Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  String _currentLocation = 'Fetching location...';
  bool _isVehicleRunning = false;
  GoogleMapController? _mapController;
  LatLng? _currentPosition;

  // Variables for Daily Usage
  String _currentPlace = 'Fetching location...';
  String _distanceMoved = 'Calculating...';
  String _vehicleState = 'Checking vehicle state...';
  String _lastUpdated = 'N/A';
  Color _vehicleStateColor = Colors.white;
  bool _isDailyUsageLoading = true;

  // Add variables for tracking distance and previous location like in MapScreen
  LatLng? _previousLocation;
  double _distanceMovedValue = 0.0;

  // Firestore instance
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot>? _userStatusSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.initialWeatherData != null) {
      setState(() {
        _temperature = widget.initialWeatherData!['temperature'] ?? '--';
        _weatherCondition = widget.initialWeatherData!['weatherCondition'] ?? 'Unknown';
        _weatherIcon = widget.initialWeatherData!['weatherIcon'] ?? Icons.cloud;
        _feelsLike = widget.initialWeatherData!['feelsLike'] ?? '--';
        _humidity = widget.initialWeatherData!['humidity'] ?? '--';
        _isLoading = false;
      });
    } else {
      _setupLocation();
      _fetchWeatherData();
      _startLocationUpdates();
    }
    _loadPreviousData();
    _startLocationTracking();
    _fetchDailyUsage();
    _initializeVehicleState(); // Initialize vehicle state
    _resumeListeningForStatus(); // Resume listening for status updates
  }

  Future<void> _initializeVehicleState() async {
    // Restore _isVehicleRunning from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isVehicleRunning = prefs.getBool('isVehicleRunning') ?? false;
    });
    print('Restored _isVehicleRunning from SharedPreferences: $_isVehicleRunning at ${DateTime.now()}');

    // Check Firestore for the latest state
    await _checkVehicleStateOnInit();
  }

  Future<void> _checkVehicleStateOnInit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final faceId = prefs.getString('lastFaceId');
      if (faceId == null) {
        print('No faceId found in SharedPreferences at ${DateTime.now()}');
        return;
      }

      final snapshot = await _firestore
          .collection('registered_faces')
          .where('faceId', isEqualTo: faceId)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final userDoc = snapshot.docs.first;
        final data = userDoc.data();
        final hasStartedVehicle = data['hasStartedVehicle'] as bool? ?? false;
        final status = data['status'] as String? ?? 'pending';

        if (hasStartedVehicle && status == 'accepted') {
          setState(() {
            _isVehicleRunning = true;
          });
          await prefs.setBool('isVehicleRunning', true);
          print('Updated _isVehicleRunning to true based on Firestore check for faceId: $faceId at ${DateTime.now()}');
        } else {
          setState(() {
            _isVehicleRunning = false;
          });
          await prefs.setBool('isVehicleRunning', false);
          print('Updated _isVehicleRunning to false based on Firestore check for faceId: $faceId at ${DateTime.now()}');
        }
      } else {
        print('No user found with faceId: $faceId during init check at ${DateTime.now()}');
      }
    } catch (e) {
      print('Error checking vehicle state on init: $e at ${DateTime.now()}');
    }
  }

  Future<void> _resumeListeningForStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final faceId = prefs.getString('lastFaceId');
      final requestId = prefs.getString('lastRequestId');
      if (faceId != null && requestId != null) {
        print('Resuming listening for faceId: $faceId and requestId: $requestId at ${DateTime.now()}');
        _listenToUserStatus(faceId, requestId);
      } else {
        print('No faceId or requestId found in SharedPreferences to resume listening at ${DateTime.now()}');
      }
    } catch (e) {
      print('Error resuming status listening: $e at ${DateTime.now()}');
    }
  }

  Future<void> _loadPreviousData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? lastLocation = prefs.getString('lastLocation');
    double? distanceMoved = prefs.getDouble('distanceMoved');
    bool? isFirstFetch = prefs.getBool('isFirstFetch') ?? true;

    if (lastLocation != null) {
      List<String> coords = lastLocation.split(',');
      _previousLocation = LatLng(double.parse(coords[0]), double.parse(coords[1]));
    }
    _distanceMovedValue = distanceMoved ?? 0.0;
    if (isFirstFetch) {
      await prefs.setBool('isFirstFetch', false);
    }
  }

  Future<void> _startLocationTracking() async {
    try {
      bool gpsEnabled = await _isGpsEnabled();
      if (!gpsEnabled) {
        setState(() {
          _currentLocation = 'GPS disabled';
          _currentPosition = const LatLng(12.9716, 77.5946);
        });
        return;
      }

      bool permissionGranted = await _checkAndRequestPermission();
      if (!permissionGranted) {
        setState(() {
          _currentLocation = 'Permission denied';
          _currentPosition = const LatLng(12.9716, 77.5946);
        });
        return;
      }

      _locationSubscription = _location.onLocationChanged.listen((LocationData locationData) async {
        if (locationData.latitude != null && locationData.longitude != null) {
          _currentLocation = '${locationData.latitude!.toStringAsFixed(2)}, ${locationData.longitude!.toStringAsFixed(2)}';
          _currentPosition = LatLng(locationData.latitude!, locationData.longitude!);
          await _updateLocationData(locationData);
          _mapController?.animateCamera(CameraUpdate.newLatLng(_currentPosition!));
          _fetchDailyUsage();
        }
      }, onError: (e) {
        setState(() {
          _currentLocation = 'Error fetching location';
          _currentPosition = const LatLng(12.9716, 77.5946);
        });
      });
    } catch (e) {
      setState(() {
        _currentLocation = 'Error: $e';
        _currentPosition = const LatLng(12.9716, 77.5946);
      });
    }
  }

  Future<void> _updateLocationData(LocationData locationData) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String currentPlace = await _reverseGeocode(locationData.latitude!, locationData.longitude!);
    DateTime now = DateTime.now();

    if (_previousLocation != null) {
      const double earthRadius = 6371;
      double dLat = (locationData.latitude! - _previousLocation!.latitude) * math.pi / 180;
      double dLon = (locationData.longitude! - _previousLocation!.longitude) * math.pi / 180;
      double lat1 = _previousLocation!.latitude * math.pi / 180;
      double lat2 = locationData.latitude! * math.pi / 180;

      double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
      double c = 2 * math.asin(math.sqrt(a));
      double distanceInKm = earthRadius * c;

      _distanceMovedValue += distanceInKm;

      if (locationData.speed != null) {
        double speedInKmh = locationData.speed! * 3.6;
        _vehicleState = speedInKmh > 5 ? 'Moving' : distanceInKm < 0.01 ? 'Stationary' : 'Locked';
      } else {
        _vehicleState = distanceInKm < 0.01 ? 'Stationary' : 'Locked';
      }
    } else {
      _vehicleState = 'Locked';
    }

    _previousLocation = LatLng(locationData.latitude!, locationData.longitude!);

    await prefs.setString('currentPlace', currentPlace);
    await prefs.setDouble('distanceMoved', _distanceMovedValue);
    await prefs.setString('lastUpdated', now.toIso8601String());
    await prefs.setString('lastLocation', '${locationData.latitude},${locationData.longitude}');
    await prefs.setString('vehicleState', _vehicleState);
    print('Updated SharedPreferences in HomeScreen with lastLocation: ${locationData.latitude},${locationData.longitude}');
  }

  Future<String> _reverseGeocode(double lat, double lon) async {
    final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Reverse geocoding result in HomeScreen: ${data['display_name']}');
        return data['display_name'] ?? 'Unknown';
      } else {
        print('Reverse geocoding failed with status in HomeScreen: ${response.statusCode}');
      }
    } catch (e) {
      print('Error reverse geocoding in HomeScreen: $e');
    }
    return 'Unknown';
  }

  Future<void> _fetchDailyUsage() async {
    setState(() {
      _isDailyUsageLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      String? currentPlace = prefs.getString('currentPlace');
      double? distanceMoved = prefs.getDouble('distanceMoved');
      String? lastUpdated = prefs.getString('lastUpdated');
      String? vehicleState = prefs.getString('vehicleState');
      bool? isFirstFetch = prefs.getBool('isFirstFetch') ?? true;

      print('SharedPreferences values for Daily Usage in HomeScreen:');
      print('currentPlace: $currentPlace');
      print('distanceMoved: $distanceMoved');
      print('lastUpdated: $lastUpdated');
      print('vehicleState: $vehicleState');

      if (currentPlace == null || distanceMoved == null || lastUpdated == null || vehicleState == null) {
        throw Exception("Some vehicle data fields are missing.");
      }

      String formattedLastUpdated = DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(lastUpdated));

      Color stateColor;
      switch (vehicleState) {
        case 'Moving':
          stateColor = Colors.red.shade700;
          break;
        case 'Stationary':
          stateColor = Colors.green.shade700;
          break;
        default:
          stateColor = Colors.orange;
      }

      setState(() {
        _currentPlace = currentPlace;
        _distanceMoved = isFirstFetch ? 'No previous data' : '${distanceMoved.toStringAsFixed(2)} km';
        _vehicleState = vehicleState;
        _lastUpdated = formattedLastUpdated;
        _vehicleStateColor = stateColor;
        _isDailyUsageLoading = false;
      });
    } catch (e) {
      setState(() {
        _currentPlace = 'Error: $e';
        _distanceMoved = 'Error';
        _vehicleState = 'Error';
        _lastUpdated = 'N/A';
        _isDailyUsageLoading = false;
      });
    }
  }

  Future<void> _setupLocation() async {
    try {
      await _location.changeSettings(
        accuracy: LocationAccuracy.balanced,
        distanceFilter: 1,
        interval: 500,
      );
      print('Location settings configured: balanced accuracy, 1m distance filter, 500ms interval at ${DateTime.now()}');
    } catch (e) {
      print('Error configuring location settings: $e at ${DateTime.now()}');
    }
  }

  Future<bool> _isGpsEnabled() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      print('Location service not enabled, requesting service at ${DateTime.now()}');
      serviceEnabled = await _location.requestService();
    }
    return serviceEnabled;
  }

  Future<bool> _checkAndRequestPermission() async {
    PermissionStatus permission = await _location.hasPermission();
    if (permission == PermissionStatus.denied) {
      print('Location permission denied, requesting permission at ${DateTime.now()}');
      permission = await _location.requestPermission();
    }
    return permission == PermissionStatus.granted;
  }

  Future<void> _fetchWeatherData() async {
    setState(() {
      _isLoading = true;
      _weatherCondition = 'Loading...';
      _temperature = '--';
      _feelsLike = '--';
      _humidity = '--';
    });

    try {
      bool gpsEnabled = await _isGpsEnabled();
      if (!gpsEnabled) {
        throw Exception('GPS is disabled. Please enable it in your device settings.');
      }

      bool permissionGranted = await _checkAndRequestPermission();
      if (!permissionGranted) {
        throw Exception('Location permission denied. Please grant permission.');
      }

      print('Attempting to get location with getLocation() at ${DateTime.now()}');
      LocationData? locationData;
      try {
        locationData = await _location.getLocation().timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw Exception('Initial fetch timed out. Waiting for location stream...'),
        );
      } catch (e) {
        print('Error with getLocation: $e at ${DateTime.now()}');
        print('Falling back to location stream for initial location at ${DateTime.now()}');
        int streamAttempts = 0;
        const int maxStreamAttempts = 3;
        const int streamTimeoutSeconds = 30;

        _locationSubscription = _location.onLocationChanged.listen((LocationData data) {
          if (data.latitude != null && data.longitude != null) {
            locationData = data;
            print('Location fetched via stream: ${data.latitude}, ${data.longitude}, accuracy: ${data.accuracy}m at ${DateTime.now()}');
            _locationSubscription?.cancel();
          }
        }, onError: (e) {
          print('Error listening to location stream: $e at ${DateTime.now()}');
        });

        while (streamAttempts < maxStreamAttempts && locationData == null) {
          streamAttempts++;
          print('Waiting for location stream (attempt $streamAttempts/$maxStreamAttempts) at ${DateTime.now()}');
          await Future.delayed(const Duration(seconds: streamTimeoutSeconds ~/ maxStreamAttempts));
          if (locationData != null) {
            break;
          }
        }

        if (locationData == null) {
          throw Exception('Failed to get location via stream after $maxStreamAttempts attempts.');
        }
      }

      double latitude = locationData!.latitude ?? 12.9716;
      double longitude = locationData?.longitude ?? 77.5946;

      if (latitude == 12.9716 && longitude == 77.5946) {
        print('Using default location (Bangalore) as location fetch failed at ${DateTime.now()}');
      } else {
        print('Location fetched successfully: $latitude, $longitude at ${DateTime.now()}');
      }

      Map<String, dynamic> simulatedWeather = _simulateWeatherData(latitude, longitude);

      setState(() {
        _temperature = simulatedWeather['temperature'].toString();
        _weatherCondition = simulatedWeather['weatherCondition'];
        _weatherIcon = simulatedWeather['weatherIcon'];
        _feelsLike = simulatedWeather['feelsLike'].toString();
        _humidity = simulatedWeather['humidity'].toString();
        _isLoading = false;
      });
      print('Simulated weather data: $_weatherCondition, $_temperature°C at ${DateTime.now()}');
    } catch (e) {
      print('Error in _fetchWeatherData: $e at ${DateTime.now()}');
      setState(() {
        _weatherCondition = 'Failed to load weather: $e. Try moving to an open area or enabling Wi-Fi. Tap to retry.';
        _isLoading = false;
      });
    }
  }

  void _startLocationUpdates() async {
    try {
      bool gpsEnabled = await _isGpsEnabled();
      if (!gpsEnabled) {
        setState(() {
          _currentLocation = 'GPS disabled';
          _currentPosition = const LatLng(12.9716, 77.5946);
        });
        return;
      }

      bool permissionGranted = await _checkAndRequestPermission();
      if (!permissionGranted) {
        setState(() {
          _currentLocation = 'Permission denied';
          _currentPosition = const LatLng(12.9716, 77.5946);
        });
        return;
      }

      _locationSubscription = _location.onLocationChanged.listen((LocationData data) {
        if (data.latitude != null && data.longitude != null) {
          setState(() {
            _currentLocation = '${data.latitude!.toStringAsFixed(2)}, ${data.longitude!.toStringAsFixed(2)}';
            _currentPosition = LatLng(data.latitude!, data.longitude!);
          });
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(_currentPosition!),
          );
        }
      }, onError: (e) {
        setState(() {
          _currentLocation = 'Error fetching location';
          _currentPosition = const LatLng(12.9716, 77.5946);
        });
      });
    } catch (e) {
      setState(() {
        _currentLocation = 'Error: $e';
        _currentPosition = const LatLng(12.9716, 77.5946);
      });
    }
  }

  Map<String, dynamic> _simulateWeatherData(double latitude, double longitude) {
    double temperature;
    String weatherCondition;
    IconData weatherIcon;
    double feelsLike;
    int humidity;

    if (latitude > 25) {
      temperature = 38.0;
      weatherCondition = 'Clear';
      weatherIcon = Icons.wb_sunny;
      feelsLike = 40.0;
      humidity = 30;
    } else if (latitude > 20 && latitude <= 25) {
      temperature = 30.0;
      weatherCondition = 'Drizzle';
      weatherIcon = Icons.grain;
      feelsLike = 32.0;
      humidity = 70;
    } else if (latitude > 15 && latitude <= 20) {
      temperature = 32.0;
      weatherCondition = 'Cloudy';
      weatherIcon = Icons.cloud;
      feelsLike = 36.0;
      humidity = 80;
    } else {
      temperature = 29.0;
      weatherCondition = 'Cloudy';
      weatherIcon = Icons.cloud;
      feelsLike = 31.0;
      humidity = 60;
    }

    temperature -= 2.0;
    feelsLike -= 2.0;

    return {
      'temperature': temperature,
      'weatherCondition': weatherCondition,
      'weatherIcon': weatherIcon,
      'feelsLike': feelsLike,
      'humidity': humidity,
    };
  }

  void _onItemTapped(int index, BuildContext context) {
    setState(() {
      _selectedIndex = index;
    });
    switch (index) {
      case 0:
        print('Home tapped');
        // Recheck vehicle state when returning to HomeScreen
        _checkVehicleStateOnInit();
        break;
      case 1:
        print('Notifications tapped');
        try {
          Navigator.pushNamed(context, '/alerts').then((_) {
            print('Returned from AlertsPage');
            _checkVehicleStateOnInit(); // Recheck state after returning
          }).catchError((e) {
            print('Navigation error to AlertsPage: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to open alerts: $e')),
            );
          });
        } catch (e) {
          print('Error navigating to AlertsPage: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error opening alerts: $e')),
          );
        }
        break;
      case 2:
        print('Users tapped');
        try {
          Navigator.pushNamed(context, '/users').then((_) {
            print('Returned from UsersScreen');
            _checkVehicleStateOnInit(); // Recheck state after returning
          }).catchError((e) {
            print('Navigation error to UsersScreen: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to open users: $e')),
            );
          });
        } catch (e) {
          print('Error navigating to UsersScreen: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error opening users: $e')),
          );
        }
        break;
      case 3:
        print('Theft Stealing tapped');
        try {
          Navigator.pushNamed(context, '/theft').then((_) {
            print('Returned from TheftPage');
            _checkVehicleStateOnInit(); // Recheck state after returning
          }).catchError((e) {
            print('Navigation error to TheftPage: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to open theft page: $e')),
            );
          });
        } catch (e) {
          print('Error navigating to TheftPage: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error opening theft page: $e')),
          );
        }
        break;
      case 4:
        print('Profile tapped');
        try {
          Navigator.pushNamed(context, '/profile').then((_) {
            print('Returned from ProfileScreen');
            _checkVehicleStateOnInit(); // Recheck state after returning
          }).catchError((e) {
            print('Navigation error to ProfileScreen: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to open profile: $e')),
            );
          });
        } catch (e) {
          print('Error navigating to ProfileScreen: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error opening profile: $e')),
          );
        }
        break;
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapController?.dispose();
    // Do not cancel _userStatusSubscription here to keep listening
    super.dispose();
  }

  Widget _infoTile(IconData icon, String title, String value, {Color? color}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color ?? Theme.of(context).iconTheme.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(color: color ?? Theme.of(context).colorScheme.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
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

  void _listenToUserStatus(String faceId, String requestId) async {
    // Cancel any existing subscription to avoid duplicates
    await _userStatusSubscription?.cancel();

    final query = _firestore
        .collection('registered_faces')
        .where('faceId', isEqualTo: faceId)
        .limit(1);

    final snapshot = await query.get();
    if (snapshot.docs.isEmpty) {
      print('No user found with faceId: $faceId at ${DateTime.now()}');
      return;
    }

    final docRef = snapshot.docs.first.reference;
    _userStatusSubscription = docRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) {
        print('User document for faceId: $faceId no longer exists at ${DateTime.now()}');
        return;
      }

      final data = snapshot.data() as Map<String, dynamic>;
      final status = data['status'] as String? ?? 'pending';
      final currentRequestId = data['currentRequestId'] as String?;
      final hasStartedVehicle = data['hasStartedVehicle'] as bool? ?? false;

      print('User status for faceId $faceId updated to: $status with currentRequestId: $currentRequestId at ${DateTime.now()}');

      // If status is 'accepted', update the state regardless of requestId match
      if (status == 'accepted' && hasStartedVehicle) {
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          _isVehicleRunning = true;
        });
        await prefs.setBool('isVehicleRunning', true);
        await _startVehicle(faceId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission approved! Vehicle has started.'),
          ),
        );
        print('Vehicle started for faceId: $faceId at ${DateTime.now()}');
      } else if (status == 'rejected') {
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          _isVehicleRunning = false;
        });
        await prefs.setBool('isVehicleRunning', false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission rejected. Vehicle start denied.'),
          ),
        );
        print('Vehicle start denied for faceId: $faceId at ${DateTime.now()}');
      }
    }, onError: (e) {
      print('Error listening to user status for faceId $faceId: $e at ${DateTime.now()}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error monitoring permission status: $e')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 28),
                Text(
                  'Welcome Nandhaprabhu R',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _isLoading ? null : _fetchWeatherData,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _weatherCondition,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                                  ),
                                ),
                                if (!_isLoading && _weatherCondition.contains('Tap to retry'))
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: Icon(
                                      Icons.refresh,
                                      color: Theme.of(context).colorScheme.onSurface,
                                      size: 16,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _temperature,
                                  style: const TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '°',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Feels like $_feelsLike°',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _weatherIcon,
                              color: Theme.of(context).iconTheme.color,
                              size: 40,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.water_drop,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$_humidity%',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
                  child: Text(
                    'Vehicle Controls',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (!_isVehicleRunning) {
                            final result = await Navigator.pushNamed(context, '/face');
                            if (result != null && result is Map<String, dynamic>) {
                              String faceId = result['faceId'] as String;
                              String requestId = result['requestId'] as String;
                              _listenToUserStatus(faceId, requestId);
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isVehicleRunning ? Colors.red : Theme.of(context).colorScheme.secondary,
                          foregroundColor: Theme.of(context).colorScheme.onSecondary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          _isVehicleRunning ? 'Vehicle Started' : 'Start Vehicle',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          setState(() {
                            _isVehicleRunning = false;
                          });
                          await prefs.setBool('isVehicleRunning', false);
                          // Update Firestore to reflect vehicle stopped
                          final faceId = prefs.getString('lastFaceId');
                          if (faceId != null) {
                            final userSnapshot = await _firestore
                                .collection('registered_faces')
                                .where('faceId', isEqualTo: faceId)
                                .get();
                            if (userSnapshot.docs.isNotEmpty) {
                              final userDoc = userSnapshot.docs.first;
                              await userDoc.reference.update({
                                'hasStartedVehicle': false,
                                'status': 'pending',
                                'currentRequestId': null,
                              });
                              print('Vehicle stopped for faceId: $faceId at ${DateTime.now()}');
                            }
                          }
                          // Clear SharedPreferences
                          await prefs.remove('lastFaceId');
                          await prefs.remove('lastRequestId');
                          print('Stop Vehicle button pressed, state reset');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.secondary,
                          foregroundColor: Theme.of(context).colorScheme.onSecondary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: const Text(
                          'Stop Vehicle',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
                  child: Text(
                    'Current Location',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  height: 300,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _currentPosition == null
                        ? const Center(child: CircularProgressIndicator())
                        : GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _currentPosition!,
                        zoom: 15,
                      ),
                      onMapCreated: (GoogleMapController controller) {
                        _mapController = controller;
                      },
                      markers: {
                        Marker(
                          markerId: const MarkerId('current_location'),
                          position: _currentPosition!,
                          infoWindow: InfoWindow(title: 'Your vehicle Location', snippet: _currentLocation),
                        ),
                      },
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
                  child: Text(
                    'Daily Usage',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: _isDailyUsageLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoTile(Icons.place, "Current Place", _currentPlace),
                      _infoTile(Icons.map, "Distance Moved", _distanceMoved),
                      _infoTile(Icons.security, "Vehicle State", _vehicleState, color: _vehicleStateColor),
                      _infoTile(Icons.access_time, "Last Updated", _lastUpdated),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.center,
                        child: ElevatedButton.icon(
                          onPressed: _fetchDailyUsage,
                          icon: const Icon(Icons.refresh),
                          label: const Text("Refresh Now"),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Builder(
        builder: (BuildContext context) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildEnhancedNavItem(
                  index: 0,
                  icon: Icons.home_rounded,
                  isSelected: _selectedIndex == 0,
                  onTap: () => _onItemTapped(0, context),
                ),
                _buildEnhancedNavItem(
                  index: 1,
                  icon: Icons.notifications_rounded,
                  isSelected: _selectedIndex == 1,
                  onTap: () => _onItemTapped(1, context),
                ),
                _buildEnhancedNavItem(
                  index: 2,
                  icon: Icons.group_rounded,
                  isSelected: _selectedIndex == 2,
                  onTap: () => _onItemTapped(2, context),
                ),
                _buildEnhancedNavItem(
                  index: 3,
                  icon: Icons.warning_rounded,
                  isSelected: _selectedIndex == 3,
                  onTap: () => _onItemTapped(3, context),
                ),
                _buildEnhancedNavItem(
                  index: 4,
                  icon: Icons.person_rounded,
                  isSelected: _selectedIndex == 4,
                  onTap: () => _onItemTapped(4, context),
                  isTransparent: true,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEnhancedNavItem({
    required int index,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    bool isTransparent = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: isTransparent
          ? Icon(
        icon,
        color: isSelected
            ? Theme.of(context).bottomNavigationBarTheme.selectedItemColor
            : Theme.of(context).bottomNavigationBarTheme.unselectedItemColor,
        size: 22,
      )
          : AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).bottomNavigationBarTheme.selectedItemColor!.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: Theme.of(context).bottomNavigationBarTheme.selectedItemColor!.withOpacity(0.2),
              blurRadius: 6,
              spreadRadius: 0,
              offset: const Offset(0, 2),
            ),
          ]
              : [],
        ),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).bottomNavigationBarTheme.selectedItemColor
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
              BoxShadow(
                color: Theme.of(context).bottomNavigationBarTheme.selectedItemColor!.withOpacity(0.3),
                blurRadius: 4,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
            ]
                : [],
          ),
          child: Icon(
            icon,
            color: isSelected
                ? Theme.of(context).colorScheme.onSecondary
                : Theme.of(context).bottomNavigationBarTheme.unselectedItemColor,
            size: 22,
          ),
        ),
      ),
    );
  }
}