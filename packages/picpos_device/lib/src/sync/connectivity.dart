import 'package:connectivity_plus/connectivity_plus.dart';

/// Network reachability as schedulers need it (from
/// mobile/lib/sync/sync_scheduler.dart).
abstract class ConnectivitySource {
  Future<bool> isOnline();
  Stream<bool> get changes;
}

/// `connectivity_plus`: online when any transport other than `none` is up
/// (a captive or dead network still fails the request and backs off).
class PlusConnectivity implements ConnectivitySource {
  PlusConnectivity([Connectivity? c]) : _c = c ?? Connectivity();
  final Connectivity _c;
  static bool _up(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async => _up(await _c.checkConnectivity());
  @override
  Stream<bool> get changes => _c.onConnectivityChanged.map(_up);
}
