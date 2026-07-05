import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import '../api/trip_provider.dart';
import '../models/trip_models.dart';

class MapScreen extends StatefulWidget {
  final int tripId;
  const MapScreen({super.key, required this.tripId});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Trip? _trip;
  late ValueNotifier<Day?> _selectedDayNotifier;
  bool _isLoading = true;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _selectedDayNotifier = ValueNotifier<Day?>(null);
    _loadTrip();
  }

  Future<void> _loadTrip() async {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    final trip = await tripProvider.fetchTripDetails(widget.tripId);
    setState(() {
      _trip = trip;
      if (_trip != null && _trip!.days.isNotEmpty) {
        _selectedDayNotifier.value = _trip!.days.first;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _zoomToTrip();
        });
      }
      _isLoading = false;
    });
  }

  void _zoomToTrip() {
    if (_trip == null || _trip!.days.isEmpty) return;

    final allPoints = _trip!.days
        .expand((day) => day.waypoints)
        .map((wp) => LatLng(wp.lat, wp.lon))
        .toList();

    if (allPoints.isEmpty) return;

    final bounds = LatLngBounds.fromPoints(allPoints);
    _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50.0)));
  }

  List<Marker> _getMarkers(Day? selectedDay) {
    if (_trip == null) return [];

    List<Marker> markers = [];
    for (var day in _trip!.days) {
      final isSelected = day == selectedDay;
      final dayColor = day.color != null
          ? Color(int.parse(day.color!.replaceFirst('#', '0xff')))
          : Colors.blue;

      markers.addAll(day.waypoints.map<Marker>((wp) {
        return Marker(
          point: LatLng(wp.lat, wp.lon),
          width: isSelected ? 80 : 40,
          height: isSelected ? 80 : 40,
          child: Icon(
            wp.isRefuel ? Icons.local_gas_station : Icons.location_on,
            color: isSelected ? dayColor : dayColor.withOpacity(0.4),
            size: isSelected ? 30 : 20,
          ),
        );
      }).toList());
    }
    return markers;
  }

  List<Polyline> _getPolylines(Day? selectedDay) {
    if (_trip == null) return [];

    List<Polyline> polylines = [];
    for (var day in _trip!.days) {
      final isSelected = day == selectedDay;
      final dayColor = day.color != null
          ? Color(int.parse(day.color!.replaceFirst('#', '0xff')))
          : Colors.blue;

      List<LatLng> points = [];
      if (day.geometry != null && day.geometry!.isNotEmpty) {
        try {
          final geometryData = jsonDecode(day.geometry!);
          final coordinates = geometryData['coordinates'] as List;
          points = coordinates.map((coord) {
            final c = coord as List;
            return LatLng(c[1] as double, c[0] as double);
          }).toList();
        } catch (e) {
          debugPrint('Error parsing geometry: $e');
          points = day.waypoints.map((wp) => LatLng(wp.lat, wp.lon)).toList();
        }
      } else {
        points = day.waypoints.map((wp) => LatLng(wp.lat, wp.lon)).toList();
      }

      if (points.length >= 2) {
        polylines.add(
          Polyline(
            points: points,
            color: isSelected ? dayColor : dayColor.withOpacity(0.3),
            strokeWidth: isSelected ? 5.0 : 3.0,
          ),
        );
      }
    }
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_trip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ошибка')),
        body: const Center(
            child: Text('Не удалось загрузить данные путешествия')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_trip!.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Скачать область',
            onPressed: _downloadCurrentView,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: Implement trip settings
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(55.75, 37.61),
              initialZoom: 10,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.georouter.app',
                tileProvider: FMTCStore('osm').getTileProvider(),
              ),
              ValueListenableBuilder<Day?>(
                valueListenable: _selectedDayNotifier,
                builder: (context, selectedDay, child) {
                  return Stack(
                    children: [
                      PolylineLayer(polylines: _getPolylines(selectedDay)),
                      MarkerLayer(markers: _getMarkers(selectedDay)),
                    ],
                  );
                },
              ),
            ],
          ),
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: _buildDayDetails(),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: _buildDaySelector(),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadCurrentView() async {
    final bounds = _mapController.camera.visibleBounds;

    try {
      // Start downloading the current visible area
      // Zoom range 12-18 is usually sufficient for route navigation
      final region = RectangleRegion(bounds).toDownloadable(
        minZoom: 12,
        maxZoom: 18,
        options: TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.georouter.app',
        ),
      );
      final downloadStream = FMTCStore('osm').download.startForeground(
          region: region);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Началась загрузка области карты...')),
      );

      // Listen to progress
      await for (final progress in downloadStream) {
        debugPrint('Download progress: ${progress.percentageProgress}%');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Область карты успешно загружена!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при загрузке карты: $e')),
      );
    }
  }

  Widget _buildDayDetails() {
    return ValueListenableBuilder<Day?>(
      valueListenable: _selectedDayNotifier,
      builder: (context, selectedDay, child) {
        if (selectedDay == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(15),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('dd MMMM yyyy').format(selectedDay!.date),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (selectedDay!.color != null)
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Color(int.parse(selectedDay!.color!
                            .replaceFirst('#', '0xff'))),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                selectedDay!.comment ?? 'Нет комментария к этому дню',
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 12),
              const Text(
                'Точки маршрута:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              ...selectedDay!.waypoints.map((wp) =>
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          wp.isRefuel ? Icons.local_gas_station : Icons
                              .location_on,
                          size: 16,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            wp.comment ?? 'Без названия',
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDaySelector() {
    return ValueListenableBuilder<Day?>(
        valueListenable: _selectedDayNotifier,
        builder: (context, selectedDay, child) {
          return Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _trip!.days.length,
              itemBuilder: (context, index) {
                final day = _trip!.days[index];
                final isSelected = selectedDay == day;
                return GestureDetector(
                  onTap: () => _selectedDayNotifier.value = day,
                  child: Container(
                    width: 80,
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue : Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: day.color != null
                            ? Color(int.parse(
                            day.color!.replaceFirst('#', '0xff')))
                            : Colors.blue,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('dd MMM').format(day.date),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black,
                          ),
                        ),
                        Text(
                          DateFormat('EEEE').format(day.date),
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        }
    );
  }
}