/// Cloud `/manage/*` client of «PicPos إدارة» — M-1 surface (pair, login,
/// signed snapshots). Queries/commands/step-up arrive with M-2/M-3.
library;

import 'dart:convert';

import 'api_error.dart';
import 'contracts.dart';
import 'headers.dart';
import 'mobile_password.dart';
import 'signature.dart';
import 'transport.dart';

/// What a pairing QR (or the manual fallback) gives the phone (ADR-M3).
/// The QR carries the desktop signing key so the phone pins it without
/// trusting the cloud; manual entry (code + URL) pins the key returned by
/// `/manage/pair` (trust on first use) and shows its fingerprint.
class PairingOffer {
  const PairingOffer({required this.cloudUrl, required this.code, this.desktopSigningKey, this.company});
  final Uri cloudUrl;
  final String code;
  final String? desktopSigningKey;
  final String? company;

  static final _codeRe = RegExp(r'^[A-HJ-NP-Z2-9]{8}$');

  /// Normalizes a typed pairing code (upper case, spaces/dashes removed).
  static String normalizeCode(String raw) => raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

  static bool isValidCode(String raw) => _codeRe.hasMatch(normalizeCode(raw));

  /// Manual entry. Throws [FormatException] for a bad URL or code.
  factory PairingOffer.manual({required String url, required String code}) {
    final u = Uri.tryParse(url.trim());
    if (u == null || !(u.isScheme('https') || u.isScheme('http')) || u.host.isEmpty) {
      throw const FormatException('invalid_url');
    }
    final c = normalizeCode(code);
    if (!_codeRe.hasMatch(c)) throw const FormatException('invalid_code');
    return PairingOffer(cloudUrl: u, code: c);
  }

  /// QR JSON `{v:1, cloudUrl, cloudCode, desktopSigningKey, company}`.
  factory PairingOffer.fromQr(String text) {
    final Object? m;
    try {
      m = jsonDecode(text);
    } on FormatException {
      throw const FormatException('invalid_qr');
    }
    if (m is! Map || m['v'] != 1) throw const FormatException('invalid_qr');
    final base = PairingOffer.manual(url: '${m['cloudUrl'] ?? ''}', code: '${m['cloudCode'] ?? ''}');
    final key = m['desktopSigningKey'];
    if (key is! String) throw const FormatException('invalid_qr');
    PayloadVerifier.fromBase64(key); // validates the key encoding
    return PairingOffer(cloudUrl: base.cloudUrl, code: base.code, desktopSigningKey: key, company: m['company'] as String?);
  }

  Map<String, Object?> toQrJson() => {
        'v': 1,
        'cloudUrl': cloudUrl.toString(),
        'cloudCode': code,
        'desktopSigningKey': desktopSigningKey,
        'company': company,
      };
}

class CompanyInfo {
  const CompanyInfo({required this.name, required this.currency, required this.decimals});
  final String name;
  final String currency;
  final int decimals;

  factory CompanyInfo.fromJson(Map<String, Object?> m) => CompanyInfo(
        name: '${m['name'] ?? ''}',
        currency: '${m['currency'] ?? ''}',
        decimals: (m['decimals'] as num?)?.toInt() ?? 3,
      );
  Map<String, Object?> toJson() => {'name': name, 'currency': currency, 'decimals': decimals};
}

/// `/manage/pair` result with the company block.
class AdminPairResult extends PairResult {
  const AdminPairResult({
    required super.deviceToken,
    required super.desktopSigningKey,
    required this.deviceId,
    required this.company,
    super.user,
  });
  final String deviceId;
  final CompanyInfo company;
}

MobileUser mobileUserFromJson(Map<String, Object?> m) => MobileUser(
      globalId: '${m['globalId'] ?? ''}',
      username: '${m['username'] ?? ''}',
      displayName: '${m['displayName'] ?? m['username'] ?? ''}',
      permissions: [for (final p in (m['permissions'] as List? ?? const [])) '$p'],
      branchScope: [for (final b in (m['branchScope'] as List? ?? const [])) (b as num).toInt()],
    );

Map<String, Object?> mobileUserToJson(MobileUser u) => {
      'globalId': u.globalId,
      'username': u.username,
      'displayName': u.displayName,
      'permissions': u.permissions,
      'branchScope': u.branchScope,
    };

/// Snapshots after verification against the pinned desktop key.
class VerifiedSnapshots {
  const VerifiedSnapshots({required this.items, required this.rejected, this.desktopLastSeenAt, this.serverTime});

