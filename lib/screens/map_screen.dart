import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../api/offline_map_helper.dart';
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
  MapLibreMapController? _mapController;
  bool _isStyleLoaded = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  bool _cancelDownload = false;

  @override
  @override
  void initState() {
    super.initState();
    debugPrint('MapScreen: initState called');
    _selectedDayNotifier = ValueNotifier<Day?>(null);
    _loadTrip();
  }

  Future<void> _loadTrip() async {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    
    // 1. Try to load from cache first for instant display
    final cachedTrip = await tripProvider.dbHelper.getTrip(widget.tripId);
    if (cachedTrip != null) {
      setState(() {
        _trip = cachedTrip;
        if (_trip!.days.isNotEmpty) {
          _selectedDayNotifier.value = _trip!.days.first;
        }
        _isLoading = false;
      });
    }

    // 2. Fetch fresh data from server in the background
    try {
      final trip = await tripProvider.fetchTripDetails(widget.tripId);
      setState(() {
        _trip = trip;
        if (_trip != null && _trip!.days.isNotEmpty) {
          _selectedDayNotifier.value = _trip!.days.first;
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error updating trip from server: $e');
      setState(() {
        _isLoading = false;
      });
    }
  
    @override
    void dispose() {
      debugPrint('MapScreen: dispose called');
      _selectedDayNotifier.dispose();
      super.dispose();
    }
  }


  void _onMapCreated(MapLibreMapController controller) {
    debugPrint('MapLibre: [${DateTime.now()}] Map created');
    _mapController = controller;
  }

  void _onStyleLoaded() {
    debugPrint('MapLibre: [${DateTime.now()}] Style loaded successfully');
    setState(() {
      _isStyleLoaded = true;
    });
    _updateMapLayers();
    _zoomToTrip();
  }

  Future<void> _clearLayers() async {
    if (_mapController == null) return;
    // In maplibre_gl flutter plugin, addSymbol and addLine create internal layers.
    // There is no simple way to clear them all.
    // For now, we rely on the fact that _updateMapLayers is called sparingly.
  }

  void _zoomToTrip() {
    if (_trip == null || _trip!.days.isEmpty || _mapController == null) return;

    final allPoints = _trip!.days
        .expand((day) => day.waypoints)
        .map((wp) => LatLng(wp.lat, wp.lon))
        .toList();

    if (allPoints.isEmpty) return;

    // Calculate bounds
    double minLon = allPoints.first.longitude;
    double maxLon = allPoints.first.longitude;
    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;

    for (var p in allPoints) {
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
    }

    _mapController!.setCameraBounds(
      north: maxLat,
      south: minLat,
      east: maxLon,
      west: minLon,
      padding: 50,
    );
  }

  Future<void> _updateMapLayers() async {
    debugPrint('MapLibre: [${DateTime.now()}] Updating map layers...');
    if (_mapController == null || _trip == null || !_isStyleLoaded) {
      debugPrint('MapLibre: Update aborted - controller: $_mapController, trip: $_trip, styleLoaded: $_isStyleLoaded');
      return;
    }

    // We avoid calling _clearLayers() because addSymbol/addLine
    // in this plugin don't provide a way to clear them.
    // To avoid duplication, we only call this when necessary.

    final selectedDay = _selectedDayNotifier.value;

    for (var day in _trip!.days) {
      final isSelected = day == selectedDay;
      final dayColor = day.color != null
          ? Color(int.parse(day.color!.replaceFirst('#', '0xff')))
          : Colors.blue;

      // Add Waypoints
      debugPrint('MapLibre: Adding ${day.waypoints.length} waypoints for day ${day.date}');
      for (var wp in day.waypoints) {
        await _mapController!.addSymbol(
          SymbolOptions(
            geometry: LatLng(wp.lat, wp.lon),
            iconImage: wp.isRefuel ? 'gas-station' : 'location-pin',
            iconSize: isSelected ? 1.5 : 1.0,
            textField: wp.comment,
            textOffset: const Offset(0, 10),
          ),
        );
      }

      // Add Route
      List<LatLng> points = [];
      if (day.geometry != null && day.geometry!.isNotEmpty) {
        try {
          final geometryData = jsonDecode(day.geometry!);
          final coordinates = geometryData['coordinates'] as List;
          points = coordinates.map((coord) {
            final c = coord as List;
            return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
          }).toList();
        } catch (e) {
          debugPrint('Error parsing geometry: $e');
          points = day.waypoints.map((wp) => LatLng(wp.lat, wp.lon)).toList();
        }
      } else {
        points = day.waypoints.map((wp) => LatLng(wp.lat, wp.lon)).toList();
      }

      if (points.length >= 2) {
        await _mapController!.addLine(
          LineOptions(
            geometry: points,
            lineColor: isSelected
                ? '#${dayColor.value.toRadixString(16).substring(2).toUpperCase()}'
                : '#${dayColor.withOpacity(0.3).value.toRadixString(16).substring(2).toUpperCase()}',
            lineWidth: isSelected ? 5.0 : 3.0,
          ),
        );
      }
    }
    debugPrint('MapLibre: [${DateTime.now()}] Map layers update completed');
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('MapScreen: build called at ${DateTime.now()}');
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
          _isDownloading
            ? SizedBox(
                width: 48,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: _downloadProgress,
                    ),
                  ),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.download_for_offline),
                tooltip: 'Скачать область',
                onPressed: _downloadCurrentView,
              ),
            IconButton(
              icon: const Icon(Icons.route),
              tooltip: 'Кэшировать весь маршрут',
              onPressed: _downloadTripRoute,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить карту',
            onPressed: () {
              _updateMapLayers();
              _zoomToTrip();
            },
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
          if (_isDownloading)
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.downloading, size: 20, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Загрузка карты... ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: _downloadProgress,
                                minHeight: 4,
                                backgroundColor: Colors.grey[300],
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _cancelDownload = true;
                          });
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Отмена', style: TextStyle(color: Colors.red, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          MapLibreMap(
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            initialCameraPosition: const CameraPosition(
              target: LatLng(55.75, 37.61),
              zoom: 10,
            ),
            styleString: OfflineMapHelper.defaultStyleUrl
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

  LatLngBounds _calculateTripBounds() {
    if (_trip == null || _trip!.days.isEmpty) {
      return LatLngBounds(
        southwest: LatLng(0, 0),
        northeast: LatLng(0, 0),
      );
    }

    final allPoints = _trip!.days
        .expand((day) => day.waypoints)
        .map((wp) => LatLng(wp.lat, wp.lon))
        .toList();

    if (allPoints.isEmpty) {
      return  LatLngBounds(
        southwest: LatLng(0, 0),
        northeast: LatLng(0, 0),
      );
    }

    double minLon = allPoints.first.longitude;
    double maxLon = allPoints.first.longitude;
    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;

    for (var p in allPoints) {
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLon),
      northeast: LatLng(maxLat, maxLon),
    );
  }

  Future<void> _downloadTripRoute() async {
    final bounds = _calculateTripBounds();
    if (bounds.southwest.latitude == 0 && bounds.southwest.longitude == 0) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _cancelDownload = false;
    });

    try {
      await OfflineMapHelper.downloadRegion(
        bounds: bounds,
        minZoom: 10, // Lower zoom for the whole route to avoid too many tiles
        maxZoom: 14, // Moderate zoom for route overview
        onProgress: (progress) {
          setState(() {
            _downloadProgress = progress;
          });
        },
        onCancel: () => _cancelDownload,
      );

      if (!_cancelDownload) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Весь маршрут успешно закэширован!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Загрузка отменена')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при загрузке маршрута: $e')),
      );
    } finally {
      setState(() {
        _isDownloading = false;
        _cancelDownload = false;
      });
    }
  }

  Future<void> _downloadCurrentView() async {
    if (_mapController == null) return;

    final bounds = await _mapController!.getVisibleRegion();
    
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _cancelDownload = false;
    });

    try {
      await OfflineMapHelper.downloadRegion(
        bounds: bounds,
        minZoom: 12,
        maxZoom: 16,
        onProgress: (progress) {
          setState(() {
            _downloadProgress = progress;
          });
        },
        onCancel: () => _cancelDownload,
      );
      
      if (!_cancelDownload) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Область карты успешно закэширована!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Загрузка отменена')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при загрузке карты: $e')),
      );
    } finally {
      setState(() {
        _isDownloading = false;
        _cancelDownload = false;
      });
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
                  onTap: () {
                    _selectedDayNotifier.value = day;
                    _updateMapLayers();
                  },
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
