// Shared HTTP plumbing of the warehouse-phone routes (plan 2026-10-23, W2+).
//
// * [WhError] - a refusal with a stable machine code (plan MC §A.1 codes:
//   permission_denied | stale | invalid_transition | stock_changed |
//   batch_expired | idempotency_conflict | period_closed ...).
// * [WhHttp.run] - device-kind + live user + permission + scope gate, the JSON
//   body parser and ONE error mapper. An unexpected exception becomes a bare
//   `500 internal`: its text is NEVER echoed, because messages from the stock
//   layer can carry quantities (a blind counter must not learn them).
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import '../../../data/database/database.dart';
import '../api_user_context.dart';
import '../approval_proof.dart';
import 'wh_scope.dart';

class WhError implements Exception {
  WhError(this.code, [this.status = 409, this.details = const {}]);
  final String code;
  final int status;
  final Map<String, Object?> details;
  @override
  String toString() => 'WhError($code)';
}

/// Everything a handler needs about the caller.
class WhCtx {
  WhCtx({
    required this.userId,
    required this.branchId,
    required this.deviceId,
    required this.scope,
    required this.request,
  });
  final int userId;
  final int branchId;
  final String deviceId;
  final WhScope scope;
  final Request request;

  /// `X-Idempotency-Key` = the command id; every write needs one.
  String get commandId {
    final id = (request.headers['x-idempotency-key'] ?? '').trim();
    if (id.length < 8) throw WhError('idempotency_key_required', 400);
    return id;
  }
}

/// Sorted-key JSON, so the same logical body always hashes the same.
Object? _canon(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canon(v[k])};
  }
  if (v is List) return [for (final e in v) _canon(e)];
  return v;
}

String payloadHash(Object? body) => sha256.convert(utf8.encode(jsonEncode(_canon(body)))).toString();

class WhHttp {
  WhHttp(this.db);
  final AppDatabase db;

  static Response json(Object body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: const {'content-type': 'application/json'},
      );

  static Response errorResponse(WhError e) => json({'error': e.code, ...e.details}, status: e.status);

  /// Parses a JSON object body; empty body = `{}`.
  static Future<Map<String, Object?>> body(Request r) async {
    final text = await r.readAsString();
    if (text.trim().isEmpty) return {};
    final d = jsonDecode(text);
    if (d is! Map) throw WhError('bad_request', 400);
    return d.cast<String, Object?>();
  }

  Future<Response> run(
    Request request,
    List<String> permissions,
    Future<Response> Function(WhCtx ctx) handler,
  ) async {
    try {
      final branch = request.context['lanDeviceBranchId'];
      final deviceId = request.context['lanDeviceId'];
      if (request.context['lanDeviceKind'] != 'warehouse' || branch is! int || deviceId is! String) {
        return errorResponse(WhError('device_scope', 403));
      }
      for (final code in permissions) {
        final denied = await ApiUserCtx.requirePermission(request, db, code);
        if (denied != null) return denied;
      }
      final userId = ApiUserCtx.userIdOf(request)!;
      final scope = await resolveWhScope(db, userId: userId, deviceBranchId: branch);
      return await handler(WhCtx(
        userId: userId,
        branchId: branch,
        deviceId: deviceId,
        scope: scope,
        request: request,
      ));
    } on WhError catch (e) {
      return errorResponse(e);
    } on FormatException {
      return errorResponse(WhError('bad_request', 400));
    } catch (_) {
      return errorResponse(WhError('internal', 500));
    }
  }
}

extension WhApproval on WhHttp {
  /// Who really approves: the signed-in user when he holds [code], otherwise
  /// the manager whose P5 approval proof (`x-approval-proof`) let this call
  /// through `ApiUserCtx.requirePermission` (the proof is bound to [code]).
  Future<int> approverOf(WhCtx ctx, String code) async {
    if (await db.userHasPermission(ctx.userId, code)) return ctx.userId;
    return ApprovalProof.parse(ctx.request.headers['x-approval-proof'])?.approverId ?? ctx.userId;
  }
}

/// Four-eyes (plan §B.2-6): the approver must differ from everyone who made or
/// handled the document. Checked on the server; «مدير النظام» gets no bypass.
void requireDistinct(int approver, Iterable<int?> actors) {
  if (actors.contains(approver)) throw WhError('self_approval', 403);
}

/// Decimal helpers: quantities travel as strings (plan MC contracts).
double parseQty(Object? v, {bool allowZero = false}) {
  final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.trim());
  if (d == null || d.isNaN || d.isInfinite || d < 0 || (!allowZero && d == 0)) {
    throw WhError('invalid_quantity', 422);
  }
  return d;
}

String fmtQty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
