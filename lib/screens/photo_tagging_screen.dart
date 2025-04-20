import 'dart:io';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../models/photo_location.dart';
import '../services/photo_service.dart';

class PhotoTaggingScreen extends StatefulWidget {
  final LatLng? initialPosition;
  final String? locationName;

  const PhotoTaggingScreen({
    Key? key,
    this.initialPosition,
    this.locationName,
  }) : super(key: key);

  @override
  _PhotoTaggingScreenState createState() => _PhotoTaggingScreenState();
}

class _PhotoTaggingScreenState extends State<PhotoTaggingScreen> with SingleTickerProviderStateMixin {
  final PhotoService _photoService = PhotoService();
  late TabController _tabController;
  
  List<PhotoLocation> _allPhotos = [];
  List<PhotoLocation> _nearbyPhotos = [];
  bool _isLoading = true;
  TextEditingController _descriptionController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initPhotoService();
  }
  
  Future<void> _initPhotoService() async {
    setState(() {
      _isLoading = true;
    });
    
    await _photoService.initialize();
    _refreshPhotoLists();
    
    setState(() {
      _isLoading = false;
    });
  }
  
  void _refreshPhotoLists() {
    _allPhotos = _photoService.getAllPhotoLocations();
    
    if (widget.initialPosition != null) {
      _nearbyPhotos = _photoService.getPhotosNearLocation(
        widget.initialPosition!,
        1000, // 1km radius
      );
    } else {
      _nearbyPhotos = [];
    }
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Tagging'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All Photos'),
            Tab(text: 'Nearby Photos'),
          ],
        ),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAllPhotosTab(),
                _buildNearbyPhotosTab(),
              ],
            ),
      floatingActionButton: widget.initialPosition != null 
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'takephoto',
                  onPressed: _takePhoto,
                  child: const Icon(Icons.camera_alt),
                  tooltip: 'Take Photo',
                ),
                const SizedBox(height: 16),
                FloatingActionButton(
                  heroTag: 'choosephoto',
                  onPressed: _chooseFromGallery,
                  child: const Icon(Icons.photo_library),
                  tooltip: 'Choose from Gallery',
                ),
              ],
            )
          : null,
    );
  }
  
  Widget _buildAllPhotosTab() {
    if (_allPhotos.isEmpty) {
      return _buildEmptyState('No photos yet', 'Take geotagged photos or import existing ones');
    }
    
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: _allPhotos.length,
      itemBuilder: (context, index) {
        return _buildPhotoCard(_allPhotos[index]);
      },
    );
  }
  
  Widget _buildNearbyPhotosTab() {
    if (widget.initialPosition == null) {
      return _buildEmptyState(
        'No location selected',
        'Return to the map and select a location first',
      );
    }
    
    if (_nearbyPhotos.isEmpty) {
      return _buildEmptyState(
        'No photos nearby',
        'Take a photo at this location or import one from your gallery',
      );
    }
    
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: _nearbyPhotos.length,
      itemBuilder: (context, index) {
        return _buildPhotoCard(_nearbyPhotos[index]);
      },
    );
  }
  
  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_album, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          if (widget.initialPosition != null) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _takePhoto,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take Photo'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _chooseFromGallery,
              icon: const Icon(Icons.photo),
              label: const Text('Choose from Gallery'),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildPhotoCard(PhotoLocation photo) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () => _showPhotoDetails(photo),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(photo.photoPath),
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.black54,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('MMM d, yyyy').format(photo.timestamp),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          if (photo.address != null)
                            Text(
                              photo.address!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showPhotoDetails(PhotoLocation photo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Image
              Flexible(
                child: Image.file(
                  File(photo.photoPath),
                  fit: BoxFit.contain,
                ),
              ),
              
              // Details
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date and time
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('MMMM d, yyyy \'at\' h:mm a').format(photo.timestamp),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    // Location
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            photo.address ?? 
                              'Lat: ${photo.position.latitude.toStringAsFixed(6)}, Lng: ${photo.position.longitude.toStringAsFixed(6)}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    // Description if available
                    if (photo.description != null) ...[
                      const Divider(),
                      Text(
                        photo.description!,
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 8),
                    ],
                    
                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.edit_note),
                          label: const Text('Add Description'),
                          onPressed: () {
                            Navigator.pop(context);
                            _showAddDescriptionDialog(photo);
                          },
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _showDeleteConfirmation(photo);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  void _showAddDescriptionDialog(PhotoLocation photo) {
    _descriptionController.text = photo.description ?? '';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Photo Description'),
        content: TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(
            hintText: 'Enter a description for this photo',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final description = _descriptionController.text.trim();
              if (description.isNotEmpty) {
                await _photoService.addPhotoDescription(photo.id, description);
                _refreshPhotoLists();
                setState(() {});
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
  
  void _showDeleteConfirmation(PhotoLocation photo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo?'),
        content: const Text(
          'This will permanently delete this photo from the app. This action cannot be undone.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              await _photoService.deletePhoto(photo.id);
              _refreshPhotoLists();
              setState(() {});
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Photo deleted')),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _takePhoto() async {
    if (widget.initialPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No location selected')),
      );
      return;
    }
    
    final photo = await _photoService.capturePhoto(
      widget.initialPosition!,
      address: widget.locationName,
    );
    
    if (photo != null) {
      _refreshPhotoLists();
      setState(() {});
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo captured and geotagged')),
      );
      
      // Optionally add description right away
      _showAddDescriptionDialog(photo);
    }
  }
  
  Future<void> _chooseFromGallery() async {
    if (widget.initialPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No location selected')),
      );
      return;
    }
    
    final photo = await _photoService.pickPhotoFromGallery(
      widget.initialPosition!,
      address: widget.locationName,
    );
    
    if (photo != null) {
      _refreshPhotoLists();
      setState(() {});
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo imported and geotagged')),
      );
      
      // Optionally add description right away
      _showAddDescriptionDialog(photo);
    }
  }
} 