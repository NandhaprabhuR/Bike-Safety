import 'dart:async';

import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'fmap.dart';
import 'alerts.dart';

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
  bool _isVehicleRunning = false; // Track vehicle running state
  GoogleMapController? _mapController;
  LatLng? _currentPosition;

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
          _currentPosition = const LatLng(12.9716, 77.5946); // Default to Bangalore
        });
        return;
      }

      bool permissionGranted = await _checkAndRequestPermission();
      if (!permissionGranted) {
        setState(() {
          _currentLocation = 'Permission denied';
          _currentPosition = const LatLng(12.9716, 77.5946); // Default to Bangalore
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
          _currentPosition = const LatLng(12.9716, 77.5946); // Default to Bangalore
        });
      });
    } catch (e) {
      setState(() {
        _currentLocation = 'Error: $e';
        _currentPosition = const LatLng(12.9716, 77.5946); // Default to Bangalore
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
        break;
      case 1:
        print('Notifications tapped');
        try {
          Navigator.pushNamed(context, '/alerts').then((_) {
            print('Returned from AlertsPage');
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
        print('Users Registered tapped');
        break;
      case 3: // New Theft Stealing button
        print('Theft Stealing tapped');
        try {
          Navigator.pushNamed(context, '/theft').then((_) {
            print('Returned from TheftPage');
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
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF5F0E5),
              Color(0xFFE5DBC8),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile icon in the top right corner
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Color(0xFFD0C3A6).withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.person_rounded, color: Color(0xFF3E3A36)),
                          onPressed: () {
                            print('Profile icon tapped');
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  // Weather section
                  GestureDetector(
                    onTap: _isLoading ? null : _fetchWeatherData,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Color(0xFFFFFBF3).withOpacity(0.6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Color(0xFFE5DBC8)),
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
                                      color: Color(0xFF3E3A36).withOpacity(0.8),
                                    ),
                                  ),
                                  if (!_isLoading && _weatherCondition.contains('Tap to retry'))
                                    const Padding(
                                      padding: EdgeInsets.only(left: 8.0),
                                      child: Icon(
                                        Icons.refresh,
                                        color: Color(0xFF3E3A36),
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
                                      color: Color(0xFF3E3A36),
                                    ),
                                  ),
                                  const Text(
                                    '°',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF3E3A36),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Feels like $_feelsLike°',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF3E3A36).withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _weatherIcon,
                                color: Color(0xFFD0C3A6),
                                size: 40,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.water_drop,
                                    color: Color(0xFF3E3A36).withOpacity(0.7),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$_humidity%',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF3E3A36).withOpacity(0.7),
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
                  // Vehicle Controls section
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
                    child: Text(
                      'Vehicle Controls',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF3E3A36),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Column(
                    children: [
                      // Start Vehicle / Vehicle Running button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (!_isVehicleRunning) {
                              Navigator.pushNamed(context, '/face').then((result) {
                                print('Returned from FaceRecognitionScreen with result: $result');
                                if (result == true) {
                                  setState(() {
                                    _isVehicleRunning = true;
                                  });
                                }
                              }).catchError((e) {
                                print('Navigation error to FaceRecognitionScreen: $e');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to open face recognition: $e')),
                                );
                              });
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isVehicleRunning ? Colors.red : Color(0xFF7D9D7F),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: Text(
                            _isVehicleRunning ? 'Vehicle Running' : 'Start Vehicle',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Stop Vehicle button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _isVehicleRunning = false;
                            });
                            print('Stop Vehicle button pressed');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF7D9D7F),
                            foregroundColor: Colors.white,
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
                  // Map section
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
                    child: Text(
                      'Current Location',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF3E3A36),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Container(
                    height: 300, // Increased height for better map visibility
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Color(0xFFE5DBC8)),
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
                            infoWindow: InfoWindow(title: 'Current Location', snippet: _currentLocation),
                          ),
                        },
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      // Bottom navigation bar with Home, Alerts, Users Registered, and Theft Stealing
      bottomNavigationBar: Builder(
        builder: (BuildContext context) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            decoration: BoxDecoration(
              color: Color(0xFFFFFBF3),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
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
                  icon: Icons.people_rounded,
                  isSelected: _selectedIndex == 2,
                  onTap: () => _onItemTapped(2, context),
                ),
                _buildEnhancedNavItem(
                  index: 3,
                  icon: Icons.warning_rounded, // Icon for Theft Stealing theme
                  isSelected: _selectedIndex == 3,
                  onTap: () => _onItemTapped(3, context),
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD0C3A6).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: const Color(0xFFD0C3A6).withOpacity(0.2),
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
            color: isSelected ? const Color(0xFFD0C3A6) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
              BoxShadow(
                color: const Color(0xFFD0C3A6).withOpacity(0.3),
                blurRadius: 4,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
            ]
                : [],
          ),
          child: Icon(
            icon,
            color: isSelected ? const Color(0xFF3E3A36) : const Color(0xFF8F8A80),
            size: 22,
          ),
        ),
      ),
    );
  }
}