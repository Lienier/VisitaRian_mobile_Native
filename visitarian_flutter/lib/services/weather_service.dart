import 'dart:convert';

import 'package:http/http.dart' as http;

class WeatherService {
  const WeatherService();

  Future<String> fetchCurrentCondition(String placeQuery) async {
    final query = placeQuery.trim();
    if (query.isEmpty) {
      throw Exception('Location is required to fetch weather.');
    }

    final geoUri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': query,
      'count': '1',
      'language': 'en',
      'format': 'json',
    });

    final geoRes = await http.get(geoUri).timeout(const Duration(seconds: 10));
    if (geoRes.statusCode != 200) {
      throw Exception('Geocoding request failed (${geoRes.statusCode}).');
    }

    final geoJson = jsonDecode(geoRes.body) as Map<String, dynamic>;
    final results = geoJson['results'] as List<dynamic>?;
    if (results == null ||
        results.isEmpty ||
        results.first is! Map<String, dynamic>) {
      throw Exception('Location not found.');
    }

    final first = results.first as Map<String, dynamic>;
    final latitude = (first['latitude'] as num?)?.toDouble();
    final longitude = (first['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) {
      throw Exception('Invalid geocoding coordinates.');
    }

    final weatherUri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current': 'weather_code',
      'current_weather': 'true',
    });

    final weatherRes = await http
        .get(weatherUri)
        .timeout(const Duration(seconds: 10));
    if (weatherRes.statusCode != 200) {
      throw Exception('Weather request failed (${weatherRes.statusCode}).');
    }

    final weatherJson = jsonDecode(weatherRes.body) as Map<String, dynamic>;
    final current = weatherJson['current'] as Map<String, dynamic>?;
    final currentWeather =
        weatherJson['current_weather'] as Map<String, dynamic>?;
    final weatherCode =
        (current?['weather_code'] as num?)?.toInt() ??
        (currentWeather?['weathercode'] as num?)?.toInt();
    if (weatherCode == null) {
      throw Exception('Weather is unavailable for this location.');
    }

    return _mapWeatherCode(weatherCode);
  }

  String _mapWeatherCode(int code) {
    if (code == 0) return 'Sunny';
    if (code == 1) return 'Mostly Sunny';
    if (code == 2) return 'Partly Cloudy';
    if (code == 3) return 'Cloudy';
    if (code == 45 || code == 48) return 'Foggy';
    if (code == 51 || code == 53 || code == 55 || code == 56 || code == 57) {
      return 'Drizzle';
    }
    if (code == 61 || code == 63 || code == 65 || code == 66 || code == 67) {
      return 'Rainy';
    }
    if (code == 71 || code == 73 || code == 75 || code == 77) return 'Snowy';
    if (code == 80 || code == 81 || code == 82) return 'Rain Showers';
    if (code == 85 || code == 86) return 'Snow Showers';
    if (code == 95 || code == 96 || code == 99) return 'Stormy';
    return 'Unknown';
  }
}
