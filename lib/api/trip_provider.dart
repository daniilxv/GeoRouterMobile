import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_client.dart';
import '../models/trip_models.dart';
import 'local_db_helper.dart';

class TripProvider with ChangeNotifier {
  final ApiClient apiClient;
  final LocalDatabaseHelper dbHelper;
  List<Trip> _trips = [];
  bool _isLoading = false;
  String? _error;

  TripProvider({required this.apiClient, required this.dbHelper});

  List<Trip> get trips => _trips;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> syncPendingChanges() async {
    final queue = await dbHelper.getSyncQueue();
    if (queue.isEmpty) return;

    for (var item in queue) {
      final id = item['id'] as int;
      final action = item['action'] as String;
      final tripId = item['trip_id'] as int?;
      final data = item['data'] as String?;

      try {
        if (action == 'CREATE' && data != null) {
          final response = await apiClient.post('/api/trips/', jsonDecode(data) as Map<String, dynamic>);
          final serverTrip = Trip.fromJson(response);
          
          if (tripId != null) {
            await dbHelper.updateTripId(tripId, serverTrip);
          }
        } else if (action == 'DELETE' && tripId != null) {
          await apiClient.delete('/api/trips/$tripId/');
        }
        
        // Remove from queue after successful sync
        await dbHelper.removeFromSyncQueue(id);
      } catch (e) {
        print('Sync failed for item $id: $e');
        // Stop processing queue if we hit a network error
        break;
      }
    }
  }

  Future<void> fetchTrips() async {
    _error = null;

    // 1. Load from local cache immediately for instant availability
    try {
      _trips = await dbHelper.getAllTrips();
      notifyListeners();
    } catch (e) {
      print('Error loading from local cache: $e');
    }

    // 2. Sync pending changes and fetch fresh data from server in the background
    await syncPendingChanges();

    // 2. Fetch fresh data from server in the background
    _isLoading = true;
    notifyListeners();

    try {
      final response = await apiClient.get('/api/trips/');
      final List<dynamic> data = response as List<dynamic>;
      final serverTrips = data.map((json) => Trip.fromJson(json)).toList();
      
      // Update local cache with server trips
      await dbHelper.saveTrips(serverTrips);
      
      // Merge server trips with local trips that aren't on the server yet
      final allLocalTrips = await dbHelper.getAllTrips();
      final serverIds = serverTrips.map((t) => t.id).toSet();
      
      _trips = [...serverTrips];
      for (var localTrip in allLocalTrips) {
        if (!serverIds.contains(localTrip.id)) {
          _trips.add(localTrip);
        }
      }
    } catch (e) {
      if (_trips.isEmpty) {
        _error = 'No internet connection and no cached data available.';
      } else {
        // If we have cached data, we don't show a hard error,
        // maybe just a toast or a small indicator that data is offline.
        print('Server fetch failed, using cached data: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createTrip(String name) async {
    try {
      // 1. Create a temporary trip for local display
      final tempId = DateTime.now().millisecondsSinceEpoch;
      final tempTrip = Trip(
        id: tempId,
        name: name,
        userId: 0, // Will be updated by server
        createdAt: DateTime.now(),
        days: [],
      );

      // 2. Save locally immediately
      await dbHelper.saveTrip(tempTrip);
      _trips.add(tempTrip);
      notifyListeners();

      // 3. Add to sync queue
      await dbHelper.addToSyncQueue('CREATE', tripId: tempId, data: jsonEncode({'name': name}));

      // 4. Try to sync in background
      syncPendingChanges().catchError((e) => print('Background sync error: $e'));

      return true;
    } catch (e) {
      _error = 'Failed to create trip locally: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteTrip(int id) async {
    try {
      // 1. Remove locally immediately
      await dbHelper.deleteTrip(id);
      _trips.removeWhere((trip) => trip.id == id);
      notifyListeners();

      // 2. Add to sync queue
      await dbHelper.addToSyncQueue('DELETE', tripId: id);

      // 3. Try to sync in background
      syncPendingChanges().catchError((e) => print('Background sync error: $e'));

      return true;
    } catch (e) {
      _error = 'Failed to delete trip locally: $e';
      notifyListeners();
      return false;
    }
  }

  Future<Trip?> fetchTripDetails(int id) async {
    // 1. Try to get from local cache first for instant load
    Trip? cachedTrip = await dbHelper.getTrip(id);
    
    // If we have a cached trip, we can return it immediately,
    // but we should still try to update it from the server.
    // However, since this method is awaited in MapScreen's initState,
    // we have two options:
    // a) Return cachedTrip immediately and handle server update separately.
    // b) Wait for server, but if it fails, return cachedTrip.
    
    // To avoid the "infinite loader", we can't just await the API call if we want instant load.
    // But MapScreen expects a Trip? return value.
    
    // Let's implement a "cache-first" approach:
    try {
      final response = await apiClient.get('/api/trips/$id/');
      final trip = Trip.fromJson(response);
      await dbHelper.saveTrip(trip);
      return trip;
    } catch (e) {
      print('Error fetching trip details from API: $e. Using cached data.');
      return cachedTrip;
    }
  }
}
