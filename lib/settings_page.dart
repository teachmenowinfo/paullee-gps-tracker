import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  final int gpsUpdateIntervalSeconds;
  final int gpsDistanceFilterMeters;
  final List<String> logEntries;
  final Function(int interval, int distance) onSettingsChanged;

  const SettingsPage({
    Key? key,
    required this.gpsUpdateIntervalSeconds,
    required this.gpsDistanceFilterMeters,
    required this.logEntries,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late int _updateInterval;
  late int _distanceFilter;
  bool _showLog = false;
  String _timeUnit = 'seconds';
  
  final Map<String, int> _timeUnitMultipliers = {
    'seconds': 1,
    'minutes': 60,
    'hours': 3600,
    'days': 86400,
  };
  
  final Map<String, List<int>> _timeUnitRanges = {
    'seconds': [1, 60],
    'minutes': [1, 60],
    'hours': [1, 24],
    'days': [1, 7],
  };

  @override
  void initState() {
    super.initState();
    _distanceFilter = widget.gpsDistanceFilterMeters;
    // Convert incoming seconds to the appropriate unit
    _determineTimeUnit(widget.gpsUpdateIntervalSeconds);
  }
  
  void _determineTimeUnit(int totalSeconds) {
    if (totalSeconds >= 86400 && totalSeconds % 86400 == 0) {
      _timeUnit = 'days';
      _updateInterval = totalSeconds ~/ 86400;
    } else if (totalSeconds >= 3600 && totalSeconds % 3600 == 0) {
      _timeUnit = 'hours';
      _updateInterval = totalSeconds ~/ 3600;
    } else if (totalSeconds >= 60 && totalSeconds % 60 == 0) {
      _timeUnit = 'minutes';
      _updateInterval = totalSeconds ~/ 60;
    } else {
      _timeUnit = 'seconds';
      _updateInterval = totalSeconds;
    }
  }
  
  int _getTotalSeconds() {
    return _updateInterval * _timeUnitMultipliers[_timeUnit]!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.terminal),
            onPressed: () {
              setState(() {
                _showLog = !_showLog;
              });
            },
            tooltip: 'Show/Hide Log',
          ),
        ],
      ),
      body: _showLog ? _buildLogView() : _buildSettingsView(),
    );
  }

  Widget _buildSettingsView() {
    final currentRange = _timeUnitRanges[_timeUnit]!;
    
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GPS Update Interval',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Current value: $_updateInterval $_timeUnit',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    DropdownButton<String>(
                      value: _timeUnit,
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _timeUnit = newValue;
                            // Ensure value is within the new range
                            final newRange = _timeUnitRanges[newValue]!;
                            _updateInterval = _updateInterval.clamp(newRange[0], newRange[1]);
                          });
                        }
                      },
                      items: _timeUnitMultipliers.keys
                          .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                Slider(
                  value: _updateInterval.toDouble(),
                  min: currentRange[0].toDouble(),
                  max: currentRange[1].toDouble(),
                  divisions: currentRange[1] - currentRange[0],
                  label: '$_updateInterval $_timeUnit',
                  onChanged: (value) {
                    setState(() {
                      _updateInterval = value.round();
                    });
                  },
                ),
                const Text(
                  'More frequent updates provide more accurate tracking but use more battery.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GPS Distance Filter',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current value: $_distanceFilter meters',
                  style: const TextStyle(fontSize: 16),
                ),
                Slider(
                  value: _distanceFilter.toDouble(),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: '$_distanceFilter m',
                  onChanged: (value) {
                    setState(() {
                      _distanceFilter = value.round();
                    });
                  },
                ),
                const Text(
                  'Only record new positions when you\'ve moved at least this many meters.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () {
            final totalSeconds = _getTotalSeconds();
            widget.onSettingsChanged(totalSeconds, _distanceFilter);
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Settings saved: update every $_updateInterval $_timeUnit')),
            );
          },
          child: const Text('Save Settings'),
        ),
      ],
    );
  }

  Widget _buildLogView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              const Text(
                'Application Log',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
                onPressed: widget.logEntries.isEmpty 
                    ? null 
                    : () {
                        // Copy to clipboard logic would go here
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Log copied to clipboard')),
                        );
                      },
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: widget.logEntries.isEmpty
              ? const Center(child: Text('No log entries yet'))
              : ListView.builder(
                  itemCount: widget.logEntries.length,
                  itemBuilder: (context, index) {
                    final reversedIndex = widget.logEntries.length - 1 - index;
                    final logEntry = widget.logEntries[reversedIndex];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 4.0,
                      ),
                      child: Text(
                        logEntry,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
} 