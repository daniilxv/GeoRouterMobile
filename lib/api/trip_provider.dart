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

  Future<void> fetchTrips() async {
    _error = null;
    
    // 1. Load from local cache immediately for instant availability
    try {
      _trips = await dbHelper.getAllTrips();
      notifyListeners();
    } catch (e) {
      print('Error loading from local cache: $e');
    }

    // 2. Fetch fresh data from server in the background
    _isLoading = true;
    notifyListeners();

    try {
      final response = await apiClient.get('/api/trips/');
      final List<dynamic> data = response as List<dynamic>;
      _trips = data.map((json) => Trip.fromJson(json)).toList();
      
      // Update local cache
      await dbHelper.saveTrips(_trips);
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
      await apiClient.post('/api/trips/', {'name': name});
      await fetchTrips();
      return true;
    } catch (e) {
      _error = 'Failed to create trip: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteTrip(int id) async {
    try {
      await apiClient.delete('/api/trips/$id/');
      _trips.removeWhere((trip) => trip.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to delete trip: $e';
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
