import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'screens/audio_tracks_screen.dart';
import 'features/feature_manager.dart';
import 'services/audio_service.dart';
import 'models/audio_track.dart' as audio_model;

// TODO: Import Apple's Family Controls framework when approval is granted

Future<void> main() async {
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  // Initialize the feature manager
  final featureManager = FeatureManager();
  await featureManager.initialize();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaulLee GPS Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MapSample(),
    );
  }
}

class LocationPoint {
  final LatLng position;
  final double accuracy;
  final double? heading;
  final DateTime timestamp;
  String? address;
  bool isVisited;

  LocationPoint({
    required this.position, 
    required this.accuracy, 
    this.heading, 
    required this.timestamp,
    this.address,
    this.isVisited = false,
  });

  String get formattedTime => DateFormat('HH:mm:ss').format(timestamp);
  String get formattedDate => DateFormat('yyyy-MM-dd').format(timestamp);
  String get formattedDateTime => DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);
  String get displayAddress => address ?? 'Address unavailable';

  @override
  String toString() {
    return 'Lat: ${position.latitude.toStringAsFixed(6)}, Lng: ${position.longitude.toStringAsFixed(6)}, Accuracy: ${accuracy.toStringAsFixed(1)}m, Time: $formattedTime';
  }
}

class GPSSearchService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org/search';
  
  static Future<List<Map<String, dynamic>>> searchByQuery(String query) async {
    if (query.isEmpty) return [];
    
    final response = await http.get(
      Uri.parse('$_baseUrl?q=$query&format=json&limit=10'),
      headers: {'User-Agent': 'LocationTrackerApp/1.0'},
    );
    
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((item) => item as Map<String, dynamic>).toList();
    } else {
      throw Exception('Failed to search location. Status code: ${response.statusCode}');
    }
  }

  static Future<List<Map<String, dynamic>>> searchNearby(LatLng location, {String type = 'restaurant', int radius = 1000}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl?q=$type&format=json&limit=10&lat=${location.latitude}&lon=${location.longitude}&radius=$radius'),
      headers: {'User-Agent': 'LocationTrackerApp/1.0'},
    );
    
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((item) => item as Map<String, dynamic>).toList();
    } else {
      throw Exception('Failed to search nearby. Status code: ${response.statusCode}');
    }
  }
}

class MapSample extends StatefulWidget {
  const MapSample({Key? key}) : super(key: key);

  @override
  State<MapSample> createState() => MapSampleState();
}

class MapSampleState extends State<MapSample> {
  Position? _currentPosition;
  bool _isLoading = false;
  final MapController _mapController = MapController();
  List<Marker> _markers = [];
  bool _isTracking = false;
  List<LatLng> _trackingPoints = [];
  List<LocationPoint> _locationHistory = [];
  bool _userInteracting = false;
  double _currentZoom = 15.0;
  bool _highPrecisionMode = false;
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  String? _currentAddress;
  
  // GPS settings
  int _gpsUpdateIntervalSeconds = 120; // 2 minutes
  int _gpsDistanceFilterMeters = 10;
  List<String> _logEntries = [];
  Timer? _trackingReminderTimer;
  
  // Filtering
  DateTime? _startDate;
  DateTime? _endDate;
  String? _addressFilter;
  TextEditingController _addressFilterController = TextEditingController();
  
  // Visited places
  List<LocationPoint> _visitedPlaces = [];
  bool _showVisitedPlaces = false;
  bool _showHistoryTrail = false;
  
  @override
  void initState() {
    super.initState();
    _checkPermission();
    
    // Initialize audio service
    AudioLocationService().initialize().then((_) {
      // Start monitoring if there are saved tracks
      if (AudioLocationService().getLocationAudioTracks().isNotEmpty) {
        AudioLocationService().startMonitoring();
      }
    });
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _addressFilterController.dispose();
    _trackingReminderTimer?.cancel();
    super.dispose();
  }
  
