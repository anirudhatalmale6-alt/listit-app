import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/weather.dart';

/// Fetches current conditions from Open-Meteo - a free, keyless weather API
/// that sends permissive CORS headers, so it works from both the native app
/// and the browser preview without a proxy.
///
/// Defaults to the Isle of Man (Douglas), which is "local" for a Manx
/// marketplace. Coordinates can be swapped for the device's own location later.
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 8);

  // Isle of Man (Douglas).
  static const double _lat = 54.15;
  static const double _lon = -4.48;
  static const String _place = 'Isle of Man';

  Future<Weather> fetchCurrent() async {
    final uri = Uri.parse('https://api.open-meteo.com/v1/forecast').replace(
      queryParameters: {
        'latitude': '$_lat',
        'longitude': '$_lon',
        'current': 'temperature_2m,weather_code',
      },
    );
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('weather ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final current = body['current'] as Map<String, dynamic>?;
    if (current == null) throw Exception('no current weather');
    final temp = (current['temperature_2m'] as num?)?.toDouble() ?? 0;
    final code = (current['weather_code'] as num?)?.toInt() ?? 0;
    return Weather(tempC: temp, code: code, place: _place);
  }

  void dispose() => _client.close();
}
