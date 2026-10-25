// ═══════════════════════════════════════════════════════════════════════════
// Manager approval proofs (plan 2026-10-24, P5 / B.9).
//
// A four-eyes approval is decided ON THE MAIN SERVER: a second user proves his
// credential to `POST /api/approvals/grant`, the main checks that he is a
// DIFFERENT user who holds the permission outright ([ManagerApprovalRules]), and
// answers with a SIGNED proof that travels with the operation:
//
//     header  X-Approval-Proof: <proof>          (online call)
//     payload "approvalProof": "<proof>"          (outbox row -> header on replay)
//
// The proof is `base64url(json claims) '.' HMAC(domain, claims)`, signed with the
// server's session key under its own domain, so no session token can be replayed
// as a proof and a client cannot mint one.
//
// Verification ([ApprovalGate.authorise]) runs where a permission is checked
// ([ApiUserCtx.requirePermission]): when the signed-in user LACKS the permission
// but presents a proof for exactly that code that
//   * is correctly signed, names this user as the requester and this device,
//   * has not expired (checked on first use only - see replay below),
//   * has an approver who is still active and still allowed to approve,
// the call is let through and the use is recorded (audit + replay memory).
//
// Replay: a proof is single-use per OPERATION. The operation is fingerprinted as
// `METHOD path` + the request's `X-Idempotency-Key`; the first use stores the
// fingerprint, a retry of the SAME operation (an outbox replay carries the same
// idempotency key) is accepted again - even after the proof expired - and a
// different operation is `approval_already_used`.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';

import '../../core/permissions/manager_approval_rules.dart';
import '../../data/database/database.dart';
import '../activity_logger.dart';
import 'api_session_token.dart';

/// Machine-readable codes of a refused proof (`403 {code}`).
abstract final class ApprovalCode {
  static const String invalid = 'approval_invalid';
  static const String expired = 'approval_expired';
  static const String mismatch = 'approval_mismatch';
  static const String alreadyUsed = 'approval_already_used';
  static const String approverInvalid = 'approval_approver_invalid';
}

/// What a verified proof says.
class ApprovalClaims {
  const ApprovalClaims({
    required this.permission,
    required this.requesterId,
    required this.approverId,
    required this.issuedAtMs,
    required this.expiresAtMs,
    required this.nonce,
    this.deviceId,
    this.scope,
  });

  final String permission;
  final int requesterId;
  final int approverId;
  final int issuedAtMs;
  final int expiresAtMs;
  final String nonce;
  final String? deviceId;
  final String? scope;
}

class ApprovalProof {
  ApprovalProof._();

  static const String domain = 'picpos.approval.v1';

  /// How long a freshly granted proof may be used for its FIRST use.
  static const Duration ttl = Duration(minutes: 5);

