import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
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

class SharedMarkerData {
  final String id;
  final String name;
  final double latitude;
  final double longitude;

  const SharedMarkerData({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  LatLng get point => LatLng(latitude, longitude);

  factory SharedMarkerData.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return SharedMarkerData(
      id: doc.id,
      name: (data['name'] as String?)?.trim().isNotEmpty == true
          ? (data['name'] as String)
          : 'Marker',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
  final List<SharedMarkerData> _sharedMarkers = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _sharedMarkersSubscription;

  CollectionReference<Map<String, dynamic>> get _sharedMarkersCollection =>
      FirebaseFirestore.instance.collection('shared_markers');

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
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _kmController = TextEditingController();

  String _selectedTransportMode = 'auto';
  String _exportFormat = 'gpx';

  late SpeedSettings _speedSettings;

  @override
  void initState() {
    super.initState();
    _speedSettings = SpeedSettings();
    _listenToSharedMarkers();
  }

  @override
  void dispose() {
    _sharedMarkersSubscription?.cancel();
    startPointController.dispose();
    endPointController.dispose();
    _timeController.dispose();
    _kmController.dispose();
    super.dispose();
  }

  void _listenToSharedMarkers() {
    _sharedMarkersSubscription = _sharedMarkersCollection
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) {
              return;
            }
            setState(() {
              _sharedMarkers
                ..clear()
                ..addAll(
                  snapshot.docs.map(SharedMarkerData.fromDoc).where(
                    (marker) => marker.latitude != 0 || marker.longitude != 0,
                  ),
                );
            });
          },
          onError: (error) {
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Nepodarilo se nacist markery: $error')),
            );
          },
        );
  }

  Future<String?> _showMarkerNameDialog({
    required String title,
    required String actionLabel,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nazev markeru'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Zrusit'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  return;
                }
                Navigator.of(context).pop(value);
              },
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addSharedMarker(LatLng coordinates) async {
    final markerName = await _showMarkerNameDialog(
      title: 'Pojmenovat marker',
      actionLabel: 'Ulozit',
      initialValue: 'Bod',
    );

    if (markerName == null) {
      return;
    }

    await _sharedMarkersCollection.add({
      'name': markerName,
      'latitude': coordinates.latitude,
      'longitude': coordinates.longitude,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Marker "$markerName" byl ulozen')),
    );
  }

  Future<void> _renameSharedMarker(SharedMarkerData marker) async {
    final renamed = await _showMarkerNameDialog(
      title: 'Prejmenovat marker',
      actionLabel: 'Ulozit',
      initialValue: marker.name,
    );

    if (renamed == null || renamed == marker.name) {
      return;
    }

    await _sharedMarkersCollection.doc(marker.id).update({
      'name': renamed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteSharedMarker(SharedMarkerData marker) async {
    await _sharedMarkersCollection.doc(marker.id).delete();

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Marker "${marker.name}" byl smazan')));
  }

  Future<void> _showSharedMarkerActions(SharedMarkerData marker) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(marker.name),
                subtitle: Text(
                  '${marker.latitude.toStringAsFixed(5)}, ${marker.longitude.toStringAsFixed(5)}',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Prejmenovat'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _renameSharedMarker(marker);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Smazat marker'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _deleteSharedMarker(marker);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Marker _buildSharedMarker(SharedMarkerData marker) {
    return Marker(
      point: marker.point,
      width: 120,
      height: 62,
      child: GestureDetector(
        onTap: () => _showSharedMarkerActions(marker),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, color: Colors.orange, size: 36),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                marker.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
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
        html.AnchorElement(href: url)
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
        html.AnchorElement(href: url)
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
          onTap: () async {
            await _addSharedMarker(coordinates);
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
        selectedTransportMode: _selectedTransportMode,
        exportFormat: _exportFormat,
        timeController: _timeController,
        kmController: _kmController,
        onTransportModeChanged: (value) {
          setState(() {
            _selectedTransportMode = value;
          });
        },
        onExportFormatChanged: (value) {
          setState(() {
            _exportFormat = value;
          });
        },
        onCalculateRoute: () async {
          try {
            var route = await calc(_selectedTransportMode);
            setState(() {
              _timeController.text =
                  '${(route['trip']['summary']['time'] / 60).toStringAsFixed(1)} min';
              _kmController.text =
                  '${(route['trip']['summary']['length']).toStringAsFixed(2)} km';
            });
          } catch (e) {
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Chyba: $e')));
          }
        },
        export: () async {
          await export(_selectedTransportMode, exportFormat: _exportFormat);
        },
        speedSettings: _speedSettings,
        onSpeedSettingsChanged: () {
          setState(() {});
        },
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
                MarkerLayer(
                  markers: _sharedMarkers.map(_buildSharedMarker).toList(),
                ),
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

class NavigationDrawer extends StatelessWidget {
  final TextEditingController startPointController;
  final TextEditingController endPointController;
  final TextEditingController timeController;
  final TextEditingController kmController;
  final String selectedTransportMode;
  final String exportFormat;
  final ValueChanged<String> onTransportModeChanged;
  final ValueChanged<String> onExportFormatChanged;
  final Future<void> Function() onCalculateRoute;
  final Future<void> Function() export;
  final SpeedSettings speedSettings;
  final VoidCallback onSpeedSettingsChanged;

  const NavigationDrawer({
    super.key,
    required this.startPointController,
    required this.endPointController,
    required this.timeController,
    required this.kmController,
    required this.selectedTransportMode,
    required this.exportFormat,
    required this.onTransportModeChanged,
    required this.onExportFormatChanged,
    required this.onCalculateRoute,
    required this.export,
    required this.speedSettings,
    required this.onSpeedSettingsChanged,
  });

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
            controller: startPointController,
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
            controller: endPointController,
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
                groupValue: selectedTransportMode,
                onChanged: (value) {
                  if (value != null) {
                    onTransportModeChanged(value);
                  }
                },
              ),
              RadioListTile<String>(
                title: const Text('Kolo'),
                value: 'bicycle',
                groupValue: selectedTransportMode,
                onChanged: (value) {
                  if (value != null) {
                    onTransportModeChanged(value);
                  }
                },
              ),
              RadioListTile<String>(
                title: const Text('Chůze'),
                value: 'pedestrian',
                groupValue: selectedTransportMode,
                onChanged: (value) {
                  if (value != null) {
                    onTransportModeChanged(value);
                  }
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
                value: speedSettings.walkingSpeed,
                min: 1.0,
                max: 10.0,
                divisions: 90,
                label:
                    '${speedSettings.walkingSpeed.toStringAsFixed(1)} km/h',
                onChanged: (value) {
                  speedSettings.walkingSpeed = value;
                  onSpeedSettingsChanged();
                },
              ),
              Text(
                '${speedSettings.walkingSpeed.toStringAsFixed(1)} km/h',
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
                value: speedSettings.cyclingSpeed,
                min: 10.0,
                max: 50.0,
                divisions: 40,
                label:
                    '${speedSettings.cyclingSpeed.toStringAsFixed(1)} km/h',
                onChanged: (value) {
                  speedSettings.cyclingSpeed = value;
                  onSpeedSettingsChanged();
                },
              ),
              Text(
                '${speedSettings.cyclingSpeed.toStringAsFixed(1)} km/h',
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
            await onCalculateRoute();
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
            controller: timeController,
            readOnly: true,
            decoration: const InputDecoration(labelText: 'Čas'),
          ),
        ),
        ListTile(
          title: TextField(
            controller: kmController,
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
                groupValue: exportFormat,
                onChanged: (value) {
                  if (value != null) {
                    onExportFormatChanged(value);
                  }
                },
              ),
              RadioListTile<String>(
                title: const Text('JSON'),
                value: 'json',
                groupValue: exportFormat,
                onChanged: (value) {
                  if (value != null) {
                    onExportFormatChanged(value);
                  }
                },
              ),
            ],
          ),
        ),
        ListTile(
          title: ElevatedButton(
            onPressed: () async {
              await export();
            },
            child: Text('Exportovat trasu do ${exportFormat.toUpperCase()}'),
          ),
        ),
      ],
    ),
  );
}
