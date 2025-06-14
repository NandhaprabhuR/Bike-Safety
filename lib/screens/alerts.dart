import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'dart:io';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> with SingleTickerProviderStateMixin {
  String _currentPlace = 'Fetching location...';
  String _distanceMoved = 'Calculating...';
  String _vehicleState = 'Checking vehicle state...';
  String _lastUpdated = 'N/A';
  Color _vehicleStateColor = Colors.white;
  bool _isLoading = true;
  bool _dataUnavailable = false;

  String _theftState = 'No theft detected';
  String _theftTimestamp = 'N/A';
  String? _theftPhoto;
  String _theftLocation = 'Unknown location';
  LatLng? _theftLatLng;
  Color _theftStateColor = Colors.grey;
  Set<Marker> _theftMarkers = {};
  String? _theftLocationError;

  late Timer _autoRefreshTimer;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_fadeController);
    _fetchDetailsFromMap();
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 5), (_) => _fetchDetailsFromMap());
  }

  @override
  void dispose() {
    _autoRefreshTimer.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetailsFromMap() async {
    setState(() {
      _isLoading = true;
      _dataUnavailable = false;
      _theftLocationError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      String? currentPlace = prefs.getString('currentPlace');
      double? distanceMoved = prefs.getDouble('distanceMoved');
      String? lastUpdated = prefs.getString('lastUpdated');
      String? vehicleState = prefs.getString('vehicleState');
      bool? isFirstFetch = prefs.getBool('isFirstFetch') ?? true;

      String? theftState = prefs.getString('theftState');
      String? theftTimestamp = prefs.getString('theftTimestamp');
      String? theftPhoto = prefs.getString('theftPhoto');
      String? theftLocation = prefs.getString('theftLocation');
      String? theftLatLng = prefs.getString('theftLatLng');

      print('SharedPreferences values:');
      print('currentPlace: $currentPlace');
      print('distanceMoved: $distanceMoved');
      print('lastUpdated: $lastUpdated');
      print('vehicleState: $vehicleState');
      print('theftState: $theftState');
      print('theftTimestamp: $theftTimestamp');
      print('theftPhoto: $theftPhoto');
      print('theftLocation: $theftLocation');
      print('theftLatLng: $theftLatLng');

      if (currentPlace == null || distanceMoved == null || lastUpdated == null || vehicleState == null) {
        throw Exception("Some vehicle data fields are missing.");
      }

      String formattedLastUpdated = DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(lastUpdated));
      String formattedTheftTimestamp = theftTimestamp != null
          ? DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(theftTimestamp))
          : 'N/A';

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

      bool photoExists = false;
      if (theftPhoto != null) {
        final file = File(theftPhoto);
        photoExists = await file.exists();
        print('Theft photo path: $theftPhoto, exists: $photoExists');
        if (!photoExists) {
          print('Theft photo file does not exist at: $theftPhoto');
          theftPhoto = null;
        }
      }

      LatLng? parsedTheftLatLng;
      if (theftLatLng != null) {
        try {
          List<String> coords = theftLatLng.split(',');
          double lat = double.parse(coords[0]);
          double lon = double.parse(coords[1]);
          if (lat == 0.0 && lon == 0.0) {
            _theftLocationError = 'Theft location coordinates not available';
          } else {
            parsedTheftLatLng = LatLng(lat, lon);
            _theftMarkers = {
              Marker(
                markerId: const MarkerId('theft_location'),
                position: parsedTheftLatLng,
                infoWindow: const InfoWindow(title: 'Theft Location'),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              ),
            };
            print('Theft location loaded: $theftLatLng');
          }
        } catch (e) {
          print('Error parsing theftLatLng: $e');
          _theftLocationError = 'Failed to parse theft location coordinates: $e';
        }
      } else if (theftState != null) {
        _theftLocationError = 'Theft location coordinates not available';
      }

      setState(() {
        _currentPlace = currentPlace;
        _distanceMoved = isFirstFetch ? 'No previous data' : '${distanceMoved.toStringAsFixed(2)} km';
        _vehicleState = vehicleState;
        _lastUpdated = formattedLastUpdated;
        _vehicleStateColor = stateColor;

        _theftState = theftState ?? 'No theft detected';
        _theftTimestamp = formattedTheftTimestamp;
        _theftPhoto = theftPhoto;
        _theftLocation = theftLocation ?? 'Unknown location';
        _theftLatLng = parsedTheftLatLng;
        _theftStateColor = theftState != null ? Colors.red.shade700 : Colors.grey;

        _isLoading = false;
      });

      _fadeController.forward(from: 0.0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vehicle data refreshed"), duration: Duration(seconds: 2)),
      );
    } catch (e) {
      setState(() {
        _dataUnavailable = true;
        _isLoading = false;
        _vehicleState = 'Error: $e';
      });

      Fluttertoast.showToast(
        msg: "Error fetching vehicle data: $e",
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Safety Alerts'),
        centerTitle: true,
      ),
      body: AnimatedOpacity(
        opacity: _isLoading ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 500),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.grey.shade200, blurRadius: 6, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Vehicle Information",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _infoTile(Icons.place, "Current Place", _currentPlace),
                    _infoTile(Icons.map, "Distance Moved", _distanceMoved),
                    _infoTile(Icons.security, "Vehicle State", _vehicleState, color: _vehicleStateColor),
                    _infoTile(Icons.access_time, "Last Updated", _lastUpdated),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.center,
                      child: ElevatedButton.icon(
                        onPressed: _fetchDetailsFromMap,
                        icon: const Icon(Icons.refresh),
                        label: const Text("Refresh Now"),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.grey.shade200, blurRadius: 6, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Theft Information",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _infoTile(Icons.warning, "Theft Alert", _theftState, color: _theftStateColor),
                    _infoTile(Icons.access_time, "Theft Timestamp", _theftTimestamp),
                    if (_theftPhoto != null) ...[
                      const SizedBox(height: 12),
                      const Text(
                        "Theft Photo",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Image.file(
                          File(_theftPhoto!),
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            print('Error loading theft photo: $error');
                            return const Center(child: Text("Photo unavailable"));
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Theft Location Map",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 10),
                        if (_theftLocationError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _theftLocationError!,
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                        SizedBox(
                          height: 200,
                          width: double.infinity,
                          child: _theftLatLng != null
                              ? GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: _theftLatLng!,
                              zoom: 15.0,
                            ),
                            markers: _theftMarkers,
                            myLocationEnabled: false,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                          )
                              : const Center(child: Text("Theft location unavailable")),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String title, String value, {Color? color}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color ?? Colors.blueGrey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(color: color ?? Colors.black)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}