  static String newNonce() {
    final rnd = Random.secure();
    return List<int>.generate(16, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Signed proof; null when the signing key is not ready.
  static String? mint({
    required String permission,
    required int requesterId,
    required int approverId,
    String? deviceId,
    String? scope,
    int? nowMs,
    String? nonce,
  }) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final payload = base64Url.encode(utf8.encode(jsonEncode({
      'v': 1,
      'op': permission,
      'req': requesterId,
      'apr': approverId,
      'iat': now,
      'exp': now + ttl.inMilliseconds,
      'nid': nonce ?? newNonce(),
      'dev': ?deviceId,
      'sc': ?scope,
    })));
    final sig = ApiSessionToken.signDomain(domain, payload);
    return sig == null ? null : '$payload.$sig';
  }

  /// The claims of [proof] iff it is well formed AND correctly signed
  /// (expiry is NOT checked here).
  static ApprovalClaims? parse(String? proof) {
    if (proof == null) return null;
    final dot = proof.indexOf('.');
    if (dot <= 0 || dot == proof.length - 1) return null;
    final payload = proof.substring(0, dot);
    if (!ApiSessionToken.verifyDomain(domain, payload, proof.substring(dot + 1))) {
      return null;
    }
    try {
      final m = jsonDecode(utf8.decode(base64Url.decode(payload)));
      if (m is! Map<String, dynamic> || m['v'] != 1) return null;
      final op = m['op'], req = m['req'], apr = m['apr'];
      final iat = m['iat'], exp = m['exp'], nid = m['nid'];
      if (op is! String || op.isEmpty || req is! int || apr is! int) return null;
      if (iat is! int || exp is! int || nid is! String || nid.isEmpty) return null;
      return ApprovalClaims(
        permission: op,
        requesterId: req,
        approverId: apr,
        issuedAtMs: iat,
        expiresAtMs: exp,
        nonce: nid,
        deviceId: m['dev'] as String?,
        scope: m['sc'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Outcome of presenting a proof at a permission check.
class ApprovalDecision {
  const ApprovalDecision.granted(this.claims)
      : code = null,
        replay = false;
  const ApprovalDecision.replayed(this.claims)
      : code = null,
        replay = true;
  const ApprovalDecision.denied(this.code)
      : claims = null,
        replay = false;

  final ApprovalClaims? claims;
  final String? code;
  final bool replay;
  bool get isGranted => code == null;

  Response toResponse() => Response(
        403,
        body: jsonEncode({'error': 'Approval proof refused: $code', 'code': code}),
        headers: const {'content-type': 'application/json'},
      );
}

/// Single-use memory of consumed proofs: in memory, backed by the audit trail
/// (`activity_logs`, action [useAction]) so a restart does not forget a use.
class ApprovalProofStore {
  ApprovalProofStore._();

  static const String useAction = 'manager_approval_used';
  static final Map<String, String> _used = {};

  static void resetForTesting() => _used.clear();

  static final RegExp _fp = RegExp(r'fp=([0-9a-f]{64})');

  /// Fingerprint stored for [nonce], or null when never used.
  static Future<String?> fingerprintOf(AppDatabase db, String nonce) async {
    final hit = _used[nonce];
    if (hit != null) return hit;
    try {
      final rows = await (db.select(db.activityLogs)
            ..where((l) =>
                l.action.equals(useAction) & l.description.like('nid=$nonce %'))
            ..orderBy([(l) => OrderingTerm.asc(l.id)])
            ..limit(1))
          .get();
      if (rows.isEmpty) return null;
      final fp = _fp.firstMatch(rows.first.description)?.group(1);
      if (fp != null) _used[nonce] = fp;
      return fp;
    } catch (_) {
      return null;
    }
  }

  static Future<void> record(
    AppDatabase db,
    ApprovalClaims c,
    String fingerprint, {
    String? approverName,
    String? requesterName,
  }) async {
    _used[c.nonce] = fingerprint;
    await ActivityLogger(db).log(
      userId: c.requesterId,
      userName: requesterName ?? '#${c.requesterId}',
      action: useAction,
      entityType: 'approval',
      entityId: c.approverId,
      description: 'nid=${c.nonce} op=${c.permission} req=${c.requesterId} '
          'apr=${c.approverId} fp=$fingerprint',
    );
  }
}

class ApprovalGate {
  ApprovalGate._();

  static const String headerName = 'x-approval-proof';

  /// sha256 of `METHOD path#idempotency-key`: what "the same operation" means.
  /// A call WITHOUT an idempotency key cannot prove it is a retry, so it gets a
  /// one-off fingerprint: the proof is spent by it and can never be replayed.
  static String fingerprint(Request request) {
    final idem = request.headers['x-idempotency-key'];
    final basis = '${request.method} /${request.url.path}'
        '#${idem == null || idem.isEmpty ? 'nokey-${ApprovalProof.newNonce()}' : idem}';
    return sha256.convert(utf8.encode(basis)).toString();
  }

  /// Whether the approver may still approve [permission] (checked at USE time so
  /// a user disabled after granting cannot be used through an old proof).
  static Future<bool> approverStillValid(
    AppDatabase db,
    ApprovalClaims c,
  ) async {
    final user = await (db.select(db.users)
          ..where((u) => u.id.equals(c.approverId))
          ..limit(1))
        .getSingleOrNull();
    if (user == null || !user.isActive || user.isLocked) return false;
    return ManagerApprovalRules.canApprove(
      approverId: c.approverId,
      requesterId: c.requesterId,
      approverPermissions: await db.getUserPermissionCodes(c.approverId),
      permission: c.permission,
    );
  }

  /// `null` when the request carries no proof (the caller keeps its ordinary
  /// refusal). Otherwise the decision for [userId] needing [permission].
  static Future<ApprovalDecision?> authorise(
    Request request,
    AppDatabase db,
    int userId,
    String permission, {
    int? nowMs,
  }) async {
    final raw = request.headers[headerName];
    if (raw == null || raw.isEmpty) return null;
    final c = ApprovalProof.parse(raw);
    if (c == null) return const ApprovalDecision.denied(ApprovalCode.invalid);
    final device = request.context['lanDeviceId'];
    if (c.requesterId != userId ||
        c.permission != permission ||
        (c.deviceId != null && c.deviceId != device)) {
      return const ApprovalDecision.denied(ApprovalCode.mismatch);
    }
    final fp = fingerprint(request);
    final prior = await ApprovalProofStore.fingerprintOf(db, c.nonce);
    if (prior != null) {
      return prior == fp
          ? ApprovalDecision.replayed(c)
          : const ApprovalDecision.denied(ApprovalCode.alreadyUsed);
    }
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    if (now >= c.expiresAtMs) {
      return const ApprovalDecision.denied(ApprovalCode.expired);
    }
    if (!await approverStillValid(db, c)) {
      return const ApprovalDecision.denied(ApprovalCode.approverInvalid);
    }
    await ApprovalProofStore.record(db, c, fp);
    return ApprovalDecision.granted(c);
  }
}
