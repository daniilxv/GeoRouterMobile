import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'api/api_client.dart';
import 'api/auth_provider.dart';
import 'api/trip_provider.dart';
import 'api/local_db_helper.dart';
import 'screens/login_screen.dart';
import 'screens/trip_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database factory for desktop/ffi
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize FMTC
  await FMTCObjectBoxBackend().initialise();
  
  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>(
          create: (_) => ApiClient(baseUrl: 'http://192.168.0.186:8000'), // 10.0.2.2 is localhost for Android emulator
        ),
        ChangeNotifierProvider(
          create: (context) => AuthProvider(
            apiClient: Provider.of<ApiClient>(context, listen: false),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => TripProvider(
            apiClient: Provider.of<ApiClient>(context, listen: false),
            dbHelper: LocalDatabaseHelper.instance,
          ),
        ),
      ],
      child: const GeoRouterApp(),
    ),
  );
}

class GeoRouterApp extends StatelessWidget {
  const GeoRouterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoRouter',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: Consumer<AuthProvider>(
        builder: (context, auth, child) {
          if (auth.isAuthenticated) {
            return const TripListScreen();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
