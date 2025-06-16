import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

class AlertsPage extends StatefulWidget {
  final Map<String, dynamic>? latestAlert;

  const AlertsPage({super.key, this.latestAlert});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _isLoading = false;
  List<Map<String, dynamic>> _allAlerts = [];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_fadeController);

    _loadAllAlerts();
  }

  Future<void> _loadAllAlerts() async {
    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    String? alertsJson = prefs.getString('theftAlerts');
    List<Map<String, dynamic>> formattedAlerts = [];

    // If latestAlert is provided, add it to the list
    if (widget.latestAlert != null) {
      formattedAlerts.add(widget.latestAlert!);
    }

    // Load existing alerts from SharedPreferences
    if (alertsJson != null) {
      try {
        List<dynamic> decoded = jsonDecode(alertsJson);
        List<Map<String, String>> existingAlerts = decoded.map((item) => Map<String, String>.from(item)).toList();

        for (var alert in existingAlerts) {
          // Skip if this alert is already added (e.g., the latestAlert)
          if (widget.latestAlert != null &&
              alert['theftTimestamp'] == widget.latestAlert!['theftTimestamp']) {
            continue;
          }

          String timestamp = alert['theftTimestamp'] ?? DateTime.now().toIso8601String();
          String formattedTimestamp = DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(timestamp));

          String locationCoords = alert['theftLatLng'] ?? '0.0,0.0';
          List<String> coords = locationCoords.split(',');
          double lat = double.parse(coords[0]);
          double lon = double.parse(coords[1]);
          LatLng? parsedLatLng;
          Set<Marker> markers = {};
          String? locationError;
          if (lat != 0.0 && lon != 0.0) {
            parsedLatLng = LatLng(lat, lon);
            markers = {
              Marker(
                markerId: const MarkerId('theft_location'),
                position: parsedLatLng,
                infoWindow: const InfoWindow(title: 'Theft Location'),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              ),
            };
          } else {
            locationError = 'Theft location coordinates not available';
          }

          formattedAlerts.add({
            'theftState': alert['theftState'] ?? 'Theft Detected',
            'theftTimestamp': formattedTimestamp,
            'theftPhoto': alert['theftPhoto']?.isNotEmpty == true ? alert['theftPhoto'] : null,
            'theftLocation': alert['theftLocation'] ?? 'Unknown location',
            'theftLatLng': parsedLatLng,
            'theftMarkers': markers,
            'theftLocationError': locationError,
            'theftStateColor': Colors.red.shade700,
            'priority': int.parse(alert['priority'] ?? '0'),
          });
        }
      } catch (e) {
        print('Error decoding alerts from SharedPreferences: $e');
      }
    }

    // Sort by priority (highest to lowest)
    formattedAlerts.sort((a, b) => (b['priority'] as int).compareTo(a['priority'] as int));

    setState(() {
      _allAlerts = formattedAlerts;
      _isLoading = false;
    });
    print('Loaded all alerts: $_allAlerts');
    _fadeController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _fadeController.dispose();
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color ?? Theme.of(context).iconTheme.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(color: color ?? Theme.of(context).colorScheme.onSurface),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Theft Information",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _infoTile(
            Icons.warning,
            "Theft Alert",
            alert['theftState'] ?? 'Unknown',
            color: alert['theftStateColor'] ?? Colors.red.shade700,
          ),
          _infoTile(
            Icons.access_time,
            "Theft Timestamp",
            alert['theftTimestamp'] ?? 'N/A',
          ),
          if (alert['theftPhoto'] != null && alert['theftPhoto'].isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              "Theft Photo",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.file(
                  File(alert['theftPhoto']),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    print('Error loading theft photo: $error');
                    return const Center(
                      child: Text("Photo unavailable"),
                    );
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            "Theft Location Map",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          if (alert['theftLocationError'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                alert['theftLocationError'],
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                ),
              ),
            ),
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: alert['theftLatLng'] != null
                  ? GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: alert['theftLatLng'],
                  zoom: 15.0,
                ),
                markers: alert['theftMarkers'] ?? <Marker>{},
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
              )
                  : const Center(
                child: Text("Theft location unavailable"),
              ),
            ),
          ),
        ],
      ),
    );
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
                  'Vehicle Safety Alerts',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 24),
                AnimatedOpacity(
                  opacity: _isLoading ? 0.5 : 1.0,
                  duration: const Duration(milliseconds: 500),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: _allAlerts.isEmpty
                        ? Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          "No theft alerts recorded",
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    )
                        : Column(
                      children: _allAlerts.map((alert) => _buildAlertCard(alert)).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}