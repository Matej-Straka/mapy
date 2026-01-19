import 'dart:convert';
import 'package:http/http.dart' as http;

/// Enum for supported Valhalla profiles
enum ValhallaProfile { bicycle, pedestrian, auto }

/// Class representing a single location
class ValhallaLocation {
  final double lat;
  final double lon;

  ValhallaLocation({required this.lat, required this.lon});

  Map<String, dynamic> toJson() => {"lat": lat, "lon": lon};
}

/// Main Valhalla service
class ValhallaService {
  final String baseUrl;

  ValhallaService({this.baseUrl = 'https://valhalla1.openstreetmap.de'});

  /// Convert enum to string
  String _profileToString(ValhallaProfile profile) {
    switch (profile) {
      case ValhallaProfile.bicycle:
        return 'bicycle';
      case ValhallaProfile.pedestrian:
        return 'pedestrian';
      case ValhallaProfile.auto:
        return 'auto';
      default:
        return 'auto';
    }
  }

  /// Send a route request
  Future<Map<String, dynamic>> getRoute({
    required List<ValhallaLocation> locations,
    ValhallaProfile profile = ValhallaProfile.bicycle,
    Map<String, dynamic>? profileOptions,
    String units = 'km',
  }) async {
    final url = Uri.parse('$baseUrl/route');

    final requestBody = {
      "locations": locations.map((loc) => loc.toJson()).toList(),
      "costing": _profileToString(profile),
      "costing_options": {_profileToString(profile): profileOptions ?? {}},
      "directions_options": {"units": units},
    };

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
        "Valhalla request failed: ${response.statusCode} ${response.body}",
      );
    }
  }
}
