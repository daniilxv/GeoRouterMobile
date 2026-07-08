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

    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        trip_id INTEGER,
        data TEXT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
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

  Future<void> saveTrips(List<Trip> trips) async {
    final db = await instance.database;
    final batch = db.batch();
    
    for (var trip in trips) {
      batch.insert(
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
    
    await batch.commit(noResult: true);
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

  Future<void> updateTripId(int oldId, Trip newTrip) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('trips', where: 'id = ?', whereArgs: [oldId]);
      await txn.insert(
        'trips',
        {
          'id': newTrip.id,
          'name': newTrip.name,
          'user_id': newTrip.userId,
          'data': jsonEncode(newTrip.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> clearAllTrips() async {
    final db = await instance.database;
    await db.delete('trips');
  }

  Future<void> addToSyncQueue(String action, {int? tripId, String? data}) async {
    final db = await instance.database;
    await db.insert('sync_queue', {
      'action': action,
      'trip_id': tripId,
      'data': data,
    });
  }

  Future<List<Map<String, dynamic>>> getSyncQueue() async {
    final db = await instance.database;
    return await db.query('sync_queue', orderBy: 'timestamp ASC');
  }

  Future<void> removeFromSyncQueue(int id) async {
    final db = await instance.database;
    await db.delete(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
