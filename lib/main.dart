import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'valhalla_service.dart';
import 'package:universal_html/html.dart' as html;
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';

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
  final MapController _mapController = MapController();
  List<LatLng> _routePoints = [];

  final TextEditingController startPointController = TextEditingController();
  final TextEditingController endPointController = TextEditingController();

  calc(String mode) async {
    final valhalla = ValhallaService();

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
      profileOptions: {
        "cycling_speed": 22.0,
        "use_roads": 0.3,
        "use_trails": 0.8,
      },
    );

    print("Distance: ${route['trip']['summary']['length']} km");
    print("Time: ${route['trip']['summary']['time'] / 60} minutes");
    String encodedShape = route['trip']['legs'][0]['shape'];
    setState(() {
      _routePoints = decodeValhallaShape(encodedShape);
    });
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
                    color: Colors.red,
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
            startPointController.text =
                '${coordinates.latitude.toStringAsFixed(4)}, ${coordinates.longitude.toStringAsFixed(4)}';
          },
        ),
        PopupMenuItem(
          child: const Text('Cílový bod trasy'),
          onTap: () {
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
        onCalculateRoute: (String mode) => calc(mode),
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

  const NavigationDrawer({
    super.key,
    required this.startPointController,
    required this.endPointController,
    required this.onCalculateRoute,
  });

  @override
  State<NavigationDrawer> createState() => _NavigationDrawerState();
}

class _NavigationDrawerState extends State<NavigationDrawer> {
  String? _selectedTransportMode = 'Automobil';

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
        ListTile(
          title: const Text('Vypočítat trasu'),
          onTap: () {
            widget.onCalculateRoute(_selectedTransportMode ?? 'auto');
          },
        ),
      ],
    ),
  );
}