  /// Only items whose signature verifies and whose signed envelope
  /// (kind/scope/asOf inside the payload) matches the cloud's envelope.
  final List<SignedPayload> items;

  /// Count of items that failed verification (shown as
  /// «تعذّر التحقق من البيانات»; their figures are never displayed).
  final int rejected;
  final DateTime? desktopLastSeenAt;
  final DateTime? serverTime;

  SignedPayload? find(String kind, [String scope = 'all']) {
    for (final i in items) {
      if (i.kind == kind && i.scope == scope) return i;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'items': [
          for (final i in items)
            {'kind': i.kind, 'scope': i.scope, 'asOf': i.asOf.toUtc().toIso8601String(), 'payload': i.payload, 'signature': i.signature}
        ],
        'rejected': rejected,
        'desktopLastSeenAt': desktopLastSeenAt?.millisecondsSinceEpoch,
        'serverTime': serverTime?.millisecondsSinceEpoch,
      };

  factory VerifiedSnapshots.fromJson(Map<String, Object?> m) => VerifiedSnapshots(
        items: [for (final i in (m['items'] as List? ?? const [])) SignedPayload.fromJson((i as Map).cast())],
        rejected: (m['rejected'] as num?)?.toInt() ?? 0,
        desktopLastSeenAt: _ms(m['desktopLastSeenAt']),
        serverTime: _ms(m['serverTime']),
      );
}

DateTime? _ms(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true) : null;

/// True when [item]'s signature verifies with [verifier] and the signed
/// payload names the same kind, scope and asOf as the envelope, so the relay
/// cannot replay a payload under another kind/branch or a newer time.
Future<bool> verifySnapshot(SignedPayload item, PayloadVerifier verifier) async {
  final p = item.payload;
  if (p is! Map) return false;
  if (p['kind'] != item.kind || p['scope'] != item.scope) return false;
  final signedAsOf = DateTime.tryParse('${p['asOf']}');
  if (signedAsOf == null || !signedAsOf.isAtSameMomentAs(item.asOf)) return false;
  return verifier.verify(p, item.signature);
}

/// Snapshot kinds of M-1 (desktop builder ↔ cloud filter ↔ app).
abstract final class SnapshotKinds {
  static const kpiToday = 'kpi.today';
  static const kpiMonth = 'kpi.month';
  static const profitToday = 'profit.today';
  static const profitMonth = 'profit.month';
  static const cash = 'cash.position';
  static const parties = 'parties.position';
  static const branches = 'branches.performance';
  static const reps = 'reps.performance';
  static const approvalsSalesReturns = 'approvals.sales_returns';
  static const approvalsPurchaseReturns = 'approvals.purchase_returns';
  static const approvalsLeave = 'approvals.leave';
  static const approvalsPayroll = 'approvals.payroll';
  static const approvalsJournals = 'approvals.journals';

  static const approvals = [
    approvalsSalesReturns,
    approvalsPurchaseReturns,
    approvalsLeave,
    approvalsPayroll,
    approvalsJournals,
  ];

  static String branchScope(int branchId) => 'branch:$branchId';
}

/// Builds one signed snapshot item the way [verifySnapshot] expects: the
/// envelope (kind, scope, asOf) is repeated inside the signed payload.
Future<Map<String, Object?>> buildSignedSnapshot(
  PayloadSigner signer, {
  required String kind,
  required String scope,
  required DateTime asOf,
  required Map<String, Object?> data,
}) async {
  final at = DateTime.fromMillisecondsSinceEpoch(
      asOf.millisecondsSinceEpoch, isUtc: true).toIso8601String();
  final payload = {...data, 'kind': kind, 'scope': scope, 'asOf': at};
  return {'kind': kind, 'scope': scope, 'asOf': at, 'payload': payload, 'signature': await signer.sign(payload)};
}

/// [ManageApi] over a cloud [ApiTransport]. Holds the device credentials and
/// the session; [credentials] is updated by [pair] and [login].
class CloudManageClient implements ManageApi {
  CloudManageClient({
    required this.transport,
    required this.headers,
    this.credentials = const ApiCredentials(),
  });

  final ApiTransport transport;
  final ApiHeaderBuilder headers;
  ApiCredentials credentials;

  Map<String, Object?> _map(ApiResponse r) {
    final j = r.json;
    if (j is Map) return j.cast<String, Object?>();
    throw ApiError(kind: ApiErrorKind.unknown, code: 'invalid_response', status: r.status);
  }

