import 'package:latlong2/latlong.dart';

class LocationAudioTrack {
  final String id;
  final String title;
  final String artist;
  final String? albumArt;
  final String audioUri;
  final LatLng position;
  final String? locationName;
  final DateTime associatedAt;
  final double radius;  // Radius in meters to trigger this audio

  const LocationAudioTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.albumArt,
    required this.audioUri,
    required this.position,
    this.locationName,
    required this.associatedAt,
    this.radius = 100.0,  // Default radius: 100 meters
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'albumArt': albumArt,
      'audioUri': audioUri,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'locationName': locationName,
      'associatedAt': associatedAt.toIso8601String(),
      'radius': radius,
    };
  }

  // Create from JSON
  factory LocationAudioTrack.fromJson(Map<String, dynamic> json) {
    return LocationAudioTrack(
      id: json['id'],
      title: json['title'],
      artist: json['artist'],
      albumArt: json['albumArt'],
      audioUri: json['audioUri'],
      position: LatLng(json['latitude'], json['longitude']),
      locationName: json['locationName'],
      associatedAt: DateTime.parse(json['associatedAt']),
      radius: json['radius'] ?? 100.0,
    );
  }
} 