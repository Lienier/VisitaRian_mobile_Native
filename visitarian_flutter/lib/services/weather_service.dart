import 'dart:convert';

import 'package:http/http.dart' as http;

class WeatherService {
  const WeatherService();

  Future<double> fetchCurrentTemperatureC(String placeQuery) async {
    final query = placeQuery.trim();
    if (query.isEmpty) {
      throw Exception('Location is required to fetch temperature.');
    }

    final geoUri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': query,
      'count': '1',
      'language': 'en',
      'format': 'json',
    });

    final geoRes = await http.get(geoUri);
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
      'current': 'temperature_2m',
    });

    final weatherRes = await http.get(weatherUri);
    if (weatherRes.statusCode != 200) {
      throw Exception('Weather request failed (${weatherRes.statusCode}).');
    }

    final weatherJson = jsonDecode(weatherRes.body) as Map<String, dynamic>;
    final current = weatherJson['current'] as Map<String, dynamic>?;
    final temperature = (current?['temperature_2m'] as num?)?.toDouble();
    if (temperature == null) {
      throw Exception('Temperature is unavailable for this location.');
    }

    return temperature;
  }
}
