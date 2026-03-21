import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'valhalla_service.dart';
import 'package:universal_html/html.dart' as html;
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';

class SpeedSettings {
  double walkingSpeed; // km/h
  double cyclingSpeed; // km/h

  SpeedSettings({this.walkingSpeed = 5.0, this.cyclingSpeed = 22.0});
}

await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
);

void main() {
  html.document.onContextMenu.listen((event) => event.preventDefault());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final List<Marker> _markers = [];
  late Marker _startMarker = Marker(
    point: LatLng(0, 0),
    width: 40,
    height: 40,
    child: const Icon(Icons.location_on, color: Colors.green, size: 40),
  );
  late Marker _endMarker = Marker(
    point: LatLng(0, 0),
    width: 40,
    height: 40,
    child: const Icon(Icons.location_on, color: Colors.red, size: 40),
  );
  final MapController _mapController = MapController();
  List<LatLng> _routePoints = [];

  final TextEditingController startPointController = TextEditingController();
  final TextEditingController endPointController = TextEditingController();

  late SpeedSettings _speedSettings;

  @override
  void initState() {
    super.initState();
    _speedSettings = SpeedSettings();
  }

  calc(String mode) async {
    final valhalla = ValhallaService();

    Map<String, dynamic> profileOptions = {"use_roads": 0.3, "use_trails": 0.8};

    if (mode == 'bicycle') {
      profileOptions["cycling_speed"] = _speedSettings.cyclingSpeed;
    } else if (mode == 'pedestrian') {
      profileOptions["walking_speed"] = _speedSettings.walkingSpeed;
    }

    final route = await valhalla.getRoute(
      locations: [
        if (startPointController.text.isNotEmpty)
          ValhallaLocation.fromString(startPointController.text),
        if (endPointController.text.isNotEmpty)
          ValhallaLocation.fromString(endPointController.text),
      ],
      profile: ValhallaProfile.values.firstWhere(
        (p) => p.toString().split('.').last == mode,
      ),
      profileOptions: profileOptions,
    );
    print(route);
    String encodedShape = route['trip']['legs'][0]['shape'];
    setState(() {
      _routePoints = decodeValhallaShape(encodedShape);
    });
    return route;
  }

  export(String mode, {String exportFormat = 'gpx'}) async {
    final valhalla = ValhallaService();

    Map<String, dynamic> profileOptions = {"use_roads": 0.3, "use_trails": 0.8};

    if (mode == 'bicycle') {
      profileOptions["cycling_speed"] = _speedSettings.cyclingSpeed;
    } else if (mode == 'pedestrian') {
      profileOptions["walking_speed"] = _speedSettings.walkingSpeed;
    }

    try {
      final content = await valhalla.getRoute(
        locations: [
          if (startPointController.text.isNotEmpty)
            ValhallaLocation.fromString(startPointController.text),
          if (endPointController.text.isNotEmpty)
            ValhallaLocation.fromString(endPointController.text),
        ],
        profile: ValhallaProfile.values.firstWhere(
          (p) => p.toString().split('.').last == mode,
        ),
        profileOptions: profileOptions,
        format: exportFormat,
      );

      if (exportFormat == 'gpx') {
        final bytes = utf8.encode(content);
        final blob = html.Blob([bytes], 'application/gpx+xml');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'route.gpx')
          ..click();
        html.Url.revokeObjectUrl(url);
        print('GPX file downloaded successfully');
      } else if (exportFormat == 'json') {
        final jsonContent = jsonEncode(
          content,
          toEncodable: (o) => o.toString(),
        );
        final bytes = utf8.encode(jsonContent);
        final blob = html.Blob([bytes], 'application/json');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'route.json')
          ..click();
        html.Url.revokeObjectUrl(url);
        print('JSON file downloaded successfully');
      }
    } catch (e) {
      print('Export error: $e');
      rethrow;
    }
  }

  List<LatLng> decodeValhallaShape(String encoded) {
    final decoded = decodePolyline(encoded, accuracyExponent: 6);

    return decoded
        .map((point) => LatLng(point[0].toDouble(), point[1].toDouble()))
        .toList();
  }

  void _showMapContextMenu(
    BuildContext context,
    Offset position,
    LatLng coordinates,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [
        PopupMenuItem(
          child: const Text('Add Marker'),
          onTap: () {
            setState(() {
              _markers.add(
                Marker(
                  point: coordinates,
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.orange,
                    size: 40,
                  ),
                ),
              );
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Marker added at ${coordinates.latitude.toStringAsFixed(4)}, ${coordinates.longitude.toStringAsFixed(4)}',
                ),
              ),
            );
          },
        ),
        PopupMenuItem(
          child: const Text('Startovni bod trasy'),
          onTap: () {
            setState(() {
              _startMarker = Marker(
                point: coordinates,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.green,
                  size: 40,
                ),
              );

              startPointController.text =
                  '${coordinates.latitude.toStringAsFixed(4)}, ${coordinates.longitude.toStringAsFixed(4)}';
            });
          },
        ),
        PopupMenuItem(
          child: const Text('Cílový bod trasy'),
          onTap: () {
            setState(() {
              _endMarker = Marker(
                point: coordinates,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 40,
                ),
              );
            });

            endPointController.text =
                '${coordinates.latitude.toStringAsFixed(4)}, ${coordinates.longitude.toStringAsFixed(4)}';
          },
        ),
        PopupMenuItem(
          child: const Text('Share Location'),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Location: ${coordinates.latitude}, ${coordinates.longitude}',
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      drawer: NavigationDrawer(
        startPointController: startPointController,
        endPointController: endPointController,
        onCalculateRoute: (String mode) async {
          var route = await calc(mode);
          return route;
        },
        export: (String mode) async {
          await export(mode);
        },
        speedSettings: _speedSettings,
      ),
      body: Stack(
        children: [
          GestureDetector(
            onSecondaryTap: () {
              // Consume to prevent default menu
            },
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(49.066, 17.459),
                initialZoom: 16,
                onSecondaryTap: (tapPosition, latLng) {
                  _showMapContextMenu(context, tapPosition.global, latLng);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.myapp',
                ),
                MarkerLayer(markers: _markers),
                MarkerLayer(markers: [_startMarker]),
                MarkerLayer(markers: [_endMarker]),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 4.0,
                        color: Colors.red,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            child: Builder(
              builder: (BuildContext context) {
                return ElevatedButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  child: const Icon(Icons.menu),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class NavigationDrawer extends StatefulWidget {
  final TextEditingController startPointController;
  final TextEditingController endPointController;
  final Function(String) onCalculateRoute;
  final Function(String) export;
  final SpeedSettings speedSettings;

  const NavigationDrawer({
    super.key,
    required this.startPointController,
    required this.endPointController,
    required this.onCalculateRoute,
    required this.export,
    required this.speedSettings,
  });

  @override
  State<NavigationDrawer> createState() => _NavigationDrawerState();
}

class _NavigationDrawerState extends State<NavigationDrawer> {
  String? _selectedTransportMode = 'auto';
  String _exportFormat = 'gpx';

  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _kmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _timeController.text = '';
    _kmController.text = '';
  }

  @override
  void dispose() {
    _timeController.dispose();
    _kmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Drawer(
    child: ListView(
      // Important: Remove any padding from the ListView.
      padding: EdgeInsets.zero,
      children: [
        const DrawerHeader(
          decoration: BoxDecoration(color: Colors.blue),
          child: Text('Navigace'),
        ),
        ListTile(
          title: TextField(
            controller: widget.startPointController,
            decoration: const InputDecoration(
              labelText: 'Počáteční bod trasy: ',
            ),
          ),
          onTap: () {
            // Update the state of the app.
            // ...
          },
        ),
        ListTile(
          title: TextField(
            controller: widget.endPointController,
            decoration: const InputDecoration(labelText: 'Koncový bod trasy: '),
          ),
          onTap: () {
            // Update the state of the app.
            // ...
          },
        ),
        ListTile(
          title: const Text('Mód přepravy:'),
          subtitle: Column(
            children: [
              RadioListTile<String>(
                title: const Text('Automobil'),
                value: 'auto',
                groupValue: _selectedTransportMode,
                onChanged: (value) {
                  setState(() {
                    _selectedTransportMode = value;
                  });
                },
              ),
              RadioListTile<String>(
                title: const Text('Kolo'),
                value: 'bicycle',
                groupValue: _selectedTransportMode,
                onChanged: (value) {
                  setState(() {
                    _selectedTransportMode = value;
                  });
                },
              ),
              RadioListTile<String>(
                title: const Text('Chůze'),
                value: 'pedestrian',
                groupValue: _selectedTransportMode,
                onChanged: (value) {
                  setState(() {
                    _selectedTransportMode = value;
                  });
                },
              ),
            ],
          ),
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Rozšířená nastavení',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        ListTile(
          title: const Text('Průměrná rychlost chůze'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Slider(
                value: widget.speedSettings.walkingSpeed,
                min: 1.0,
                max: 10.0,
                divisions: 90,
                label:
                    '${widget.speedSettings.walkingSpeed.toStringAsFixed(1)} km/h',
                onChanged: (value) {
                  setState(() {
                    widget.speedSettings.walkingSpeed = value;
                  });
                },
              ),
              Text(
                '${widget.speedSettings.walkingSpeed.toStringAsFixed(1)} km/h',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        ListTile(
          title: const Text('Průměrná rychlost kola'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Slider(
                value: widget.speedSettings.cyclingSpeed,
                min: 10.0,
                max: 50.0,
                divisions: 40,
                label:
                    '${widget.speedSettings.cyclingSpeed.toStringAsFixed(1)} km/h',
                onChanged: (value) {
                  setState(() {
                    widget.speedSettings.cyclingSpeed = value;
                  });
                },
              ),
              Text(
                '${widget.speedSettings.cyclingSpeed.toStringAsFixed(1)} km/h',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        const Divider(),
        ListTile(
          title: const Text(
            'Vypočítat trasu',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          onTap: () async {
            try {
              var route = await widget.onCalculateRoute(
                _selectedTransportMode ?? 'auto',
              );
              setState(() {
                _timeController.text =
                    '${(route['trip']['summary']['time'] / 60).toStringAsFixed(1)} min';
                _kmController.text =
                    '${(route['trip']['summary']['length']).toStringAsFixed(2)} km';
              });
            } catch (e) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Chyba: $e')));
            }
          },
        ),
        const Divider(),
        ListTile(
          title: const Text(
            'Délka trasy',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        ListTile(
          title: TextField(
            controller: _timeController,
            readOnly: true,
            decoration: const InputDecoration(labelText: 'Čas'),
          ),
        ),
        ListTile(
          title: TextField(
            controller: _kmController,
            readOnly: true,
            decoration: const InputDecoration(labelText: 'Vzdálenost'),
          ),
        ),
        const Divider(),
        ListTile(
          title: const Text(
            'Export formát',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            children: [
              RadioListTile<String>(
                title: const Text('GPX'),
                value: 'gpx',
                groupValue: _exportFormat,
                onChanged: (value) {
                  setState(() {
                    _exportFormat = value ?? 'gpx';
                  });
                },
              ),
              RadioListTile<String>(
                title: const Text('JSON'),
                value: 'json',
                groupValue: _exportFormat,
                onChanged: (value) {
                  setState(() {
                    _exportFormat = value ?? 'gpx';
                  });
                },
              ),
            ],
          ),
        ),
        ListTile(
          title: ElevatedButton(
            onPressed: () async {
              await widget.export(_selectedTransportMode ?? 'auto');
            },
            child: Text('Exportovat trasu do ${_exportFormat.toUpperCase()}'),
          ),
        ),
      ],
    ),
  );
}
