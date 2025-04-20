import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/audio_track.dart';

class AudioLocationService {
  static final AudioLocationService _instance = AudioLocationService._internal();
  factory AudioLocationService() => _instance;
  AudioLocationService._internal();

  // Audio query to access device music
  final OnAudioQuery _audioQuery = OnAudioQuery();
  
  // Audio player for playback
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // Track storage and state
  List<LocationAudioTrack> _locationTracks = [];
  LocationAudioTrack? _currentlyPlayingTrack;
  bool _isMonitoring = false;
  StreamSubscription<Position>? _positionSubscription;
  
  // Radius calculator
  final Distance _distance = const Distance();
  
  // Initialize and load saved tracks
  Future<void> initialize() async {
    await _loadTracks();
    // Request permissions
    await _audioQuery.permissionsStatus();
    await _audioQuery.permissionsRequest();
  }
  
  // Load tracks from shared preferences
  Future<void> _loadTracks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tracksJson = prefs.getString('location_audio_tracks');
      
      if (tracksJson != null) {
        final List<dynamic> decoded = json.decode(tracksJson);
        _locationTracks = decoded
            .map((track) => LocationAudioTrack.fromJson(track))
            .toList();
        debugPrint('Loaded ${_locationTracks.length} location audio tracks');
      }
    } catch (e) {
      debugPrint('Error loading audio tracks: $e');
    }
  }
  
  // Save tracks to shared preferences
  Future<void> _saveTracks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encodedTracks = json.encode(
        _locationTracks.map((track) => track.toJson()).toList(),
      );
      await prefs.setString('location_audio_tracks', encodedTracks);
    } catch (e) {
      debugPrint('Error saving audio tracks: $e');
    }
  }
  
  // Get audio tracks from device
  Future<List<SongModel>> getDeviceAudioTracks() async {
    try {
      // Get all songs from device
      final songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      return songs;
    } catch (e) {
      debugPrint('Error getting device audio tracks: $e');
      return [];
    }
  }
  
  // Add a location audio track
  Future<void> addLocationAudioTrack({
    required SongModel song,
    required LatLng position,
    String? locationName,
    double radius = 100.0,
  }) async {
    // Create a new location point
    final locationPoint = LocationPoint(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      position: position,
      locationName: locationName,
      radius: radius,
    );
    
    // Check if we already have a track with this song
    final existingTrackIndex = _locationTracks.indexWhere(
      (track) => track.audioUri == song.uri
    );
    
    if (existingTrackIndex >= 0) {
      // Add the new location to the existing track
      final updatedTrack = _locationTracks[existingTrackIndex].addLocation(locationPoint);
      _locationTracks[existingTrackIndex] = updatedTrack;
    } else {
      // Create a new track with this location
      final track = LocationAudioTrack(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: song.title,
        artist: song.artist ?? 'Unknown Artist',
        audioUri: song.uri ?? '',
        locations: [locationPoint],
        associatedAt: DateTime.now(),
      );
      
      _locationTracks.add(track);
    }
    
    await _saveTracks();
  }
  
  // Remove a location from a track
  Future<void> removeLocationFromTrack(String trackId, String locationId) async {
    final trackIndex = _locationTracks.indexWhere((track) => track.id == trackId);
    if (trackIndex < 0) return;
    
    final track = _locationTracks[trackIndex];
    final updatedTrack = track.removeLocation(locationId);
    
    // If no locations left, remove the track entirely
    if (updatedTrack.locations.isEmpty) {
      await removeLocationAudioTrack(trackId);
    } else {
      _locationTracks[trackIndex] = updatedTrack;
      await _saveTracks();
    }
    
    // If we're removing the currently playing track's active location, stop playback
    if (_currentlyPlayingTrack?.id == trackId) {
      await stopPlayback();
    }
  }
  
  // Update a location for a track
  Future<void> updateLocationForTrack(
    String trackId, 
    String locationId, 
    LatLng position, 
    String? locationName, 
    double radius
  ) async {
    final trackIndex = _locationTracks.indexWhere((track) => track.id == trackId);
    if (trackIndex < 0) return;
    
    final track = _locationTracks[trackIndex];
    final updatedLocation = LocationPoint(
      id: locationId,
      position: position,
      locationName: locationName,
      radius: radius,
    );
    
    final updatedTrack = track.updateLocation(updatedLocation);
    _locationTracks[trackIndex] = updatedTrack;
    
    await _saveTracks();
  }
  
  // Remove a location audio track
  Future<void> removeLocationAudioTrack(String id) async {
    _locationTracks.removeWhere((track) => track.id == id);
    await _saveTracks();
    
    // If we're removing the currently playing track, stop playback
    if (_currentlyPlayingTrack?.id == id) {
      await stopPlayback();
    }
  }
  
  // Get all location audio tracks
  List<LocationAudioTrack> getLocationAudioTracks() {
    return List.unmodifiable(_locationTracks);
  }
  
  // Start monitoring for location-based audio playback
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    
    // Start listening to position updates
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(_checkForNearbyTracks);
  }
  
  // Stop monitoring
  Future<void> stopMonitoring() async {
    _isMonitoring = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await stopPlayback();
  }
  
  // Check for tracks near the current position
  void _checkForNearbyTracks(Position position) {
    if (_locationTracks.isEmpty) return;
    
    final currentPosition = LatLng(position.latitude, position.longitude);
    
    // Find the closest location point among all tracks
    LocationAudioTrack? closestTrack;
    LocationPoint? closestLocation;
    double closestDistance = double.infinity;
    
    for (final track in _locationTracks) {
      for (final location in track.locations) {
        final distance = _distance.as(
          LengthUnit.Meter,
          currentPosition,
          location.position,
        );
        
        if (distance <= location.radius && distance < closestDistance) {
          closestTrack = track;
          closestLocation = location;
          closestDistance = distance;
        }
      }
    }
    
    // If we found a nearby track and it's different from current
    if (closestTrack != null && 
        (_currentlyPlayingTrack?.id != closestTrack.id)) {
      _playTrack(closestTrack);
    } 
    // If we're not near any track but we're playing something
    else if (closestTrack == null && _currentlyPlayingTrack != null) {
      stopPlayback();
    }
  }
  
  // Play a specific track
  Future<void> _playTrack(LocationAudioTrack track) async {
    try {
      await stopPlayback();
      
      // Set the source and play
      await _audioPlayer.setAudioSource(
        AudioSource.uri(Uri.parse(track.audioUri)),
      );
      await _audioPlayer.play();
      
      _currentlyPlayingTrack = track;
    } catch (e) {
      debugPrint('Error playing track: $e');
    }
  }
  
  // Play a track manually (for testing)
  Future<void> playTrackManually(String trackId) async {
    final track = _locationTracks.firstWhere(
      (t) => t.id == trackId,
      orElse: () => throw Exception('Track not found'),
    );
    
    await _playTrack(track);
  }
  
  // Stop playback
  Future<void> stopPlayback() async {
    try {
      await _audioPlayer.stop();
      _currentlyPlayingTrack = null;
    } catch (e) {
      debugPrint('Error stopping playback: $e');
    }
  }
  
  // Get currently playing track
  LocationAudioTrack? getCurrentlyPlayingTrack() {
    return _currentlyPlayingTrack;
  }
  
  // Check if monitoring is active
  bool isMonitoring() {
    return _isMonitoring;
  }
  
  // Clean up resources
  Future<void> dispose() async {
    await stopMonitoring();
    await _audioPlayer.dispose();
  }
  
  // Add a location to an existing track
  Future<void> addLocationToTrack(String trackId, LocationPoint locationPoint) async {
    final trackIndex = _locationTracks.indexWhere((track) => track.id == trackId);
    if (trackIndex < 0) return;
    
    final track = _locationTracks[trackIndex];
    final updatedTrack = track.addLocation(locationPoint);
    _locationTracks[trackIndex] = updatedTrack;
    
    await _saveTracks();
  }
} 