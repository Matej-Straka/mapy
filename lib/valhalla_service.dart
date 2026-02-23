import 'dart:convert';
import 'package:http/http.dart' as http;

/// Enum for supported Valhalla profiles
enum ValhallaProfile { bicycle, pedestrian, auto }

/// Class representing a single location
class ValhallaLocation {
  final double lat;
  final double lon;
  final String format;

  ValhallaLocation({
    required this.lat,
    required this.lon,
    this.format = 'json',
  });

  /// Create a ValhallaLocation from a comma-separated string (e.g., "49.066, 17.459")
  factory ValhallaLocation.fromString(String coordString) {
    final parts = coordString.split(',').map((s) => s.trim()).toList();
    if (parts.length != 2) {
      throw FormatException('Invalid coordinate format. Expected "lat, lon"');
    }
    return ValhallaLocation(
      lat: double.parse(parts[0]),
      lon: double.parse(parts[1]),
    );
  }

  Map<String, dynamic> toJson() => {"lat": lat, "lon": lon, "format": format};
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
    }
  }

  /// Send a route request
  Future<dynamic> getRoute({
    required List<ValhallaLocation> locations,
    ValhallaProfile profile = ValhallaProfile.bicycle,
    Map<String, dynamic>? profileOptions,
    String units = 'km',
    String format = 'json',
  }) async {
    final url = Uri.parse('$baseUrl/route');

    final requestBody = {
      "locations": locations.map((loc) => loc.toJson()).toList(),
      "costing": _profileToString(profile),
      "costing_options": {_profileToString(profile): profileOptions ?? {}},
      "directions_options": {"units": units},
      "format": format,
    };

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      if (format == 'gpx') {
        return response.body; // Return raw GPX string
      } else {
        return jsonDecode(response.body); // Return JSON
      }
    } else {
      throw Exception(
        "Valhalla request failed: ${response.statusCode} ${response.body}",
      );
    }
  }
}
