import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/trip_models.dart';
import 'dart:convert';

class LocalDatabaseHelper {
  static final LocalDatabaseHelper instance = LocalDatabaseHelper._init();
  static Database? _database;

  LocalDatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('trips.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE trips (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        user_id INTEGER NOT NULL,
        data TEXT NOT NULL
      )
    ''');
  }

  Future<void> saveTrip(Trip trip) async {
    final db = await instance.database;
    
    // We store the entire Trip object as JSON in the 'data' column
    // to simplify the caching of nested Days and Waypoints.
    await db.insert(
      'trips',
      {
        'id': trip.id,
        'name': trip.name,
        'user_id': trip.userId,
        'data': jsonEncode(trip.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }



  Future<List<Trip>> getAllTrips() async {
    final db = await instance.database;
    final result = await db.query('trips');

    return result.map((json) {
      final tripData = jsonDecode(json['data'] as String);
      return Trip.fromJson(tripData);
    }).toList();
  }

  Future<Trip?> getTrip(int id) async {
    final db = await instance.database;
    final maps = await db.query(
      'trips',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      final tripData = jsonDecode(maps.first['data'] as String);
      return Trip.fromJson(tripData);
    }
    return null;
  }

  Future<void> deleteTrip(int id) async {
    final db = await instance.database;
    await db.delete(
      'trips',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAllTrips() async {
    final db = await instance.database;
    await db.delete('trips');
  }
}
