import 'package:latlong2/latlong.dart';

class PhotoLocation {
  final String id;
  final String photoPath;
  final LatLng position;
  final DateTime timestamp;
  final String? address;
  final String? description;
  final String? takenBy;

  const PhotoLocation({
    required this.id,
    required this.photoPath,
    required this.position,
    required this.timestamp,
    this.address,
    this.description,
    this.takenBy,
  });

  // To JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'photoPath': photoPath,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': timestamp.toIso8601String(),
      'address': address,
      'description': description,
      'takenBy': takenBy,
    };
  }

  // From JSON for retrieval
  factory PhotoLocation.fromJson(Map<String, dynamic> json) {
    return PhotoLocation(
      id: json['id'],
      photoPath: json['photoPath'],
      position: LatLng(json['latitude'], json['longitude']),
      timestamp: DateTime.parse(json['timestamp']),
      address: json['address'],
      description: json['description'],
      takenBy: json['takenBy'],
    );
  }
} 