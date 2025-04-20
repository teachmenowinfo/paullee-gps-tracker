import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceCommandService {
  static final VoiceCommandService _instance = VoiceCommandService._internal();
  factory VoiceCommandService() => _instance;
  VoiceCommandService._internal();

  final SpeechToText _speech = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isListening = false;
  final _commandController = StreamController<String>.broadcast();
  
  Stream<String> get commandStream => _commandController.stream;
  
  // Initialize the speech recognition service
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    _isInitialized = await _speech.initialize(
      onError: (error) => debugPrint('Speech recognition error: $error'),
      onStatus: (status) => debugPrint('Speech recognition status: $status'),
    );
    
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    
    return _isInitialized;
  }
  
  // Start listening for voice commands
  Future<bool> startListening() async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }
    
    if (_isListening) return true;
    
    _isListening = await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          final command = result.recognizedWords.toLowerCase();
          _commandController.add(command);
          _processCommand(command);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      localeId: 'en_US',
    );
    
    return _isListening;
  }
  
  // Stop listening for voice commands
  Future<void> stopListening() async {
    _speech.stop();
    _isListening = false;
  }
  
  // Process the recognized command
  void _processCommand(String command) {
    debugPrint('Processed voice command: $command');
    // Command processing is done by the command handler
  }
  
  // Speak feedback to the user
  Future<void> speak(String text) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return;
    }
    
    await _flutterTts.speak(text);
  }
  
  // Dispose resources
  void dispose() {
    stopListening();
    _commandController.close();
    _flutterTts.stop();
  }
}

class VoiceCommandButton extends StatefulWidget {
  final Function(String) onCommand;
  
  const VoiceCommandButton({
    Key? key,
    required this.onCommand,
  }) : super(key: key);
  
  @override
  State<VoiceCommandButton> createState() => _VoiceCommandButtonState();
}

class _VoiceCommandButtonState extends State<VoiceCommandButton> {
  final VoiceCommandService _voiceService = VoiceCommandService();
  bool _isListening = false;
  StreamSubscription? _commandSubscription;
  
  @override
  void initState() {
    super.initState();
    _initVoiceService();
  }
  
  Future<void> _initVoiceService() async {
    await _voiceService.initialize();
    _commandSubscription = _voiceService.commandStream.listen((command) {
      widget.onCommand(command);
    });
  }
  
  void _toggleListening() async {
    if (_isListening) {
      await _voiceService.stopListening();
      _voiceService.speak('Voice commands disabled');
    } else {
      final success = await _voiceService.startListening();
      if (success) {
        _voiceService.speak('Listening for commands');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start voice recognition')),
        );
      }
    }
    
    setState(() {
      _isListening = !_isListening;
    });
  }
  
  @override
  void dispose() {
    _commandSubscription?.cancel();
    _voiceService.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: _toggleListening,
      backgroundColor: _isListening ? Colors.red : Colors.blue,
      child: Icon(_isListening ? Icons.mic : Icons.mic_none),
      tooltip: _isListening ? 'Stop listening' : 'Start voice commands',
    );
  }
}

class VoiceCommandHandler {
  static void handleCommand(String command, BuildContext context, Function(String) callback) {
    // List of supported commands
    if (command.contains('zoom in')) {
      callback('zoom_in');
    } else if (command.contains('zoom out')) {
      callback('zoom_out');
    } else if (command.contains('start tracking') || command.contains('begin tracking')) {
      callback('start_tracking');
    } else if (command.contains('stop tracking') || command.contains('end tracking')) {
      callback('stop_tracking');
    } else if (command.contains('show history') || command.contains('view history')) {
      callback('show_history');
    } else if (command.contains('take photo') || command.contains('capture photo')) {
      callback('take_photo');
    } else if (command.contains('current location') || command.contains('where am i')) {
      callback('current_location');
    } else if (command.contains('get weather') || command.contains('show weather')) {
      callback('get_weather');
    } else if (command.contains('help') || command.contains('commands')) {
      _showHelpDialog(context);
    } else {
      // Unknown command
      VoiceCommandService().speak('Command not recognized. Try again or say "help" for available commands.');
    }
  }
  
  static void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Voice Commands'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('• "zoom in" - Zoom in on the map'),
            Text('• "zoom out" - Zoom out on the map'),
            Text('• "start tracking" - Begin location tracking'),
            Text('• "stop tracking" - End location tracking'),
            Text('• "show history" - View location history'),
            Text('• "take photo" - Capture a geotagged photo'),
            Text('• "current location" - Center map on current location'),
            Text('• "get weather" - Show weather for current location'),
            Text('• "help" - Show this help dialog'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
} 