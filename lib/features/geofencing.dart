import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geofence_service/geofence_service.dart';
import 'package:latlong2/latlong.dart';

class GeofencingManager {
  static final GeofencingManager _instance = GeofencingManager._internal();
  factory GeofencingManager() => _instance;
  GeofencingManager._internal();

  final _geofenceService = GeofenceService.instance.setup(
    interval: 5000,
    accuracy: 100,
    loiteringDelayMs: 60000,
    statusChangeDelayMs: 10000,
    useActivityRecognition: true,
    allowMockLocations: false,
    printDevLog: false,
    geofenceRadiusSortType: GeofenceRadiusSortType.DESC,
  );

  final _geofenceList = <Geofence>[];
  final _geofenceStreamController = StreamController<GeofenceStatus>.broadcast();
  
  Stream<GeofenceStatus> get geofenceStream => _geofenceStreamController.stream;
  bool _isRunning = false;

  Future<void> startGeofencing() async {
    if (_isRunning) return;
    
    _geofenceService.addGeofenceStatusChangeListener(_onGeofenceStatusChanged);
    
    try {
      await _geofenceService.start(_geofenceList).onError((error, stackTrace) {
        debugPrint('Error starting geofence service: $error');
        return false;
      });
      _isRunning = true;
    } catch (e) {
      debugPrint('Error starting geofence service: $e');
    }
  }

  Future<void> stopGeofencing() async {
    if (!_isRunning) return;
    
    _geofenceService.removeGeofenceStatusChangeListener(_onGeofenceStatusChanged);
    
    try {
      await _geofenceService.stop();
      _isRunning = false;
    } catch (e) {
      debugPrint('Error stopping geofence service: $e');
    }
  }

  void _onGeofenceStatusChanged(Geofence geofence, GeofenceRadius geofenceRadius, GeofenceStatus geofenceStatus, Location location) {
    _geofenceStreamController.add(geofenceStatus);
  }

  void addGeofence({
    required String id, 
    required LatLng position, 
    required double radius,
    required String description,
  }) {
    final geofence = Geofence(
      id: id,
      latitude: position.latitude,
      longitude: position.longitude,
      radius: [
        GeofenceRadius(id: 'radius_$id', length: radius),
      ],
    );
    
    _geofenceList.add(geofence);
    
    // If service is already running, restart it to include the new geofence
    if (_isRunning) {
      stopGeofencing().then((_) => startGeofencing());
    }
  }

  void removeGeofence(String id) {
    _geofenceList.removeWhere((geofence) => geofence.id == id);
    
    // If service is already running, restart it with the updated list
    if (_isRunning) {
      stopGeofencing().then((_) => startGeofencing());
    }
  }

  List<Map<String, dynamic>> getGeofenceList() {
    return _geofenceList.map((geofence) {
      return {
        'id': geofence.id,
        'latitude': geofence.latitude,
        'longitude': geofence.longitude,
        'radius': geofence.radius.first.length,
      };
    }).toList();
  }

  void dispose() {
    _geofenceStreamController.close();
    stopGeofencing();
  }
} 