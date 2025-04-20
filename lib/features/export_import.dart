import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

class LocationExporter {
  // Function to convert location history to GPX format
  static String toGPX(List<dynamic> locations) {
    final buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="UTF-8"?>\n');
    buffer.write('<gpx version="1.1" creator="LocationTracker" xmlns="http://www.topografix.com/GPX/1/1">\n');
    buffer.write('  <trk>\n');
    buffer.write('    <name>Location Track</name>\n');
    buffer.write('    <trkseg>\n');

    for (final location in locations) {
      buffer.write('      <trkpt lat="${location.position.latitude}" lon="${location.position.longitude}">\n');
      if (location.timestamp != null) {
        final timeStr = location.timestamp.toIso8601String();
        buffer.write('        <time>$timeStr</time>\n');
      }
      if (location.accuracy != null) {
        buffer.write('        <accuracy>${location.accuracy}</accuracy>\n');
      }
      if (location.address != null) {
        buffer.write('        <desc>${location.address}</desc>\n');
      }
      buffer.write('      </trkpt>\n');
    }

    buffer.write('    </trkseg>\n');
    buffer.write('  </trk>\n');
    buffer.write('</gpx>');

    return buffer.toString();
  }

  // Function to convert location history to JSON format
  static String toJSON(List<dynamic> locations) {
    final jsonList = locations.map((location) {
      return {
        'latitude': location.position.latitude,
        'longitude': location.position.longitude,
        'timestamp': location.timestamp?.toIso8601String(),
        'accuracy': location.accuracy,
        'address': location.address,
        'isVisited': location.isVisited,
      };
    }).toList();

    return jsonEncode(jsonList);
  }

  // Function to export data to a file and share it
  static Future<void> exportAndShare(
    List<dynamic> locations, 
    String format, 
    BuildContext context
  ) async {
    try {
      String content;
      String extension;
      String mimeType;
      
      if (format == 'gpx') {
        content = toGPX(locations);
        extension = 'gpx';
        mimeType = 'application/gpx+xml';
      } else {
        content = toJSON(locations);
        extension = 'json';
        mimeType = 'application/json';
      }
      
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/location_data_$timestamp.$extension');
      
      await file.writeAsString(content);
      
      // Share the file
      await Share.shareXFiles(
        [XFile(file.path, mimeType: mimeType)],
        subject: 'Location Data Export',
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully exported location data as $extension')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting data: $e')),
      );
    }
  }
  
  // Function to import data from a file
  static Future<List<Map<String, dynamic>>?> importFromFile(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'gpx'],
      );
      
      if (result == null || result.files.isEmpty) {
        return null;
      }
      
      final file = File(result.files.first.path!);
      final content = await file.readAsString();
      final extension = result.files.first.extension?.toLowerCase();
      
      if (extension == 'json') {
        final jsonData = jsonDecode(content) as List;
        return jsonData.cast<Map<String, dynamic>>();
      } else if (extension == 'gpx') {
        // GPX parsing would need a more complex XML parser 
        // For demonstration purposes, just show a message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPX importing is a work in progress')),
        );
        return null;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unsupported file format')),
        );
        return null;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error importing data: $e')),
      );
      return null;
    }
  }
} 