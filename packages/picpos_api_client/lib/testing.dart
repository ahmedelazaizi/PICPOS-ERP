/// Fakes for app and package tests (no network).
library;

import 'dart:async';

import 'src/api_error.dart';
import 'src/transport.dart';

typedef FakeHandler = FutureOr<ApiResponse> Function(ApiRequest request);

/// Records requests and answers with [handler] (default: `200 {}`).
/// Set [failWith] to make every call throw.
class FakeTransport implements ApiTransport {
  FakeTransport(this.kind, {Uri? baseUri, this.handler}) : baseUri = baseUri ?? Uri.parse('https://fake.${kind.name}');

  @override
  final TransportKind kind;
  @override
  final Uri baseUri;
  FakeHandler? handler;
  ApiError? failWith;
  final List<ApiRequest> requests = [];

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    requests.add(request);
    final f = failWith;
    if (f != null) throw f;
    final res = await (handler ?? (_) => const ApiResponse(200, '{}'))(request);
    if (!res.ok) throw ApiError.fromResponse(res.status, res.body, res.headers);
    return res;
  }
}

/// Scripted LAN probe: returns [info], throws [error], or never completes
/// when [hang] is set (to exercise the 1.5 s timeout).
class FakeLanProbe implements LanProbe {
  FakeLanProbe({this.info, this.error, this.hang = false});
  LanInfo? info;
  Object? error;
  bool hang;
  int calls = 0;

  @override
  Future<LanInfo> probe() {
    calls++;
    if (hang) return Completer<LanInfo>().future;
    if (error != null) return Future.error(error!);
    return Future.value(info ?? const LanInfo(serverId: 'desk-1', apiLevel: 1, tls: true));
  }
}

/// Manually advanced clock.
class FakeClock {
  FakeClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 2, 1, 8);
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}
