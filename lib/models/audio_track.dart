import 'package:latlong2/latlong.dart';

class LocationPoint {
  final String id;
  final LatLng position;
  final String? locationName;
  final double radius;  // Radius in meters to trigger this audio
  
  const LocationPoint({
    required this.id,
    required this.position,
    this.locationName,
    this.radius = 100.0,
  });
  
  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'locationName': locationName,
      'radius': radius,
    };
  }
  
  // Create from JSON
  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    return LocationPoint(
      id: json['id'],
      position: LatLng(json['latitude'], json['longitude']),
      locationName: json['locationName'],
      radius: json['radius'] ?? 100.0,
    );
  }
}

class LocationAudioTrack {
  final String id;
  final String title;
  final String artist;
  final String? albumArt;
  final String audioUri;
  final List<LocationPoint> locations;  // Multiple locations can trigger this track
  final DateTime associatedAt;

  const LocationAudioTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.albumArt,
    required this.audioUri,
    required this.locations,
    required this.associatedAt,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'albumArt': albumArt,
      'audioUri': audioUri,
      'locations': locations.map((loc) => loc.toJson()).toList(),
      'associatedAt': associatedAt.toIso8601String(),
    };
  }

  // Create from JSON
  factory LocationAudioTrack.fromJson(Map<String, dynamic> json) {
    final List<dynamic> locationsJson = json['locations'] ?? [];
    
    return LocationAudioTrack(
      id: json['id'],
      title: json['title'],
      artist: json['artist'],
      albumArt: json['albumArt'],
      audioUri: json['audioUri'],
      locations: locationsJson.map((locJson) => LocationPoint.fromJson(locJson)).toList(),
      associatedAt: DateTime.parse(json['associatedAt']),
    );
  }
  
  // Create a copy with modified attributes
  LocationAudioTrack copyWith({
    String? id,
    String? title,
    String? artist,
    String? albumArt,
    String? audioUri,
    List<LocationPoint>? locations,
    DateTime? associatedAt,
  }) {
    return LocationAudioTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      albumArt: albumArt ?? this.albumArt,
      audioUri: audioUri ?? this.audioUri,
      locations: locations ?? this.locations,
      associatedAt: associatedAt ?? this.associatedAt,
    );
  }
  
  // Add a new location to this track
  LocationAudioTrack addLocation(LocationPoint location) {
    final updatedLocations = List<LocationPoint>.from(locations)..add(location);
    return copyWith(locations: updatedLocations);
  }
  
  // Remove a location from this track
  LocationAudioTrack removeLocation(String locationId) {
    final updatedLocations = locations.where((loc) => loc.id != locationId).toList();
    return copyWith(locations: updatedLocations);
  }
  
  // Update a location for this track
  LocationAudioTrack updateLocation(LocationPoint updatedLocation) {
    final updatedLocations = locations.map((loc) => 
      loc.id == updatedLocation.id ? updatedLocation : loc
    ).toList();
    return copyWith(locations: updatedLocations);
  }
} 