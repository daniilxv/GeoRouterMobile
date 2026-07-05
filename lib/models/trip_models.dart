import 'package:flutter/material.dart';

class Trip {
  final int id;
  final int userId;
  final String name;
  final DateTime createdAt;
  final List<Day> days;

  Trip({
    required this.id,
    required this.userId,
    required this.name,
    required this.createdAt,
    required this.days,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'],
      userId: json['user'],
      name: json['name'],
      createdAt: DateTime.parse(json['created_at']),
      days: (json['days'] as List?)
          ?.map((dayJson) => Day.fromJson(dayJson))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user': userId,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'days': days.map((day) => day.toJson()).toList(),
    };
  }
}

class Day {
  final int id;
  final int trip;
  final DateTime date;
  final String? color;
  final String? comment;
  final String? geometry;
  final List<Waypoint> waypoints;

  Day({
    required this.id,
    required this.trip,
    required this.date,
    this.color,
    this.comment,
    this.geometry,
    required this.waypoints,
  });

  factory Day.fromJson(Map<String, dynamic> json) {
    return Day(
      id: json['id'],
      trip: json['trip'],
      date: DateTime.parse(json['date']),
      color: json['color'],
      comment: json['comment'],
      geometry: json['geometry'],
      waypoints: (json['waypoints'] as List)
          .map((wpJson) => Waypoint.fromJson(wpJson))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trip': trip,
      'date': date.toIso8601String().split('T')[0],
      'color': color,
      'comment': comment,
      'geometry': geometry,
      'waypoints': waypoints.map((wp) => wp.toJson()).toList(),
    };
  }
}

class Waypoint {
  final int id;
  final int day;
  final double lat;
  final double lon;
  final int order;
  final String? comment;
  final bool isRefuel;

  Waypoint({
    required this.id,
    required this.day,
    required this.lat,
    required this.lon,
    required this.order,
    this.comment,
    required this.isRefuel,
  });

  factory Waypoint.fromJson(Map<String, dynamic> json) {
    return Waypoint(
      id: json['id'],
      day: json['day'],
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      order: json['order'],
      comment: json['comment'],
      isRefuel: json['is_refuel'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'day': day,
      'lat': lat,
      'lon': lon,
      'order': order,
      'comment': comment,
      'is_refuel': isRefuel,
    };
  }
}
