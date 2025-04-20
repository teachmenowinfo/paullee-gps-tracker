import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:exif/exif.dart';
import 'package:intl/intl.dart';

class GeotaggedPhoto {
  final String id;
  final String path;
  final LatLng location;
  final DateTime timestamp;
  final String? description;

  GeotaggedPhoto({
    required this.id,
    required this.path,
    required this.location,
    required this.timestamp,
    this.description,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'timestamp': timestamp.toIso8601String(),
      'description': description,
    };
  }

  // Create from JSON for loading from storage
  factory GeotaggedPhoto.fromJson(Map<String, dynamic> json) {
    return GeotaggedPhoto(
      id: json['id'],
      path: json['path'],
      location: LatLng(json['latitude'], json['longitude']),
      timestamp: DateTime.parse(json['timestamp']),
      description: json['description'],
    );
  }
}

class PhotoGeotaggingService {
  static final _picker = ImagePicker();

  // Take a new photo with the device camera
  static Future<GeotaggedPhoto?> takePhoto(LatLng currentLocation) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 85,
      );

      if (image == null) return null;

      // Generate a unique ID using timestamp
      final timestamp = DateTime.now();
      final id = 'photo_${timestamp.millisecondsSinceEpoch}';
      
      // Save the image to a permanent location
      final directory = await getApplicationDocumentsDirectory();
      final savedPath = '${directory.path}/$id.jpg';
      
      // Copy the image to our app's storage
      final File imageFile = File(image.path);
      await imageFile.copy(savedPath);
      
      return GeotaggedPhoto(
        id: id,
        path: savedPath,
        location: currentLocation,
        timestamp: timestamp,
      );
    } catch (e) {
      debugPrint('Error taking photo: $e');
      return null;
    }
  }

  // Choose an existing photo from gallery
  static Future<GeotaggedPhoto?> pickPhoto(LatLng currentLocation) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 85,
      );

      if (image == null) return null;

      // Check if the image already has geotags
      final File imageFile = File(image.path);
      final data = await readExifFromFile(imageFile);
      
      LatLng photoLocation = currentLocation;
      DateTime photoTimestamp = DateTime.now();
      
      // Try to extract GPS coordinates from EXIF if available
      if (data.containsKey('GPS GPSLatitude') && data.containsKey('GPS GPSLongitude')) {
        try {
          final latTag = data['GPS GPSLatitude']!;
          final longTag = data['GPS GPSLongitude']!;
          
          // This is a simplified example - real implementation would need to handle different EXIF formats
          // and GPS reference (N/S, E/W)
          final lat = _parseExifGpsCoordinate(latTag.printable);
          final lng = _parseExifGpsCoordinate(longTag.printable);
          
          photoLocation = LatLng(lat, lng);
        } catch (e) {
          debugPrint('Error parsing EXIF GPS data: $e');
        }
      }
      
      // Try to extract timestamp if available
      if (data.containsKey('EXIF DateTimeOriginal')) {
        try {
          final dateTimeStr = data['EXIF DateTimeOriginal']!.printable;
          photoTimestamp = DateFormat('yyyy:MM:dd HH:mm:ss').parse(dateTimeStr);
        } catch (e) {
          debugPrint('Error parsing EXIF timestamp: $e');
        }
      }
      
      // Generate a unique ID using timestamp
      final id = 'photo_${photoTimestamp.millisecondsSinceEpoch}';
      
      // Save the image to a permanent location
      final directory = await getApplicationDocumentsDirectory();
      final savedPath = '${directory.path}/$id.jpg';
      
      // Copy the image to our app's storage
      await imageFile.copy(savedPath);
      
      return GeotaggedPhoto(
        id: id,
        path: savedPath,
        location: photoLocation,
        timestamp: photoTimestamp,
      );
    } catch (e) {
      debugPrint('Error picking photo: $e');
      return null;
    }
  }
  
  // Helper method to parse EXIF GPS coordinates
  static double _parseExifGpsCoordinate(String coordStr) {
    // This is a simplified version and may not work for all formats
    // EXIF coordinates are typically in degrees, minutes, seconds format
    final parts = coordStr.split(', ');
    if (parts.length == 3) {
      final degrees = double.parse(parts[0]);
      final minutes = double.parse(parts[1]) / 60;
      final seconds = double.parse(parts[2]) / 3600;
      return degrees + minutes + seconds;
    }
    throw Exception('Unexpected GPS coordinate format: $coordStr');
  }
}

class PhotoGalleryScreen extends StatelessWidget {
  final List<GeotaggedPhoto> photos;
  final Function(GeotaggedPhoto) onPhotoSelected;
  
  const PhotoGalleryScreen({
    Key? key,
    required this.photos,
    required this.onPhotoSelected,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geotagged Photos'),
      ),
      body: photos.isEmpty
          ? const Center(child: Text('No geotagged photos yet'))
          : GridView.builder(
              padding: const EdgeInsets.all(8.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8.0,
                mainAxisSpacing: 8.0,
              ),
              itemCount: photos.length,
              itemBuilder: (context, index) {
                final photo = photos[index];
                return GestureDetector(
                  onTap: () => onPhotoSelected(photo),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(photo.path),
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          color: Colors.black54,
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Text(
                            DateFormat('MM/dd/yyyy').format(photo.timestamp),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pop(context),
        child: const Icon(Icons.map),
        tooltip: 'Back to Map',
      ),
    );
  }
} 