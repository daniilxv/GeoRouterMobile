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
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiClient.get('/api/trips/');
      final List<dynamic> data = response as List<dynamic>;
      _trips = data.map((json) => Trip.fromJson(json)).toList();
      
      // Cache trips locally
      await dbHelper.saveTrips(_trips);
    } catch (e) {
      try {
        // Try to load from local DB if API fails
        _trips = await dbHelper.getAllTrips();
        if (_trips.isEmpty) {
          _error = 'No internet connection and no cached data available.';
        }
      } catch (dbError) {
        _error = 'Failed to load trips: $e';
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
    try {
      final response = await apiClient.get('/api/trips/$id/');
      final trip = Trip.fromJson(response);
      await dbHelper.saveTrip(trip);
      return trip;
    } catch (e) {
      print('Error fetching trip details from API: $e. Trying local cache...');
      try {
        return await dbHelper.getTrip(id);
      } catch (dbError) {
        print('Error fetching trip details from local DB: $dbError');
        return null;
      }
    }
  }
}
