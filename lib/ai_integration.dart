import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AIAssistant {
  static const String _baseUrl = 'https://api.openai.com/v1/chat/completions';
  
  static Future<String> askQuestion({
    required String userPrompt,
    required String locationContext,
    required BuildContext context,
  }) async {
    try {
      final apiKey = dotenv.env['OPENAI_API_KEY'];
      
      if (apiKey == null || apiKey.isEmpty) {
        return 'Error: OpenAI API key not found. Please check your .env file.';
      }
      
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {
              'role': 'system',
              'content': 'You are a helpful assistant that provides information based on location data. '
                  'You have access to the user\'s location history and can provide insights about their '
                  'travels, locations, and provide suggestions based on their current and past locations.'
            },
            {
              'role': 'user',
              'content': 'Here is my location data: $locationContext\n\nMy question is: $userPrompt'
            }
          ],
          'temperature': 0.7,
          'max_tokens': 1000,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        return 'Error ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      return 'Error connecting to OpenAI: $e';
    }
  }
}

class AIAssistantPage extends StatefulWidget {
  final String locationContext;
  
  const AIAssistantPage({
    Key? key,
    required this.locationContext,
  }) : super(key: key);
  
  @override
  State<AIAssistantPage> createState() => _AIAssistantPageState();
}

class _AIAssistantPageState extends State<AIAssistantPage> {
  final TextEditingController _promptController = TextEditingController();
  String _response = '';
  bool _isLoading = false;
  
  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }
  
  Future<void> _sendPrompt() async {
    final prompt = _promptController.text;
    
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a question')),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final response = await AIAssistant.askQuestion(
        userPrompt: prompt,
        locationContext: widget.locationContext,
        context: context,
      );
      
      setState(() {
        _response = response;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _response = 'Error: $e';
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _promptController,
              decoration: const InputDecoration(
                hintText: 'Ask a question about your location data...',
                border: OutlineInputBorder(),
                filled: true,
              ),
              maxLines: 3,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Text(
                  'Using location data from ${widget.locationContext.split('\n').length} points',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _isLoading ? null : _sendPrompt,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Ask AI'),
                ),
              ],
            ),
          ),
          const Divider(),
          if (_response.isNotEmpty)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Response:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(_response),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_response.isEmpty && !_isLoading)
            const Expanded(
              child: Center(
                child: Text(
                  'Ask the AI assistant questions about your location data,\n'
                  'travel patterns, or recommendations based on your history.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
} 