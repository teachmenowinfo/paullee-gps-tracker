# PaulLee GPS Tracker

A Flutter application for location tracking with location-based audio playback.

## Features

- Real-time GPS tracking with customizable precision modes
- Location history tracking and visualization
- Geolocation services with address lookup
- Track visited places
- Audio tracks that play automatically when you enter specific locations
- Set music for locations by address or current position
- Configurable trigger radius for audio playback
- Map visualization with OpenStreetMap

## Getting Started

### Prerequisites

- Flutter SDK: 3.7 or higher
- Dart SDK: 3.0.0 or higher
- iOS 12.0+ / Android API 21+
- XCode 14+ (for iOS builds)
- Android Studio (for Android builds)

### Installation

1. Clone this repository
```
git clone https://github.com/yourusername/flutter-location.git
```

2. Navigate to the project directory
```
cd flutter-location/location_tracker
```

3. Install dependencies
```
flutter pub get
```

4. Create a `.env` file in the project root with your API keys (if required)

5. Run the app
```
flutter run
```

## How to Use

### Location Tracking

- Tap the play button to start tracking your location
- Use high precision mode for more accurate tracking (battery intensive)
- View your location history by tapping the history button

### Location-Based Audio

1. Access the Audio Tracks feature from the Advanced Features menu
2. Choose a song from your device
3. Set a location (either your current location or by entering an address)
4. Set a trigger radius
5. Activate monitoring
6. When you enter the specified location, the audio will play automatically

## Privacy

This app respects your privacy:
- Location data is stored locally on your device
- No data is sent to external servers without your consent
- You can delete all stored data from the settings

## License

This project is licensed under the MIT License - see the LICENSE file for details.