  Future<void> _checkPermission() async {
    setState(() {
      _isLoading = true;
    });

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied')),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permissions are permanently denied')),
      );
      setState(() {
        _isLoading = false;
      });
      return;
    }
    
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 10),
      );
      
      if (_currentPosition != null) {
        _mapController.move(
          LatLng(position.latitude, position.longitude),
          _currentZoom,
        );
      }
      
      // Get the address for this location
      _getAddressFromCoordinates(position.latitude, position.longitude);
      
      final locationPoint = LocationPoint(
        position: LatLng(position.latitude, position.longitude),
        accuracy: position.accuracy,
        heading: position.heading,
        timestamp: DateTime.now(),
      );
      
      setState(() {
        _currentPosition = position;
        _isLoading = false;
        _updateMarkers();
        _locationHistory.add(locationPoint);
        
        // Show accuracy feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS Accuracy: ±${position.accuracy.toStringAsFixed(1)}m'),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: 'Options',
              onPressed: () {
                _showLocationOptionsMenu(locationPoint);
              },
            ),
          ),
        );
      });
    } catch (e) {
      print("Error getting location: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  void _updateMarkers() {
    List<Marker> newMarkers = [];
    
    // Current location marker
    if (_currentPosition != null) {
      newMarkers.add(
        Marker(
          width: 80.0,
          height: 80.0,
          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          child: const Icon(
            Icons.location_on,
            color: Colors.red,
            size: 40.0,
          ),
        ),
      );
    }
    
    // Add markers for visited places
    if (_showVisitedPlaces) {
      for (var place in _visitedPlaces) {
        newMarkers.add(
          Marker(
            width: 60.0,
            height: 60.0,
            point: place.position,
            child: Tooltip(
              message: place.address ?? 'Visited place',
              child: const Icon(
                Icons.star,
                color: Colors.amber,
                size: 30.0,
              ),
            ),
          ),
        );
      }
    }
    
    // Add markers for locations with audio tracks
    final audioService = AudioLocationService();
    final audioTracks = audioService.getLocationAudioTracks();
    
    for (var track in audioTracks) {
      for (var location in track.locations) {
        newMarkers.add(
          Marker(
            width: 60.0,
            height: 60.0,
            point: location.position,
            child: GestureDetector(
              onTap: () => _showAudioTrackInfo(track, location),
              child: Tooltip(
                message: '${track.title} by ${track.artist}',
                child: const Icon(
                  Icons.music_note,
                  color: Colors.blue,
                  size: 30.0,
                ),
              ),
            ),
          ),
        );
      }
    }
    
    setState(() {
      _markers = newMarkers;
    });
  }
  
  void _showAudioTrackInfo(audio_model.LocationAudioTrack track, audio_model.LocationPoint location) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: const Icon(
                    Icons.music_note,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        track.artist,
                        style: const TextStyle(
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Location: ${location.locationName ?? "Unnamed Location"}'),
            Text('Trigger radius: ${location.radius.toStringAsFixed(0)} meters'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    AudioLocationService().playTrackManually(track.id);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play Now'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AudioTracksScreen(
                          initialPosition: location.position,
                          locationName: location.locationName,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  List<Polyline> _buildHistoryPolylines() {
    List<Polyline> polylines = [];
    
    // Add tracking path if tracking
    if (_trackingPoints.length > 1) {
      polylines.add(
        Polyline(
          points: _trackingPoints,
          color: Colors.blue,
          strokeWidth: 4.0,
        ),
      );
    }
    
    // Add chronological history path if enabled
    if (_showHistoryTrail && _locationHistory.length > 1) {
      // Sort by timestamp
      final sortedPoints = List<LocationPoint>.from(_locationHistory);
      sortedPoints.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      // Create polyline from sorted points
      polylines.add(
        Polyline(
          points: sortedPoints.map((p) => p.position).toList(),
          color: Colors.purple,
          strokeWidth: 3.0,
          // Using strokeCap or pattern would be preferred if supported
        ),
      );
    }
    
    return polylines;
  }
  
  void _toggleTracking() {
    setState(() {
      _isTracking = !_isTracking;
      
      if (_isTracking && _currentPosition != null) {
        _trackingPoints.clear();
        _trackingPoints.add(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
        _startTracking();
      } else {
        _stopTracking();
      }
    });
  }
  
  void _startTracking() {
    if (!_isTracking) return;
    
    // Add to log
    _addToLog('Started tracking with interval: ${_formatTimeInterval(_gpsUpdateIntervalSeconds)}, distance filter: ${_gpsDistanceFilterMeters}m');
    
    // Configure location settings based on precision mode and user settings
    final LocationSettings locationSettings = LocationSettings(
      accuracy: _highPrecisionMode 
          ? LocationAccuracy.bestForNavigation 
          : LocationAccuracy.high,
      distanceFilter: _highPrecisionMode ? 3 : _gpsDistanceFilterMeters, // Use custom distance filter
      timeLimit: Duration(seconds: _gpsUpdateIntervalSeconds), // Use custom time interval
    );
    
    Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      if (!_isTracking) return;
      
      // Periodically update the address (not on every position update)
      if (_locationHistory.isEmpty || 
          DateTime.now().difference(_locationHistory.last.timestamp).inSeconds > 30) {
        _getAddressFromCoordinates(position.latitude, position.longitude);
      }
      
      final locationPoint = LocationPoint(
        position: LatLng(position.latitude, position.longitude),
        accuracy: position.accuracy,
        heading: position.heading,
        timestamp: DateTime.now(),
        address: _currentAddress,
      );
      
      // Add to log
      _addToLog('New location: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}, accuracy: ${position.accuracy.toStringAsFixed(1)}m');
      
      setState(() {
        _currentPosition = position;
        _trackingPoints.add(LatLng(position.latitude, position.longitude));
        _locationHistory.add(locationPoint);
        _updateMarkers();
        
        if (_currentPosition != null && !_userInteracting) {
          _mapController.move(
            LatLng(position.latitude, position.longitude),
            _currentZoom,
          );
        }
      });
    });
    
    // Set up hourly reminder
    _trackingReminderTimer?.cancel();
    _trackingReminderTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      if (!_isTracking) {
        timer.cancel();
        return;
      }
      _showTrackingReminderDialog();
    });
  }
  
  void _addToLog(String entry) {
    setState(() {
      _logEntries.add('${DateFormat('HH:mm:ss').format(DateTime.now())} - $entry');
      // Keep log at a reasonable size
      if (_logEntries.length > 100) {
        _logEntries.removeAt(0);
      }
    });
  }
  
  String _formatTimeInterval(int seconds) {
    if (seconds >= 86400 && seconds % 86400 == 0) {
      final days = seconds ~/ 86400;
      return '$days ${days == 1 ? 'day' : 'days'}';
    } else if (seconds >= 3600 && seconds % 3600 == 0) {
      final hours = seconds ~/ 3600;
      return '$hours ${hours == 1 ? 'hour' : 'hours'}';
    } else if (seconds >= 60 && seconds % 60 == 0) {
      final minutes = seconds ~/ 60;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
    } else {
      return '$seconds ${seconds == 1 ? 'second' : 'seconds'}';
    }
  }
  
  void _toggleHighPrecisionMode() {
    setState(() {
      _highPrecisionMode = !_highPrecisionMode;
    });
    
    // Restart tracking with new settings if currently tracking
    if (_isTracking) {
      _stopTracking();
      _startTracking();
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_highPrecisionMode ? "High" : "Standard"} precision mode enabled'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  void _stopTracking() {
    setState(() {
      _isTracking = false;
    });
    
    _trackingReminderTimer?.cancel();
    _trackingReminderTimer = null;
    
    _addToLog('Tracking stopped');
  }
  
  void _showTrackingReminderDialog() {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Tracking Active'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Location tracking has been running for 1 hour.'),
            const SizedBox(height: 8),
            Text(
              'Started: ${DateFormat('hh:mm a').format(DateTime.now().subtract(const Duration(hours: 1)))}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Do you want to continue tracking?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _stopTracking();
            },
            child: const Text('Stop Tracking'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Tracking continues
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
  
  void _zoomIn() {
    _currentZoom = _mapController.camera.zoom + 1;
    if (_currentZoom > 18.0) _currentZoom = 18.0;
    
    _userInteracting = true;
    _mapController.move(_mapController.camera.center, _currentZoom);
    
    // Resume tracking after zoom operation
    Future.delayed(const Duration(seconds: 1), () {
      if (_isTracking) {
        setState(() {
          _userInteracting = false;
        });
      }
    });
  }
  
  void _zoomOut() {
    _currentZoom = _mapController.camera.zoom - 1;
    if (_currentZoom < 4.0) _currentZoom = 4.0;
    
    _userInteracting = true;
    _mapController.move(_mapController.camera.center, _currentZoom);
    
    // Resume tracking after zoom operation
    Future.delayed(const Duration(seconds: 1), () {
      if (_isTracking) {
        setState(() {
          _userInteracting = false;
        });
      }
    });
  }
  
  void _showHistoryDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            List<LocationPoint> filteredHistory = _filterHistory();
            
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Location History',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.filter_alt),
                                label: const Text('Filter'),
                                onPressed: () {
                                  _showFilterDialog();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          if (_startDate != null && _endDate != null)
                            Expanded(
                              child: Chip(
                                label: Text(
                                  'Filter: ${DateFormat('MM/dd').format(_startDate!)} - ${DateFormat('MM/dd').format(_endDate!)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onDeleted: () {
                                  setState(() {
                                    _startDate = null;
                                    _endDate = null;
                                  });
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: filteredHistory.isEmpty
                          ? const Center(child: Text('No location history found'))
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: filteredHistory.length,
                              itemBuilder: (context, index) {
                                final point = filteredHistory[filteredHistory.length - 1 - index];
                                return ListTile(
                                  leading: const Icon(Icons.location_on),
                                  title: Text(
                                    'Lat: ${point.position.latitude.toStringAsFixed(6)}, Lng: ${point.position.longitude.toStringAsFixed(6)}',
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Accuracy: ±${point.accuracy.toStringAsFixed(1)}m'),
                                      Text(point.formattedDateTime),
                                      if (point.address != null)
                                        Text(
                                          point.address!,
                                          style: const TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: Colors.blue,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          point.isVisited ? Icons.star : Icons.star_border,
                                          color: point.isVisited ? Colors.amber : Colors.grey,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            point.isVisited = !point.isVisited;
                                            if (point.isVisited) {
                                              if (!_visitedPlaces.contains(point)) {
                                                _visitedPlaces.add(point);
                                              }
                                            } else {
                                              _visitedPlaces.remove(point);
                                            }
                                            _updateMarkers();
                                          });
                                        },
                                        tooltip: 'Mark as visited',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.map),
                                        onPressed: () {
                                          // Go to this location on map
                                          _mapController.move(point.position, _currentZoom);
                                          Navigator.pop(context);
                                        },
                                        tooltip: 'Show on map',
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  List<LocationPoint> _filterHistory() {
    List<LocationPoint> filtered = _locationHistory;
    
    // Filter by date if specified
    if (_startDate != null && _endDate != null) {
      filtered = filtered.where((point) {
        return point.timestamp.isAfter(_startDate!) && 
               point.timestamp.isBefore(_endDate!.add(const Duration(days: 1)));
      }).toList();
    }
    
    // Filter by address if specified
    if (_addressFilter != null && _addressFilter!.isNotEmpty) {
      filtered = filtered.where((point) {
        return point.address != null && 
               point.address!.toLowerCase().contains(_addressFilter!.toLowerCase());
      }).toList();
    }
    
    return filtered;
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        DateTime? startDate = _startDate ?? DateTime.now().subtract(const Duration(days: 1));
        DateTime? endDate = _endDate ?? DateTime.now();
        String addressFilter = _addressFilter ?? '';
        
        return AlertDialog(
          title: const Text('Filter Location History'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('From: '),
                  TextButton(
                    child: Text(DateFormat('yyyy-MM-dd').format(startDate)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: startDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        startDate = picked;
                      }
                    },
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('To: '),
                  TextButton(
                    child: Text(DateFormat('yyyy-MM-dd').format(endDate)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        endDate = picked;
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: TextEditingController(text: addressFilter),
                decoration: const InputDecoration(
                  labelText: 'Address contains',
                  hintText: 'Filter by address',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  addressFilter = value;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            TextButton(
              child: const Text('Apply'),
              onPressed: () {
                setState(() {
                  _startDate = startDate;
                  _endDate = endDate;
                  _addressFilter = addressFilter.isEmpty ? null : addressFilter;
                });
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _openNativeMaps() async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No location available')),
      );
      return;
    }
    
    final url = 'https://maps.apple.com/?ll=${_currentPosition!.latitude},${_currentPosition!.longitude}';
    final uri = Uri.parse(url);
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot open Maps app')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening Maps: $e')),
      );
    }
  }

  Future<String?> _getAddressFromCoordinates(double latitude, double longitude) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
      
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address = '';
        
        if (place.street != null && place.street!.isNotEmpty) {
          address += place.street!;
        }
        
        if (place.locality != null && place.locality!.isNotEmpty) {
          if (address.isNotEmpty) address += ', ';
          address += place.locality!;
        }
        
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
          if (address.isNotEmpty) address += ', ';
          address += place.administrativeArea!;
        }
        
        if (place.postalCode != null && place.postalCode!.isNotEmpty) {
          if (address.isNotEmpty) address += ' ';
          address += place.postalCode!;
        }
        
        if (address.isNotEmpty) {
          setState(() {
            _currentAddress = address;
          });
          return address;
        }
      }
    } catch (e) {
      debugPrint('Error getting address: $e');
    }
    
    return null;
  }
  
  Future<void> _searchLocations(String query) async {
    if (query.isEmpty) return;
    
    setState(() {
      _isSearching = true;
    });
    
    try {
      final results = await GPSSearchService.searchByQuery(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
      
      _showSearchResultsDialog();
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching: $e')),
      );
    }
  }
  
  Future<void> _findNearbyPlaces(String type) async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current location is not available')),
      );
      return;
    }
    
    setState(() {
      _isSearching = true;
    });
    
    try {
      final location = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      final results = await GPSSearchService.searchNearby(location, type: type);
      
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
      
      _showSearchResultsDialog();
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error finding nearby places: $e')),
      );
    }
  }
  
  void _showSearchResultsDialog() {
    if (_searchResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No results found')),
      );
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Search Results'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final result = _searchResults[index];
                return ListTile(
                  title: Text(result['display_name'] ?? 'Unknown'),
                  subtitle: Text('${result['lat']}, ${result['lon']}'),
                  onTap: () {
                    Navigator.pop(context);
                    _goToSearchResult(result);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
  
  void _goToSearchResult(Map<String, dynamic> result) {
    try {
      final lat = double.parse(result['lat']);
      final lon = double.parse(result['lon']);
      final latLng = LatLng(lat, lon);
      
      // Add marker for the search result
      setState(() {
        _markers.add(
          Marker(
            width: 80.0,
            height: 80.0,
            point: latLng,
            child: const Icon(
              Icons.place,
              color: Colors.purple,
              size: 40.0,
            ),
          ),
        );
      });
      
      // Move map to the location
      _mapController.move(latLng, 16.0);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error navigating to location: $e')),
      );
    }
  }

  void _showAISearchDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('AI-Powered Search'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Enter location or search term',
                  hintText: 'e.g., Eiffel Tower or coffee shop',
                ),
              ),
              const SizedBox(height: 16),
              const Text('Or find nearby:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildCategoryChip('Restaurants', 'restaurant'),
                  _buildCategoryChip('Hotels', 'hotel'),
                  _buildCategoryChip('Cafés', 'cafe'),
                  _buildCategoryChip('Shops', 'shop'),
                  _buildCategoryChip('ATMs', 'atm'),
                  _buildCategoryChip('Gas', 'gas'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _searchLocations(_searchController.text);
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildCategoryChip(String label, String type) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        Navigator.pop(context);
        _findNearbyPlaces(type);
      },
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _showAISearchDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentAddress ?? 'Search places',
                        style: TextStyle(
                          color: _currentAddress != null 
                              ? Colors.black87 
                              : Colors.black54,
                          overflow: TextOverflow.ellipsis,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showVisitedPlacesDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Visited Places'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: _visitedPlaces.isEmpty
                ? const Center(child: Text('No visited places yet'))
                : ListView.builder(
                    itemCount: _visitedPlaces.length,
                    itemBuilder: (context, index) {
                      final place = _visitedPlaces[index];
                      return ListTile(
                        leading: const Icon(Icons.star, color: Colors.amber),
                        title: Text(place.address ?? 'Unknown location'),
                        subtitle: Text(
                          '${place.position.latitude.toStringAsFixed(6)}, ${place.position.longitude.toStringAsFixed(6)}\n${place.formattedDateTime}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.map),
                          onPressed: () {
                            Navigator.pop(context);
                            _mapController.move(place.position, _currentZoom);
                          },
                        ),
                        onLongPress: () {
                          showDialog(
                            context: context,
                            builder: (context) {
                              return AlertDialog(
                                title: const Text('Remove from visited places?'),
                                content: const Text('This place will no longer be marked as visited.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        place.isVisited = false;
                                        _visitedPlaces.remove(place);
                                        _updateMarkers();
                                      });
                                      Navigator.pop(context); // Close confirmation dialog
                                      Navigator.pop(context); // Close visited places dialog
                                      
                                      // Show again with updated list
                                      Future.delayed(Duration.zero, () {
                                        if (_visitedPlaces.isNotEmpty) {
                                          _showVisitedPlacesDialog();
                                        }
                                      });
                                    },
                                    child: const Text('Remove'),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            if (_visitedPlaces.isNotEmpty && _showHistoryTrail)
              TextButton(
                onPressed: () {
                  // Create a polyline connecting all visited places chronologically
                  setState(() {
                    final sortedVisits = List<LocationPoint>.from(_visitedPlaces);
                    sortedVisits.sort((a, b) => a.timestamp.compareTo(b.timestamp));
                    
                    // Find bounding box to adjust view
                    if (sortedVisits.isNotEmpty) {
                      final points = sortedVisits.map((p) => p.position).toList();
                      
                      // Zoom to fit all visited places
                      if (points.length > 1) {
                        _mapController.fitCamera(
                          CameraFit.bounds(
                            bounds: LatLngBounds.fromPoints(points),
                            padding: const EdgeInsets.all(50.0),
                          ),
                        );
                      } else if (points.length == 1) {
                        _mapController.move(points.first, _currentZoom);
                      }
                    }
                  });
                  Navigator.pop(context);
                },
                child: const Text('Show All on Map'),
              ),
          ],
        );
      },
    );
  }

  void _openSettings() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings feature is temporarily unavailable')),
    );
  }
  
  void _openAIAssistant() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI Assistant feature is temporarily unavailable')),
    );
  }

  void _showFeaturesMenu() {
    debugPrint('Opening Advanced Features menu');
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final featureManager = FeatureManager();
        debugPrint('Available features - Audio Tracks: ${featureManager.audioTracksAvailable}');
        
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Advanced Features'),
              subtitle: const Text('Access additional tools and capabilities'),
              leading: const Icon(Icons.apps),
              onTap: null,
              enabled: false,
            ),
            const Divider(),
            if (featureManager.geofencingAvailable)
              ListTile(
                title: const Text('Geofencing'),
                subtitle: const Text('Set up location-based alerts'),
                leading: const Icon(Icons.circle_notifications),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Geofencing feature is coming soon')),
                  );
                  // Add implementation when the package is available
                },
              ),
            if (featureManager.exportImportAvailable)
              ListTile(
                title: const Text('Export/Import'),
                subtitle: const Text('Save and load location data'),
                leading: const Icon(Icons.import_export),
                onTap: () {
                  Navigator.pop(context);
                  _showExportImportDialog();
                },
              ),
            if (featureManager.mapStylesAvailable)
              ListTile(
                title: const Text('Map Styles'),
                subtitle: const Text('Change map appearance'),
                leading: const Icon(Icons.map),
                onTap: () {
                  Navigator.pop(context);
                  _showMapStylesDialog();
                },
              ),
            if (featureManager.locationSharingAvailable)
              ListTile(
                title: const Text('Share Location'),
                subtitle: const Text('Send your location to others'),
                leading: const Icon(Icons.share_location),
                onTap: () {
                  Navigator.pop(context);
                  _shareCurrentLocation();
                },
              ),
            if (featureManager.weatherAvailable)
              ListTile(
                title: const Text('Weather'),
                subtitle: const Text('Check weather for this location'),
                leading: const Icon(Icons.cloud),
                onTap: () {
                  Navigator.pop(context);
                  _showWeatherInfo();
                },
              ),
            if (featureManager.photoGeotaggingAvailable)
              ListTile(
                title: const Text('Geotagged Photos'),
                subtitle: const Text('Take location-tagged photos'),
                leading: const Icon(Icons.photo_camera),
                onTap: () {
                  Navigator.pop(context);
                  _showPhotoOptions();
                },
              ),
            if (featureManager.voiceCommandAvailable)
              ListTile(
                title: const Text('Voice Commands'),
                subtitle: const Text('Control app with voice'),
                leading: const Icon(Icons.mic),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Voice commands feature is coming soon')),
                  );
                  // Add implementation when the package is available
                },
              ),
            if (featureManager.audioTracksAvailable)
              ListTile(
                title: const Text('Audio Tracks'),
                subtitle: const Text('Manage location-based audio tracks'),
                leading: const Icon(Icons.music_note),
                onTap: () {
                  Navigator.pop(context);
                  _showAudioTracksDialog();
                },
              ),
          ],
        );
      },
    );
  }
  
  void _showExportImportDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Export/Import Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Export as GPX'),
                leading: const Icon(Icons.upload),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Export as GPX feature is coming soon')),
                  );
                },
              ),
              ListTile(
                title: const Text('Export as JSON'),
                leading: const Icon(Icons.upload_file),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Export as JSON feature is coming soon')),
                  );
                },
              ),
              ListTile(
                title: const Text('Import from file'),
                leading: const Icon(Icons.download),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Import from file feature is coming soon')),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
  
  void _showMapStylesDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final featureManager = FeatureManager();
        
        return AlertDialog(
          title: const Text('Map Styles'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final style in featureManager.mapStyles.entries)
                ListTile(
                  title: Text(style.value),
                  leading: Radio<String>(
                    value: style.key,
                    groupValue: featureManager.getMapStyle(),
                    onChanged: (value) {
                      if (value != null) {
                        featureManager.setMapStyle(value);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Changed map style to ${style.value}')),
                        );
                      }
                    },
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
  
  void _shareCurrentLocation() {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No location available to share')),
      );
      return;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Location sharing feature is coming soon')),
    );
  }
  
  void _showWeatherInfo() {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No location available to check weather')),
      );
      return;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Weather information feature is coming soon')),
    );
  }
  
  void _showPhotoOptions() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Geotagged Photos'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Take Photo'),
                leading: const Icon(Icons.camera),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Take geotagged photo feature is coming soon')),
                  );
                },
              ),
              ListTile(
                title: const Text('Choose from Gallery'),
                leading: const Icon(Icons.photo_library),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Import photo feature is coming soon')),
                  );
                },
              ),
              ListTile(
                title: const Text('View Photo Map'),
                leading: const Icon(Icons.map),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Photo map feature is coming soon')),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
  
  void _showAudioTracksDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AudioTracksScreen(
          initialPosition: _currentPosition != null 
              ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude) 
              : null,
          locationName: _currentAddress,
        ),
      ),
    );
  }
  
  void _showLocationOptionsMenu(LocationPoint point) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Location Options'),
              subtitle: Text('${point.position.latitude.toStringAsFixed(6)}, ${point.position.longitude.toStringAsFixed(6)}'),
              enabled: false,
            ),
            if (point.address != null)
              ListTile(
                title: Text(point.address!),
                leading: const Icon(Icons.location_on),
                enabled: false,
              ),
            ListTile(
              title: const Text('Mark as Visited Place'),
              leading: const Icon(Icons.star),
              onTap: () {
                setState(() {
                  point.isVisited = true;
                  if (!_visitedPlaces.contains(point)) {
                    _visitedPlaces.add(point);
                  }
                  _updateMarkers();
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Location marked as visited')),
                );
              },
            ),
            ListTile(
              title: const Text('Associate Audio Track'),
              leading: const Icon(Icons.music_note),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AudioTracksScreen(
                      initialPosition: point.position,
                      locationName: point.address,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
  
  void _handleMapLongPress(LatLng point) {
    // Get address for the long-pressed location
    _getAddressFromCoordinates(point.latitude, point.longitude).then((address) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Location Options'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Coordinates: ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}'),
              const SizedBox(height: 8),
              if (address != null) Text('Address: $address'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AudioTracksScreen(
                      initialPosition: point,
                      locationName: address,
                    ),
                  ),
                );
              },
              child: const Text('Associate Music'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                // Add location to visited places
                final locationPoint = LocationPoint(
                  position: point,
                  accuracy: 0,
                  timestamp: DateTime.now(),
                  address: address,
                  isVisited: true,
                );
                setState(() {
                  _visitedPlaces.add(locationPoint);
                  _updateMarkers();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Location marked as visited')),
                );
              },
              child: const Text('Mark as Visited'),
            ),
          ],
        ),
      );
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PaulLee GPS Tracker'),
        backgroundColor: Colors.blue,
        actions: [
          if (_currentPosition != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Center(
                child: Text(
                  '±${_currentPosition!.accuracy.toStringAsFixed(1)}m',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          // Features menu
          IconButton(
            icon: const Icon(Icons.apps),
            onPressed: _showFeaturesMenu,
            tooltip: 'Advanced Features',
          ),
          // AI Assistant button
          IconButton(
            icon: const Icon(Icons.psychology),
            onPressed: _openAIAssistant,
            tooltip: 'AI Assistant',
          ),
          // Settings button
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'Settings',
          ),
          // View options popup menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.visibility),
            tooltip: 'View Options',
            onSelected: (value) {
              setState(() {
                switch (value) {
                  case 'visited':
                    _showVisitedPlaces = !_showVisitedPlaces;
                    break;
                  case 'trail':
                    _showHistoryTrail = !_showHistoryTrail;
                    break;
                }
                _updateMarkers();
              });
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem<String>(
                value: 'visited',
                checked: _showVisitedPlaces,
                child: const Text('Show Visited Places'),
              ),
              CheckedPopupMenuItem<String>(
                value: 'trail',
                checked: _showHistoryTrail,
                child: const Text('Show History Trail'),
              ),
            ],
          ),
          // History button
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _locationHistory.isNotEmpty 
                ? _showHistoryDialog 
                : null,
            tooltip: 'View History',
          ),
          // High precision mode toggle button
          IconButton(
            icon: Icon(
              _highPrecisionMode ? Icons.gps_fixed : Icons.gps_not_fixed,
              color: _highPrecisionMode ? Colors.yellow : Colors.white,
            ),
            onPressed: _toggleHighPrecisionMode,
            tooltip: 'Toggle High Precision',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSearchBar(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isTracking ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _isTracking ? 'Tracking ON' : 'Tracking OFF',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _isTracking ? Colors.green : Colors.red,
                          ),
                        ),
                      ),
                      if (_currentPosition?.heading != null && 
                          _currentPosition!.heading! > 0)
                        Transform.rotate(
                          angle: (_currentPosition!.heading! * math.pi / 180),
                          child: const Icon(Icons.arrow_upward, size: 24),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _currentPosition != null
                              ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                              : const LatLng(37.42796133580664, -122.085749655962),
                          initialZoom: 15.0,
                          minZoom: 4.0,
                          maxZoom: 18.0,
                          onTap: (_, __) {
                            // When user taps, they're interacting with the map
                            _userInteracting = true;
                          },
                          onLongPress: (tapPosition, point) {
                            _handleMapLongPress(point);
                          },
                          onMapEvent: (MapEvent event) {
                            if (event is MapEventDoubleTapZoomStart || 
                                event is MapEventMoveStart) {
                              _userInteracting = true;
                            } else if (event is MapEventMoveEnd) {
                              // Get the current map state
                              _currentZoom = _mapController.camera.zoom;
                              
                              // Reactivate tracking after a short delay
                              Future.delayed(const Duration(seconds: 3), () {
                                if (_isTracking) {
                                  setState(() {
                                    _userInteracting = false;
                                  });
                                }
                              });
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.app',
                          ),
                          MarkerLayer(markers: _markers),
                          if (_trackingPoints.length > 1)
                            PolylineLayer(
                              polylines: _buildHistoryPolylines(),
                            ),
                        ],
                      ),
                      // Zoom controls overlay - moved to left side
                      Positioned(
                        left: 16,
                        bottom: 76,
                        child: Column(
                          children: [
                            FloatingActionButton.small(
                              onPressed: _zoomIn,
                              heroTag: 'zoomIn',
                              child: const Icon(Icons.add),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              onPressed: _zoomOut,
                              heroTag: 'zoomOut',
                              child: const Icon(Icons.remove),
                            ),
                          ],
                        ),
                      ),
                      // Loading indicator
                      if (_isSearching)
                        const Center(
                          child: CircularProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
      persistentFooterButtons: [
        // Track button
        FloatingActionButton(
          onPressed: _toggleTracking,
          backgroundColor: _isTracking ? Colors.red : Colors.green,
          heroTag: 'trackBtn',
          tooltip: _isTracking ? 'Stop tracking' : 'Start tracking',
          child: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
        ),
        const SizedBox(width: 16),
        // Get location button
        FloatingActionButton(
          onPressed: _getCurrentLocation,
          tooltip: 'Get Current Location',
          heroTag: 'locateBtn', 
          child: const Icon(Icons.my_location),
        ),
        const SizedBox(width: 16),
        // AI search button
        FloatingActionButton(
          onPressed: _showAISearchDialog,
          tooltip: 'AI Search',
          heroTag: 'searchBtn',
          backgroundColor: Colors.purple,
          child: const Icon(Icons.search),
        ),
        const SizedBox(width: 16),
        // Open maps button
        FloatingActionButton(
          onPressed: _openNativeMaps,
          tooltip: 'Open in Maps',
          heroTag: 'mapBtn',
          child: const Icon(Icons.map),
        ),
      ],
    );
  }
}
