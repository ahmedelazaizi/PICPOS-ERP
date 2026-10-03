import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Location permission as the app needs it.
enum GeoPermission { granted, denied, deniedForever, serviceOff }

/// One GPS fix.
class GeoFix {
  const GeoFix({required this.lat, required this.lng, required this.accuracy, required this.at});
  final double lat, lng, accuracy;
  final DateTime at;
}

/// Platform location access (fake in tests).
abstract class GeoProvider {
  Future<GeoPermission> permission();

  /// Shows the OS permission prompt (call only after the in-app rationale).
  Future<GeoPermission> request();

  /// A fix within [timeout], or null when none came in time.
  Future<GeoFix?> currentFix(Duration timeout);
}

/// Owner decision K-3: stamps documents and visits with lat/lng/accuracy/time.
/// Never asks for permission itself (the UI shows the rationale first) and
/// never blocks longer than [timeout]: without a fix the document is saved
/// with the reason (`denied` / `timeout` / `unavailable`).
class GeoCapture {
  GeoCapture(this.provider, {this.timeout = const Duration(seconds: 8)});
  final GeoProvider provider;
  final Duration timeout;

  /// Wire form of the stamp (`geo` of a pushed document).
  Future<Map<String, Object?>> stamp() async {
    try {
      switch (await provider.permission()) {
        case GeoPermission.denied:
        case GeoPermission.deniedForever:
          return {'status': 'denied'};
        case GeoPermission.serviceOff:
          return {'status': 'unavailable'};
        case GeoPermission.granted:
          break;
      }
      final fix = await provider.currentFix(timeout).timeout(timeout + const Duration(seconds: 1));
      if (fix == null) return {'status': 'timeout'};
      return {
        'status': 'ok',
        'lat': fix.lat,
        'lng': fix.lng,
        'accuracy': fix.accuracy,
        'at': fix.at.toUtc().toIso8601String(),
      };
    } on TimeoutException {
      return {'status': 'timeout'};
    } catch (_) {
      return {'status': 'unavailable'};
    }
  }
}

/// `geolocator` on the device. A last known fix younger than [maxAge] is used
/// at once (saving a sale must not wait for a cold GPS start).
class DeviceGeoProvider implements GeoProvider {
  DeviceGeoProvider({this.maxAge = const Duration(minutes: 2)});
  final Duration maxAge;

  static GeoPermission _map(LocationPermission p) => switch (p) {
        LocationPermission.always || LocationPermission.whileInUse => GeoPermission.granted,
        LocationPermission.deniedForever => GeoPermission.deniedForever,
        _ => GeoPermission.denied,
      };

  @override
  Future<GeoPermission> permission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return GeoPermission.serviceOff;
    return _map(await Geolocator.checkPermission());
  }

  @override
  Future<GeoPermission> request() async => _map(await Geolocator.requestPermission());

  @override
  Future<GeoFix?> currentFix(Duration timeout) async {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && DateTime.now().difference(last.timestamp) <= maxAge) return _fix(last);
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeout),
      );
      return _fix(p);
    } on TimeoutException {
      return null;
    }
  }

  static GeoFix _fix(Position p) =>
      GeoFix(lat: p.latitude, lng: p.longitude, accuracy: p.accuracy, at: p.timestamp);
}
