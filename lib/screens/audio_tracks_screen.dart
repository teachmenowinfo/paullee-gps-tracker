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
    
    return ListTile(
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(track.artist),
          if (track.locationName != null)
            Text(
              'Location: ${track.locationName}',
              style: const TextStyle(fontSize: 12),
            ),
          Text(
            'Range: ${track.radius.toStringAsFixed(0)}m',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
      isThreeLine: true,
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
                    'Are you sure you want to remove this track from this location?'
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
    );
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
  
  Future<void> _searchAddress() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) return;
    
    setState(() {
      _isSearchingAddress = true;
    });
    
    try {
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