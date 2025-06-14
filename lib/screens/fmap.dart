import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as location_pkg;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  MapScreenState createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  LatLng? _currentLocation;
  LatLng? _previousLocation;
  double _distanceMoved = 0.0;
  String _vehicleState = 'Unknown';
  List<Map<String, dynamic>> _allShops = [];
  List<Map<String, dynamic>> _filteredShops = [];
  Set<Marker> _shopMarkers = {};
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  final TextEditingController _searchController = TextEditingController();
  final location_pkg.Location _location = location_pkg.Location();
  StreamSubscription<location_pkg.LocationData>? _locationSubscription;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _setupLocation();
    _loadPreviousData();
    _getCurrentLocation();
    _startLocationTracking();
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
    _distanceMoved = distanceMoved ?? 0.0;
    if (isFirstFetch) {
      await prefs.setBool('isFirstFetch', false);
    }
  }

  Future<void> _setupLocation() async {
    try {
      await _location.changeSettings(
        accuracy: location_pkg.LocationAccuracy.high,
        distanceFilter: 1,
        interval: 5000,
      );
    } catch (e) {
      debugPrint('Error configuring location: $e');
    }
  }

  Future<bool> _isGpsEnabled() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        throw Exception('GPS not enabled');
      }
    }
    return true;
  }

  Future<bool> _checkAndRequestPermission() async {
    var permission = await _location.hasPermission();
    if (permission == location_pkg.PermissionStatus.denied) {
      permission = await _location.requestPermission();
      if (permission != location_pkg.PermissionStatus.granted) {
        throw Exception('Location permission denied');
      }
    }
    return true;
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    int retries = 3;
    for (int i = 0; i < retries; i++) {
      try {
        await _isGpsEnabled();
        await _checkAndRequestPermission();

        var locationData = await _location.getLocation().timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception('Timeout'),
        );

        if (locationData.latitude != null && locationData.longitude != null) {
          _currentLocation = LatLng(locationData.latitude!, locationData.longitude!);
          setState(() => _isLoading = false);
          await _updateLocationData(locationData);
          _fetchNearbyShops();
          return; // Success, exit the loop
        } else {
          throw Exception('Null coordinates');
        }
      } catch (e) {
        print('Attempt ${i + 1} failed to fetch location: $e');
        if (i == retries - 1) {
          setState(() {
            _isLoading = false;
            _hasError = true;
            _errorMessage = 'Location Error: $e';
            _currentLocation = null; // No fallback, as per requirement
          });
          _fetchNearbyShops();
        }
        await Future.delayed(const Duration(seconds: 2)); // Wait before retrying
      }
    }
  }

  void _startLocationTracking() {
    _locationSubscription = _location.onLocationChanged.listen((locationData) async {
      if (locationData.latitude != null && locationData.longitude != null) {
        _currentLocation = LatLng(locationData.latitude!, locationData.longitude!);
        await _updateLocationData(locationData);
        _fetchNearbyShops();
        _mapController?.animateCamera(CameraUpdate.newLatLng(_currentLocation!));
      }
    });
  }

  Future<void> _updateLocationData(location_pkg.LocationData locationData) async {
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
          math.cos(lat1) * math.cos(lat2) *
              math.sin(dLon / 2) * math.sin(dLon / 2);
      double c = 2 * math.asin(math.sqrt(a));
      double distanceInKm = earthRadius * c;

      _distanceMoved += distanceInKm;

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
    await prefs.setDouble('distanceMoved', _distanceMoved);
    await prefs.setString('lastUpdated', now.toIso8601String());
    await prefs.setString('lastLocation', '${locationData.latitude},${locationData.longitude}');
    await prefs.setString('vehicleState', _vehicleState);
    print('Updated SharedPreferences with lastLocation: ${locationData.latitude},${locationData.longitude}');
  }

  Future<String> _reverseGeocode(double lat, double lon) async {
    final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Reverse geocoding result: ${data['display_name']}');
        return data['display_name'] ?? 'Unknown';
      } else {
        print('Reverse geocoding failed with status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error reverse geocoding: $e');
    }
    return 'Unknown';
  }

  Future<void> _fetchNearbyShops() async {
    if (_currentLocation == null) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final query = """
      [out:json];
      node(around:5000,${_currentLocation!.latitude},${_currentLocation!.longitude})
      ["shop"~"butcher|fishmonger"];
      out;
    """;

    try {
      final response = await http.post(
        Uri.parse("https://overpass-api.de/api/interpreter"),
        body: {"data": query},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<Map<String, dynamic>> shops = [];

        for (var e in data['elements']) {
          double lat = e['lat'];
          double lon = e['lon'];
          String name = (e['tags']?['name']) ?? "Meat/Fish Shop";

          shops.add({
            "name": name,
            "location": LatLng(lat, lon),
            "rating": (3 + (2 * (lat % 1))).toStringAsFixed(1),
            "image": "https://source.unsplash.com/300x200/?meat,shop",
          });
        }

        setState(() {
          _allShops = shops;
          _filteredShops = shops;
          _updateMarkers();
        });
      } else {
        setState(() {
          _hasError = true;
          _errorMessage = 'Fetch failed: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Error fetching shops: $e';
      });
    } finally {
      _isLoading = false;
    }
  }

  void _filterShops(String query) {
    setState(() {
      _filteredShops = _allShops
          .where((s) => s['name'].toLowerCase().contains(query.toLowerCase()))
          .toList();
      _updateMarkers();
    });
  }

  void _updateMarkers() {
    final markers = <Marker>{};

    for (var shop in _filteredShops) {
      markers.add(Marker(
        markerId: MarkerId(shop["name"]),
        position: shop["location"],
        infoWindow: InfoWindow(
          title: shop["name"],
          snippet: "Rating: ${shop["rating"]}",
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ));
    }

    if (_currentLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId("current_location"),
        position: _currentLocation!,
        infoWindow: const InfoWindow(title: "Your Location"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }

    _shopMarkers = markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _currentLocation != null
              ? GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentLocation!,
              zoom: 15.0,
            ),
            markers: _shopMarkers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onMapCreated: (controller) => _mapController = controller,
          )
              : const Center(child: CircularProgressIndicator()),

          if (_isLoading)
            const Center(child: CircularProgressIndicator()),

          if (_hasError)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _getCurrentLocation,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            top: 40,
            left: 10,
            right: 10,
            child: Row(
              children: [
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.white,
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back, color: Colors.black),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search shops...",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: Icon(Icons.search, color: Colors.grey[600]),
                    ),
                    onChanged: _filterShops,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _locationSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
}