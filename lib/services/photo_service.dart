import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/photo_location.dart';

class PhotoService {
  static final PhotoService _instance = PhotoService._internal();
  factory PhotoService() => _instance;
  PhotoService._internal();

  final ImagePicker _picker = ImagePicker();
  List<PhotoLocation> _photoLocations = [];
  
  // Initialize and load saved photo locations
  Future<void> initialize() async {
    await _loadPhotoLocations();
  }
  
  // Load photo locations from storage
  Future<void> _loadPhotoLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final photoJson = prefs.getString('photo_locations');
      
      if (photoJson != null) {
        final List<dynamic> photoData = json.decode(photoJson);
        _photoLocations = photoData
            .map((data) => PhotoLocation.fromJson(data))
            .where((photo) {
              // Verify the photo file still exists
              final file = File(photo.photoPath);
              return file.existsSync();
            })
            .toList();
            
        debugPrint('Loaded ${_photoLocations.length} photo locations');
      }
    } catch (e) {
      debugPrint('Error loading photo locations: $e');
    }
  }
  
  // Save photo locations to storage
  Future<void> _savePhotoLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encodedData = json.encode(
        _photoLocations.map((photo) => photo.toJson()).toList()
      );
      await prefs.setString('photo_locations', encodedData);
    } catch (e) {
      debugPrint('Error saving photo locations: $e');
    }
  }
  
  // Capture a new photo at the current location
  Future<PhotoLocation?> capturePhoto(LatLng position, {String? address}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      
      if (image == null) return null;
      
      // Save the image to app documents directory
      final timestamp = DateTime.now();
      final photoId = 'photo_${timestamp.millisecondsSinceEpoch}';
      final savedPath = await _saveImageToDocuments(image, photoId);
      
      // Create photo location object
      final photoLocation = PhotoLocation(
        id: photoId,
        photoPath: savedPath,
        position: position,
        timestamp: timestamp,
        address: address,
      );
      
      // Add to list and save
      _photoLocations.add(photoLocation);
      await _savePhotoLocations();
      
      return photoLocation;
    } catch (e) {
      debugPrint('Error capturing photo: $e');
      return null;
    }
  }
  
  // Pick photo from gallery and tag with location
  Future<PhotoLocation?> pickPhotoFromGallery(LatLng position, {String? address}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      
      if (image == null) return null;
      
      // Save the image to app documents directory
      final timestamp = DateTime.now();
      final photoId = 'photo_${timestamp.millisecondsSinceEpoch}';
      final savedPath = await _saveImageToDocuments(image, photoId);
      
      // Create photo location object
      final photoLocation = PhotoLocation(
        id: photoId,
        photoPath: savedPath,
        position: position,
        timestamp: timestamp,
        address: address,
      );
      
      // Add to list and save
      _photoLocations.add(photoLocation);
      await _savePhotoLocations();
      
      return photoLocation;
    } catch (e) {
      debugPrint('Error picking photo: $e');
      return null;
    }
  }
  
  // Save image to app's documents directory
  Future<String> _saveImageToDocuments(XFile image, String photoId) async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${documentsDir.path}/photos');
    
    // Create the photos directory if it doesn't exist
    if (!photoDir.existsSync()) {
      photoDir.createSync();
    }
    
    // Get file extension from original path
    final extension = image.path.split('.').last;
    final savedPath = '${photoDir.path}/$photoId.$extension';
    
    // Copy the image file to our directory
    final imageFile = File(image.path);
    await imageFile.copy(savedPath);
    
    return savedPath;
  }
  
  // Add description to an existing photo
  Future<void> addPhotoDescription(String photoId, String description) async {
    final index = _photoLocations.indexWhere((photo) => photo.id == photoId);
    if (index == -1) return;
    
    final oldPhoto = _photoLocations[index];
    final updatedPhoto = PhotoLocation(
      id: oldPhoto.id,
      photoPath: oldPhoto.photoPath,
      position: oldPhoto.position,
      timestamp: oldPhoto.timestamp,
      address: oldPhoto.address,
      description: description,
      takenBy: oldPhoto.takenBy,
    );
    
    _photoLocations[index] = updatedPhoto;
    await _savePhotoLocations();
  }
  
  // Delete a photo location
  Future<void> deletePhoto(String photoId) async {
    // Find photo location
    final photoLocation = _photoLocations.firstWhere(
      (photo) => photo.id == photoId,
      orElse: () => throw Exception('Photo not found'),
    );
    
    // Delete physical file
    try {
      final file = File(photoLocation.photoPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting photo file: $e');
    }
    
    // Remove from list and save
    _photoLocations.removeWhere((photo) => photo.id == photoId);
    await _savePhotoLocations();
  }
  
  // Get all photo locations
  List<PhotoLocation> getAllPhotoLocations() {
    return List.unmodifiable(_photoLocations);
  }
  
  // Get photos near a specific location
  List<PhotoLocation> getPhotosNearLocation(LatLng position, double radiusMeters) {
    final distanceCalculator = Distance();
    
    return _photoLocations.where((photo) {
      final distanceInMeters = distanceCalculator.as(
        LengthUnit.Meter, 
        position, 
        photo.position,
      );
      return distanceInMeters <= radiusMeters;
    }).toList();
  }
} 