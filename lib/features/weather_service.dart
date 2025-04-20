import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';

class WeatherService {
  static Future<Map<String, dynamic>> getWeatherForLocation(LatLng location) async {
    try {
      final apiKey = dotenv.env['OPENWEATHER_API_KEY'];
      
      if (apiKey == null || apiKey.isEmpty) {
        return {
          'success': false,
          'error': 'OpenWeather API key not found. Please add it to your .env file.'
        };
      }
      
      final response = await http.get(
        Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather?lat=${location.latitude}&lon=${location.longitude}&appid=$apiKey&units=metric'
        ),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        return {
          'success': true,
          'temperature': data['main']['temp'],
          'feelsLike': data['main']['feels_like'],
          'description': data['weather'][0]['description'],
          'icon': data['weather'][0]['icon'],
          'humidity': data['main']['humidity'],
          'windSpeed': data['wind']['speed'],
          'cityName': data['name'],
          'iconUrl': 'https://openweathermap.org/img/wn/${data['weather'][0]['icon']}@2x.png',
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to fetch weather data. Status code: ${response.statusCode}'
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Error fetching weather data: $e'
      };
    }
  }
}

class WeatherWidget extends StatelessWidget {
  final LatLng location;
  final String locationName;

  const WeatherWidget({
    Key? key,
    required this.location,
    required this.locationName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: WeatherService.getWeatherForLocation(location),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Failed to load weather data'),
            ),
          );
        }

        final weatherData = snapshot.data!;
        
        if (weatherData['success'] == false) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Weather error: ${weatherData['error']}'),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (weatherData['iconUrl'] != null)
                      Image.network(
                        weatherData['iconUrl'],
                        width: 50,
                        height: 50,
                        errorBuilder: (context, error, stackTrace) => 
                          const Icon(Icons.cloud, size: 50),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            locationName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            weatherData['description'] ?? 'No description',
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('Temperature'),
                        Text(
                          '${weatherData['temperature']}°C',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Feels Like'),
                        Text(
                          '${weatherData['feelsLike']}°C',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Humidity'),
                        Text(
                          '${weatherData['humidity']}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
} 