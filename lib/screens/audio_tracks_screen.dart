import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import '../services/audio_service.dart';
import '../models/audio_track.dart';

class AudioTracksScreen extends StatefulWidget {
  final LatLng? initialPosition;
  final String? locationName;

  const AudioTracksScreen({
    Key? key,
    this.initialPosition,
    this.locationName,
  }) : super(key: key);

  @override
  State<AudioTracksScreen> createState() => _AudioTracksScreenState();
}

class _AudioTracksScreenState extends State<AudioTracksScreen> with TickerProviderStateMixin {
  final AudioLocationService _audioService = AudioLocationService();
  late TabController _tabController;
  
  List<SongModel> _deviceTracks = [];
  bool _isLoading = true;
  double _selectedRadius = 100.0;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchingAddress = false;
  LatLng? _selectedLocation;
  String? _selectedLocationName;
  List<Map<String, dynamic>> _addressSuggestions = [];
  bool _showAddressSuggestions = false;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initAudioService();
    
    // If initialPosition was provided, use it
    if (widget.initialPosition != null) {
      _selectedLocation = widget.initialPosition;
      _selectedLocationName = widget.locationName;
    }
    
    // Add listener to address controller for auto-completion
    _addressController.addListener(_onAddressChanged);
  }
  
  void _onAddressChanged() {
    final query = _addressController.text.trim();
    if (query.length > 2) {
      _getAddressSuggestions(query);
    } else {
      setState(() {
        _addressSuggestions = [];
        _showAddressSuggestions = false;
      });
    }
  }
  
  Future<void> _getAddressSuggestions(String query) async {
    if (query.isEmpty) return;
    
    setState(() {
      _isSearchingAddress = true;
    });
    
    try {
      // Use Geocoding API to find places that match the query
      List<Map<String, dynamic>> suggestions = [];
      
      // Search by address/street
      try {
        final locations = await locationFromAddress(query);
        for (var location in locations.take(3)) {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            location.latitude, 
            location.longitude,
          );
          
          if (placemarks.isNotEmpty) {
            final placemark = placemarks.first;
            suggestions.add({
              'type': 'address',
              'display': '${placemark.street}, ${placemark.locality}, ${placemark.administrativeArea} ${placemark.postalCode}',
              'location': LatLng(location.latitude, location.longitude),
              'locality': placemark.locality,
              'admin': placemark.administrativeArea,
              'postal': placemark.postalCode,
            });
          }
        }
      } catch (e) {
        // Continue with other search types if address search fails
      }
      
      // Search by city
      if (query.length > 3) {
        try {
          // Create a city-specific query
          final cityQuery = '$query City';
          final locations = await locationFromAddress(cityQuery);
          if (locations.isNotEmpty) {
            final location = locations.first;
            List<Placemark> placemarks = await placemarkFromCoordinates(
              location.latitude, 
              location.longitude,
            );
            
            if (placemarks.isNotEmpty) {
              final placemark = placemarks.first;
              suggestions.add({
                'type': 'city',
                'display': '${placemark.locality}, ${placemark.administrativeArea}',
                'location': LatLng(location.latitude, location.longitude),
                'locality': placemark.locality,
                'admin': placemark.administrativeArea,
              });
            }
          }
        } catch (e) {
          // Continue if city search fails
        }
      }
      
      // Search by ZIP/postal code if query looks like a ZIP code (numbers only)
      if (RegExp(r'^\d+$').hasMatch(query)) {
        try {
          final zipQuery = 'ZIP Code $query';
          final locations = await locationFromAddress(zipQuery);
          if (locations.isNotEmpty) {
            final location = locations.first;
            List<Placemark> placemarks = await placemarkFromCoordinates(
              location.latitude, 
              location.longitude,
            );
            
            if (placemarks.isNotEmpty) {
              final placemark = placemarks.first;
              suggestions.add({
                'type': 'zip',
                'display': '${placemark.postalCode} - ${placemark.locality}, ${placemark.administrativeArea}',
                'location': LatLng(location.latitude, location.longitude),
                'locality': placemark.locality,
                'admin': placemark.administrativeArea,
                'postal': placemark.postalCode,
              });
            }
          }
        } catch (e) {
          // Continue if ZIP search fails
        }
      }
      
      // Search by state if query might be a state name or abbreviation
      if (query.length >= 2) {
        try {
          final stateQuery = 'State of $query';
          final locations = await locationFromAddress(stateQuery);
          if (locations.isNotEmpty) {
            final location = locations.first;
            List<Placemark> placemarks = await placemarkFromCoordinates(
              location.latitude, 
              location.longitude,
            );
            
            if (placemarks.isNotEmpty) {
              final placemark = placemarks.first;
              suggestions.add({
                'type': 'state',
                'display': placemark.administrativeArea,
                'location': LatLng(location.latitude, location.longitude),
                'admin': placemark.administrativeArea,
              });
            }
          }
        } catch (e) {
          // Continue if state search fails
        }
      }
      
      // Remove duplicates
      final uniqueSuggestions = <Map<String, dynamic>>[];
      for (var suggestion in suggestions) {
        if (!uniqueSuggestions.any((s) => s['display'] == suggestion['display'])) {
          uniqueSuggestions.add(suggestion);
        }
      }
      
      setState(() {
        _addressSuggestions = uniqueSuggestions;
        _showAddressSuggestions = uniqueSuggestions.isNotEmpty;
        _isSearchingAddress = false;
      });
    } catch (e) {
      setState(() {
        _isSearchingAddress = false;
        _showAddressSuggestions = false;
      });
    }
  }
  
  void _selectAddressSuggestion(Map<String, dynamic> suggestion) {
    setState(() {
      _addressController.text = suggestion['display'];
      _selectedLocation = suggestion['location'];
      _selectedLocationName = suggestion['display'];
      _showAddressSuggestions = false;
    });
  }
  
  Future<void> _initAudioService() async {
    setState(() {
      _isLoading = true;
    });
    
    await _audioService.initialize();
    await _loadDeviceTracks();
    
    setState(() {
      _isLoading = false;
    });
  }
  
  Future<void> _loadDeviceTracks() async {
    final tracks = await _audioService.getDeviceAudioTracks();
    setState(() {
      _deviceTracks = tracks;
    });
  }
  
  List<SongModel> get _filteredDeviceTracks {
    if (_searchQuery.isEmpty) return _deviceTracks;
    
    return _deviceTracks.where((track) {
      final title = track.title.toLowerCase();
      final artist = (track.artist ?? '').toLowerCase();
      final album = (track.album ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      
      return title.contains(query) || 
             artist.contains(query) || 
             album.contains(query);
    }).toList();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _addressController.removeListener(_onAddressChanged);
    _addressController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Audio Tracks'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'My Tracks'),
            Tab(text: 'Device Music'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLocationTracksTab(),
          _buildDeviceTracksTab(),
        ],
      ),
    );
  }
  
  Widget _buildLocationTracksTab() {
    final locationTracks = _audioService.getLocationAudioTracks();
    
    if (locationTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_note, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No location audio tracks yet',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add tracks from the Device Music tab',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                _tabController.animateTo(1);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Tracks'),
            ),
            const SizedBox(height: 16),
            if (_audioService.isMonitoring())
              ElevatedButton.icon(
                onPressed: () {
                  _audioService.stopMonitoring();
                  setState(() {});
                },
                icon: const Icon(Icons.stop),
                label: const Text('Stop Monitoring'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: locationTracks.isEmpty 
                    ? null
                    : () {
                        _audioService.startMonitoring();
                        setState(() {});
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Location audio monitoring started'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Monitoring'),
              ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        // Monitoring controls
        Container(
          padding: const EdgeInsets.all(16),
          color: _audioService.isMonitoring() 
              ? Colors.green.withOpacity(0.1)
              : Colors.grey.withOpacity(0.1),
          child: Row(
            children: [
              Icon(
                _audioService.isMonitoring() ? Icons.sensors : Icons.sensors_off,
                color: _audioService.isMonitoring() ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _audioService.isMonitoring()
                      ? 'Location audio monitoring is active'
                      : 'Location audio monitoring is disabled',
                  style: TextStyle(
                    color: _audioService.isMonitoring() ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  if (_audioService.isMonitoring()) {
                    _audioService.stopMonitoring();
                  } else {
                    _audioService.startMonitoring();
                  }
                  setState(() {});
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _audioService.isMonitoring() 
                      ? Colors.red 
                      : Colors.green,
                ),
                child: Text(
                  _audioService.isMonitoring() ? 'Stop' : 'Start',
                ),
              ),
            ],
          ),
        ),
        
        // Now playing
        if (_audioService.getCurrentlyPlayingTrack() != null)
          _buildNowPlayingWidget(),
          
        // List of tracks
        Expanded(
          child: ListView.builder(
            itemCount: locationTracks.length,
            itemBuilder: (context, index) {
              final track = locationTracks[index];
              return _buildLocationTrackTile(track);
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildNowPlayingWidget() {
    final track = _audioService.getCurrentlyPlayingTrack();
    if (track == null) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue.withOpacity(0.1),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.music_note,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Now Playing:',
                  style: TextStyle(
                    color: Colors.blue[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  track.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  track.artist,
                  style: const TextStyle(
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            onPressed: () {
              _audioService.stopPlayback();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildLocationTrackTile(LocationAudioTrack track) {
    final isPlaying = _audioService.getCurrentlyPlayingTrack()?.id == track.id;
    
    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: isPlaying ? Colors.blue : Colors.grey[700],
        child: const Icon(
          Icons.music_note,
          color: Colors.white,
        ),
      ),
      title: Text(
        track.title,
        style: TextStyle(
          fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text('${track.artist} • ${track.locations.length} location${track.locations.length == 1 ? '' : 's'}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              isPlaying ? Icons.stop : Icons.play_arrow,
              color: isPlaying ? Colors.red : null,
            ),
            onPressed: () {
              if (isPlaying) {
                _audioService.stopPlayback();
              } else {
                _audioService.playTrackManually(track.id);
              }
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Track'),
                  content: const Text(
                    'Are you sure you want to remove this track and all its locations?'
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              
              if (confirmed == true) {
                await _audioService.removeLocationAudioTrack(track.id);
                setState(() {});
              }
            },
          ),
        ],
      ),
      children: [
        // Show all locations for this track
        ...track.locations.map((location) => _buildLocationItem(track, location)),
        
        // Add a new location to this track
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ElevatedButton.icon(
            onPressed: () {
              _addressController.clear();
              _selectedRadius = 100.0;
              _selectedLocation = null;
              _selectedLocationName = null;
              
              showModalBottomSheet(
                context: context,
                isScrollControlled: true, 
                builder: (context) => _buildAddLocationSheet(track),
              );
            },
            icon: const Icon(Icons.add_location),
            label: const Text('Add Another Location'),
          ),
        ),
      ],
    );
  }
  
  Widget _buildLocationItem(LocationAudioTrack track, LocationPoint location) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                location.locationName ?? 'Unnamed Location',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Coordinates: ${location.position.latitude.toStringAsFixed(6)}, ${location.position.longitude.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                'Trigger radius: ${location.radius.toStringAsFixed(0)} meters',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                    onPressed: () {
                      _addressController.text = location.locationName ?? '';
                      _selectedRadius = location.radius;
                      _selectedLocation = location.position;
                      _selectedLocationName = location.locationName;
                      
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (context) => _buildEditLocationSheet(track, location),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.delete, size: 18),
                    label: const Text('Remove'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Remove Location'),
                          content: const Text(
                            'Are you sure you want to remove this location?'
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Remove'),
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                            ),
                          ],
                        ),
                      );
                      
                      if (confirmed == true) {
                        await _audioService.removeLocationFromTrack(track.id, location.id);
                        setState(() {});
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildAddLocationSheet(LocationAudioTrack track) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 16,
        left: 16,
        right: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add New Location',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text('Track: ${track.title} by ${track.artist}'),
          const SizedBox(height: 16),
          TextField(
            controller: _addressController,
            decoration: const InputDecoration(
              labelText: 'Location Name/Address',
              hintText: 'Enter an address, city, or zip code',
              border: OutlineInputBorder(),
            ),
          ),
          // Address suggestions section
          if (_showAddressSuggestions)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView(
                shrinkWrap: true,
                children: _addressSuggestions.map((suggestion) {
                  IconData icon;
                  Color iconColor;
                  
                  switch (suggestion['type']) {
                    case 'address':
                      icon = Icons.home;
                      iconColor = Colors.blue;
                      break;
                    case 'city':
                      icon = Icons.location_city;
                      iconColor = Colors.green;
                      break;
                    case 'zip':
                      icon = Icons.pin_drop;
                      iconColor = Colors.red;
                      break;
                    case 'state':
                      icon = Icons.map;
                      iconColor = Colors.purple;
                      break;
                    default:
                      icon = Icons.location_on;
                      iconColor = Colors.grey;
                  }
                  
                  return ListTile(
                    leading: Icon(icon, color: iconColor),
                    title: Text(suggestion['display']),
                    subtitle: Text(suggestion['type'].toUpperCase()),
                    onTap: () {
                      _selectAddressSuggestion(suggestion);
                      setState(() {});
                    },
                    dense: true,
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Trigger radius: ${_selectedRadius.toStringAsFixed(0)} meters'),
              ),
              ElevatedButton(
                onPressed: _searchAddress,
                child: const Text('Search Location'),
              ),
            ],
          ),
          Slider(
            value: _selectedRadius,
            min: 10,
            max: 1000,
            divisions: 99,
            label: '${_selectedRadius.toStringAsFixed(0)}m',
            onChanged: (value) {
              setState(() {
                _selectedRadius = value;
              });
            },
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _selectedLocation == null 
                    ? null 
                    : () async {
                        final locationPoint = LocationPoint(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          position: _selectedLocation!,
                          locationName: _addressController.text.isEmpty 
                              ? null 
                              : _addressController.text,
                          radius: _selectedRadius,
                        );
                        
                        await _audioService.addLocationToTrack(track.id, locationPoint);
                        setState(() {});
                        Navigator.pop(context);
                      },
                child: const Text('Add Location'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
  
  Widget _buildEditLocationSheet(LocationAudioTrack track, LocationPoint location) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 16,
        left: 16,
        right: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Edit Location',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text('Track: ${track.title} by ${track.artist}'),
          const SizedBox(height: 16),
          TextField(
            controller: _addressController,
            decoration: const InputDecoration(
              labelText: 'Location Name/Address',
              hintText: 'Enter an address, city, or zip code',
              border: OutlineInputBorder(),
            ),
          ),
          // Address suggestions section
          if (_showAddressSuggestions)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView(
                shrinkWrap: true,
                children: _addressSuggestions.map((suggestion) {
                  IconData icon;
                  Color iconColor;
                  
                  switch (suggestion['type']) {
                    case 'address':
                      icon = Icons.home;
                      iconColor = Colors.blue;
                      break;
                    case 'city':
                      icon = Icons.location_city;
                      iconColor = Colors.green;
                      break;
                    case 'zip':
                      icon = Icons.pin_drop;
                      iconColor = Colors.red;
                      break;
                    case 'state':
                      icon = Icons.map;
                      iconColor = Colors.purple;
                      break;
                    default:
                      icon = Icons.location_on;
                      iconColor = Colors.grey;
                  }
                  
                  return ListTile(
                    leading: Icon(icon, color: iconColor),
                    title: Text(suggestion['display']),
                    subtitle: Text(suggestion['type'].toUpperCase()),
                    onTap: () {
                      _selectAddressSuggestion(suggestion);
                      setState(() {});
                    },
                    dense: true,
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Trigger radius: ${_selectedRadius.toStringAsFixed(0)} meters'),
              ),
              ElevatedButton(
                onPressed: _searchAddress,
                child: const Text('Search Location'),
              ),
            ],
          ),
          Slider(
            value: _selectedRadius,
            min: 10,
            max: 1000,
            divisions: 99,
            label: '${_selectedRadius.toStringAsFixed(0)}m',
            onChanged: (value) {
              setState(() {
                _selectedRadius = value;
              });
            },
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _selectedLocation == null 
                    ? null 
                    : () async {
                        await _audioService.updateLocationForTrack(
                          track.id,
                          location.id,
                          _selectedLocation!,
                          _addressController.text.isEmpty 
                              ? null 
                              : _addressController.text,
                          _selectedRadius,
                        );
                        
                        setState(() {});
                        Navigator.pop(context);
                      },
                child: const Text('Save Changes'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
  
  Future<void> _searchAddress() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) return;
    
    // If suggestions are already showing, don't do another search
    if (_showAddressSuggestions) {
      setState(() {
        _showAddressSuggestions = false;
      });
      return;
    }
    
    setState(() {
      _isSearchingAddress = true;
    });
    
    try {
      // Force a search for the exact address entered
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        final location = locations.first;
        setState(() {
          _selectedLocation = LatLng(location.latitude, location.longitude);
          _selectedLocationName = address;
          _isSearchingAddress = false;
        });
        
        // Show confirmation
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location set to: $address')),
        );
      } else {
        setState(() {
          _isSearchingAddress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location not found')),
        );
      }
    } catch (e) {
      setState(() {
        _isSearchingAddress = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching location: $e')),
      );
    }
  }
  
  Widget _buildDeviceTracksTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_deviceTracks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No music found on your device',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              'Add some music to your device and try again',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        // Search bar for songs
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search for songs, artists or albums',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),
        
        // Location selection
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Location: ${_selectedLocationName ?? 'Current location'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        hintText: 'Enter address, city, or zip code',
                        prefixIcon: Icon(Icons.location_on),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _isSearchingAddress
                      ? const CircularProgressIndicator()
                      : IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: _searchAddress,
                        ),
                ],
              ),
              if (_showAddressSuggestions)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _addressSuggestions.map((suggestion) {
                      IconData icon;
                      Color iconColor;
                      
                      switch (suggestion['type']) {
                        case 'address':
                          icon = Icons.home;
                          iconColor = Colors.blue;
                          break;
                        case 'city':
                          icon = Icons.location_city;
                          iconColor = Colors.green;
                          break;
                        case 'zip':
                          icon = Icons.pin_drop;
                          iconColor = Colors.red;
                          break;
                        case 'state':
                          icon = Icons.map;
                          iconColor = Colors.purple;
                          break;
                        default:
                          icon = Icons.location_on;
                          iconColor = Colors.grey;
                      }
                      
                      return ListTile(
                        leading: Icon(icon, color: iconColor),
                        title: Text(suggestion['display']),
                        subtitle: Text(suggestion['type'].toUpperCase()),
                        onTap: () => _selectAddressSuggestion(suggestion),
                        dense: true,
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
        
        // Radius selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('Trigger radius: '),
              Expanded(
                child: Slider(
                  value: _selectedRadius,
                  min: 10,
                  max: 1000,
                  divisions: 99,
                  label: '${_selectedRadius.toStringAsFixed(0)}m',
                  onChanged: (value) {
                    setState(() {
                      _selectedRadius = value;
                    });
                  },
                ),
              ),
              Text('${_selectedRadius.toStringAsFixed(0)}m'),
            ],
          ),
        ),
          
        // List of device tracks
        Expanded(
          child: ListView.builder(
            itemCount: _filteredDeviceTracks.length,
            itemBuilder: (context, index) {
              final track = _filteredDeviceTracks[index];
              return _buildDeviceTrackTile(track);
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildDeviceTrackTile(SongModel track) {
    return ListTile(
      leading: QueryArtworkWidget(
        id: track.id,
        type: ArtworkType.AUDIO,
        nullArtworkWidget: CircleAvatar(
          backgroundColor: Colors.grey[800],
          child: const Icon(
            Icons.music_note,
            color: Colors.white,
          ),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${track.artist ?? 'Unknown Artist'}\n${track.album ?? 'Unknown Album'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: _selectedLocation == null
          ? null
          : IconButton(
              icon: const Icon(Icons.add_location),
              onPressed: () async {
                await _audioService.addLocationAudioTrack(
                  song: track,
                  position: _selectedLocation!,
                  locationName: _selectedLocationName,
                  radius: _selectedRadius,
                );
                
                // Show confirmation
                if (!mounted) return;
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Added "${track.title}" to ${_selectedLocationName ?? 'this location'}'
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
                
                // Switch to first tab to show the added track
                _tabController.animateTo(0);
                setState(() {});
              },
            ),
      onTap: () {
        if (_selectedLocation != null) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Add to Location'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Song: ${track.title}'),
                  Text('Artist: ${track.artist ?? "Unknown Artist"}'),
                  if (_selectedLocationName != null)
                    Text('Location: $_selectedLocationName'),
                  const SizedBox(height: 16),
                  const Text('Trigger radius:'),
                  Slider(
                    value: _selectedRadius,
                    min: 10,
                    max: 1000,
                    divisions: 99,
                    label: '${_selectedRadius.toStringAsFixed(0)}m',
                    onChanged: (value) {
                      setState(() {
                        _selectedRadius = value;
                      });
                    },
                  ),
                  Text('${_selectedRadius.toStringAsFixed(0)} meters'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _audioService.addLocationAudioTrack(
                      song: track,
                      position: _selectedLocation!,
                      locationName: _selectedLocationName,
                      radius: _selectedRadius,
                    );
                    
                    if (!mounted) return;
                    Navigator.pop(context);
                    
                    // Switch to first tab to show the added track
                    _tabController.animateTo(0);
                    setState(() {});
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
          );
        }
      },
    );
  }
} 