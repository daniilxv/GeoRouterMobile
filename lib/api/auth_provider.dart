import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class AuthProvider with ChangeNotifier {
  final ApiClient apiClient;
  String? _token;
  bool _isAuthenticated = false;

  AuthProvider({required this.apiClient}) {
    _loadToken();
  }

  String? get token => _token;
  bool get isAuthenticated => _isAuthenticated;

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    if (_token != null) {
      apiClient.setToken(_token!);
      _isAuthenticated = true;
    }
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    try {
      final response = await apiClient.post('/api/obtain-token/', {
        'username': username,
        'password': password,
      });

      _token = response['token'];
      apiClient.setToken(_token!);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', _token!);
      
      _isAuthenticated = true;
      notifyListeners();
      return true;
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  Future<bool> signup(String username, String email, String password) async {
    try {
      await apiClient.post('/signup/', {
        'username': username,
        'email': email,
        'password': password,
      });
      return true;
    } catch (e) {
      print('Signup error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    apiClient.clearToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    _isAuthenticated = false;
    notifyListeners();
  }
}