  @override
  Future<AdminPairResult> pair({
    required String code,
    required String deviceId,
    required String deviceName,
    required String appVersion,
  }) async {
    final r = await transport.send(ApiRequest('POST', ManageRoutes.pair,
        headers: headers.anonymous(),
        body: {'code': PairingOffer.normalizeCode(code), 'deviceId': deviceId, 'deviceName': deviceName, 'appVersion': appVersion}));
    final m = _map(r);
    final key = m['desktopSigningKey'];
    if (key is! String) throw ApiError(kind: ApiErrorKind.unknown, code: 'signing_key_missing', status: r.status);
    final res = AdminPairResult(
      deviceToken: '${m['deviceToken']}',
      deviceId: '${m['deviceId'] ?? deviceId}',
      desktopSigningKey: key,
      user: m['user'] is Map ? mobileUserFromJson((m['user'] as Map).cast()) : null,
      company: CompanyInfo.fromJson((m['company'] as Map? ?? const {}).cast()),
    );
    credentials = ApiCredentials(deviceId: res.deviceId, deviceToken: res.deviceToken);
    return res;
  }

  @override
  Future<Session> login({required String username, required String password, String? totp}) async {
    final r = await transport.send(ApiRequest('POST', ManageRoutes.login,
        headers: headers.build(credentials, session: false),
        body: {'username': username, 'password': normalizeCredential(password), if (totp != null) 'totp': totp}));
    final m = _map(r);
    final s = Session(
      token: '${m['sessionToken']}',
      expiresAt: DateTime.parse('${m['expiresAt']}'),
      user: mobileUserFromJson((m['user'] as Map).cast()),
    );
    credentials = credentials.copyWith(sessionToken: s.token);
    return s;
  }

  Future<void> logout() async {
    try {
      await transport.send(ApiRequest('POST', ManageRoutes.logout,
          headers: headers.build(credentials)));
    } finally {
      credentials = credentials.signedOut();
    }
  }

  Future<void> unpair() async {
    await transport.send(ApiRequest('POST', ManageRoutes.unpair,
        headers: headers.build(credentials, session: false)));
  }

  /// Raw `GET /manage/snapshots` (unverified; use [verifiedSnapshots]).
  Future<Map<String, Object?>> snapshotsEnvelope(List<String> kinds, {int? branchId}) async {
    final r = await transport.send(ApiRequest('GET', ManageRoutes.snapshots,
        headers: headers.build(credentials, json: false),
        query: {if (kinds.isNotEmpty) 'kinds': kinds.join(','), if (branchId != null) 'branch': '$branchId'}));
    return _map(r);
  }

  @override
  Future<List<SignedPayload>> snapshots(List<String> kinds, {int? branchId}) async => [
        for (final i in (await snapshotsEnvelope(kinds, branchId: branchId))['items'] as List? ?? const [])
          SignedPayload.fromJson((i as Map).cast()),
      ];

  /// Fetches and verifies against the key pinned at pairing.
  Future<VerifiedSnapshots> verifiedSnapshots(PayloadVerifier verifier,
      {List<String> kinds = const [], int? branchId}) async {
    final env = await snapshotsEnvelope(kinds, branchId: branchId);
    final ok = <SignedPayload>[];
    var bad = 0;
    for (final raw in env['items'] as List? ?? const []) {
      SignedPayload item;
      try {
        item = SignedPayload.fromJson((raw as Map).cast());
      } catch (_) {
        bad++;
        continue;
      }
      if (await verifySnapshot(item, verifier)) {
        ok.add(item);
      } else {
        bad++;
      }
    }
    return VerifiedSnapshots(
      items: ok,
      rejected: bad,
      desktopLastSeenAt: _ms((env['desktop'] as Map?)?['lastSeenAt']),
      serverTime: _ms(env['serverTime']),
    );
  }

  static Never _later(String what) =>
      throw ApiError(kind: ApiErrorKind.notFound, code: 'not_available_in_m1', message: what);

  @override
  Future<String> stepUp({String? password, String? totp}) async => _later('step-up (M-3)');
  @override
  Future<RemoteResult> submitQuery(QueryRequest q) async => _later('queries (M-2)');
  @override
  Future<RemoteResult> pollQuery(String queryId, {Duration wait = const Duration(seconds: 20)}) async =>
      _later('queries (M-2)');
  @override
  Future<RemoteResult> submitCommand(CommandRequest c, {String? stepUpToken}) async => _later('commands (M-3)');
  @override
  Future<RemoteResult> pollCommand(String commandId, {Duration wait = const Duration(seconds: 20)}) async =>
      _later('commands (M-3)');
}
