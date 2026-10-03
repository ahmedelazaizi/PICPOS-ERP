/// Transports and the LAN-first / cloud-fallback selector (ARCHITECTURE-M
/// ADR-M2 §4: LAN when the desktop answers `/api/m1/info` within 1.5 s over
/// pinned TLS, otherwise the cloud).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_error.dart';
import 'url_policy.dart';

enum TransportKind { lan, cloud }

/// The connection chip «محلي / سحابي / غير متصل».
enum ConnectionMode { local, cloud, offline }

class ApiRequest {
  const ApiRequest(this.method, this.path, {this.query = const {}, this.body, this.headers = const {}});
  final String method;

  /// Path below the transport's base URL, e.g. `/manage/login`.
  final String path;
  final Map<String, String> query;

  /// JSON-encodable body (`null` = no body).
  final Object? body;
  final Map<String, String> headers;
}

class ApiResponse {
  const ApiResponse(this.status, this.body, {this.headers = const {}});
  final int status;
  final String body;
  final Map<String, String> headers;

  bool get ok => status >= 200 && status < 300;
  Object? get json => body.isEmpty ? null : jsonDecode(body);
}

/// One way to reach a server. Implementations throw [ApiError] for any
/// failure (network → [ApiErrorKind.network], non-2xx → mapped response).
abstract interface class ApiTransport {
  TransportKind get kind;
  Uri get baseUri;
  Future<ApiResponse> send(ApiRequest request);
}

/// `package:http` transport. TLS pinning of the LAN certificate is injected
/// through [client] (an `IOClient` over a pinned `HttpClient`, M-2).
class HttpApiTransport implements ApiTransport {
  HttpApiTransport({
    required this.kind,
    required this.baseUri,
    required UrlPolicy policy,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client() {
    policy.check(baseUri);
  }

  @override
  final TransportKind kind;
  @override
  final Uri baseUri;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<ApiResponse> send(ApiRequest r) async {
    final base = baseUri.path.endsWith('/') ? baseUri.path.substring(0, baseUri.path.length - 1) : baseUri.path;
    final uri = baseUri.replace(path: '$base${r.path}', queryParameters: r.query.isEmpty ? null : r.query);
    final req = http.Request(r.method, uri)..headers.addAll(r.headers);
    if (r.body != null) req.body = jsonEncode(r.body);
    http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(timeout)).timeout(timeout);
    } on TimeoutException catch (e) {
      throw ApiError.network(e);
    } on http.ClientException catch (e) {
      throw ApiError.network(e);
    } on Exception catch (e) {
      // e.g. a TLS handshake / pin mismatch surfaced by a pinned HttpClient.
      throw ApiError.network(e);
    }
    final out = ApiResponse(res.statusCode, utf8.decode(res.bodyBytes), headers: res.headers);
    if (!out.ok) throw ApiError.fromResponse(out.status, out.body, out.headers);
    return out;
  }

  void close() => _client.close();
}

/// `GET /api/m1/info` result (§2.4).
class LanInfo {
  const LanInfo({required this.serverId, required this.apiLevel, required this.tls, this.companyName});
  final String serverId;
  final int apiLevel;
  final bool tls;
  final String? companyName;

  factory LanInfo.fromJson(Map<String, Object?> m) => LanInfo(
        serverId: '${m['serverId'] ?? ''}',
        apiLevel: (m['apiLevel'] as num?)?.toInt() ?? 0,
        tls: m['tls'] == true,
        companyName: m['companyName'] as String?,
      );
}

/// Reachability probe of the desktop LAN server. Throws on failure.
abstract interface class LanProbe {
  Future<LanInfo> probe();
}

/// Probes `/api/m1/info` through a transport (the pinned LAN one).
class TransportLanProbe implements LanProbe {
  TransportLanProbe(this.transport, {this.headers = const {}});
  final ApiTransport transport;
  final Map<String, String> headers;

  @override
  Future<LanInfo> probe() async {
    final res = await transport.send(ApiRequest('GET', '/api/m1/info', headers: headers));
    final j = res.json;
    if (j is! Map) throw const FormatException('info: not an object');
    return LanInfo.fromJson(j.cast<String, Object?>());
  }
}

typedef Clock = DateTime Function();

class TransportChoice {
  const TransportChoice(this.mode, this.transport, {this.reason});
  final ConnectionMode mode;

  /// `null` when [mode] is [ConnectionMode.offline].
  final ApiTransport? transport;

  /// Why LAN was not used (`lan_not_configured`, `lan_unreachable`,
  /// `lan_no_tls`, `lan_api_level`), for diagnostics.
  final String? reason;
}

/// Chooses LAN when the desktop answers the probe in time with TLS and a
/// supported API level; falls back to the cloud; otherwise offline. A probe
/// result is reused for [probeTtl]; [markLanFailed] forces a fresh probe.
class TransportSelector {
  TransportSelector({
    this.lan,
    this.lanProbe,
    this.cloud,
    this.probeTimeout = const Duration(milliseconds: 1500),
    this.probeTtl = const Duration(seconds: 60),
    this.minApiLevel = 1,
    this.requireLanTls = true,
    Clock? clock,
  }) : _now = clock ?? DateTime.now;

  final ApiTransport? lan;
  final LanProbe? lanProbe;
  final ApiTransport? cloud;
  final Duration probeTimeout;
  final Duration probeTtl;
  final int minApiLevel;

  /// M-A/M-B refuse LAN without TLS in production (§2.4).
  final bool requireLanTls;
  final Clock _now;

  DateTime? _probedAt;
  String? _lanRejection; // null = LAN usable at _probedAt

  Future<TransportChoice> select({bool forceProbe = false}) async {
    final lanReason = await _lanRejectionReason(forceProbe);
    if (lanReason == null) return TransportChoice(ConnectionMode.local, lan);
    if (cloud != null) return TransportChoice(ConnectionMode.cloud, cloud, reason: lanReason);
    return TransportChoice(ConnectionMode.offline, null, reason: lanReason);
  }

  /// A LAN request failed at transport level: re-probe on the next select.
  void markLanFailed() {
    _probedAt = _now();
    _lanRejection = 'lan_unreachable';
  }

  Future<String?> _lanRejectionReason(bool force) async {
    if (lan == null || lanProbe == null) return 'lan_not_configured';
    final at = _probedAt;
    if (!force && at != null && _now().difference(at) < probeTtl) return _lanRejection;
    String? rejection;
    try {
      final info = await lanProbe!.probe().timeout(probeTimeout);
      if (requireLanTls && !info.tls) {
        rejection = 'lan_no_tls';
      } else if (info.apiLevel < minApiLevel) {
        rejection = 'lan_api_level';
      }
    } catch (_) {
      rejection = 'lan_unreachable';
    }
    _probedAt = _now();
    _lanRejection = rejection;
    return rejection;
  }

  /// Runs [op] on the selected transport; when the LAN attempt fails at
  /// transport level and a cloud transport exists, retries once on the
  /// cloud. [op] must reuse the same idempotency key (`commandId`,
  /// `queryId`, `globalId`) on both attempts so the desktop executes once.
  Future<T> run<T>(Future<T> Function(TransportChoice choice) op) async {
    final choice = await select();
    if (choice.mode == ConnectionMode.offline) {
      throw ApiError.network(StateError('offline: ${choice.reason}'));
    }
    try {
      return await op(choice);
    } on ApiError catch (e) {
      if (choice.mode != ConnectionMode.local || !e.transportFailure || cloud == null) rethrow;
      markLanFailed();
      return op(TransportChoice(ConnectionMode.cloud, cloud, reason: 'lan_failed'));
    }
  }
}
