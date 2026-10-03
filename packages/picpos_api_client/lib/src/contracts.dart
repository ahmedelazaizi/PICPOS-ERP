/// Contract surface of the cloud `/manage/*` (M-A) and desktop LAN
/// `/api/m1/*` (M-A, M-B) APIs — ARCHITECTURE-M §2.2 and §2.4.
///
/// M-0 status: routes, DTOs and interfaces only. None of these endpoints
/// exists on a server yet (cloud migration 7 and the desktop `/api/m1/*`
/// adapter arrive in M-1/M-2/M-5); implementations are added with them and
/// covered by contract tests against the docker cloud / desktop harness.
library;

abstract final class ManageRoutes {
  static const pair = '/manage/pair';
  static const login = '/manage/login';
  static const stepUp = '/manage/step-up';
  static const tokenRotate = '/manage/token/rotate';
  static const pushToken = '/manage/push-token';
  static const twoFaEnroll = '/manage/2fa/enroll';
  static const twoFaConfirm = '/manage/2fa/confirm';
  static const snapshots = '/manage/snapshots';
  static const queries = '/manage/queries';
  static String query(String id) => '/manage/queries/${Uri.encodeComponent(id)}';
  static const commands = '/manage/commands';
  static String command(String id) => '/manage/commands/${Uri.encodeComponent(id)}';
  static const notifications = '/manage/notifications';
  static const notificationsRead = '/manage/notifications/read';
  static const notificationPrefs = '/manage/notification-prefs';
}

abstract final class M1Routes {
  static const info = '/api/m1/info';
  static const pair = '/api/pair';
  static const session = '/api/m1/auth/session';
  static const adminQuery = '/api/m1/admin/query';
  static const adminCommand = '/api/m1/admin/command';
  static const adminSnapshots = '/api/m1/admin/snapshots';
  static const posBootstrap = '/api/m1/pos/bootstrap';
  static const posPull = '/api/m1/pos/pull';
  static const shiftCurrent = '/api/m1/pos/shifts/current';
  static const shiftOpen = '/api/m1/pos/shifts/open';
  static const shiftClose = '/api/m1/pos/shifts/close';
  static const sales = '/api/m1/pos/sales';
  static const returns = '/api/m1/pos/returns';
  static const invoiceLookup = '/api/m1/pos/invoices/lookup';
  static const override = '/api/m1/pos/override';
  static String customerBalance(String globalId) => '/api/m1/pos/customers/${Uri.encodeComponent(globalId)}/balance';
}

/// Release-1 query types (§2.2).
abstract final class QueryTypes {
  static const kpiRefresh = 'kpi.refresh';
  static const trialBalance = 'report.trial_balance';
  static const accountLedger = 'report.account_ledger';
  static const incomeStatement = 'report.income_statement';
  static const balanceSheet = 'report.balance_sheet';
  static const partyStatement = 'report.party_statement';
  static const aging = 'report.aging';
  static const lookupAccounts = 'lookup.accounts';
  static const lookupParties = 'lookup.parties';
  static const lookupSafes = 'lookup.safes';
  static const lookupCostCenters = 'lookup.cost_centers';
  static const lookupVoucherBooks = 'lookup.voucher_books';
  static const lookupCheques = 'lookup.cheques';
  static const approvalsDetail = 'approvals.detail';
}

enum CommandClass { approval, financial, self }

/// Release-1 command types and their class; `financial` needs `X-Step-Up`.
abstract final class CommandTypes {
  static const Map<String, CommandClass> classes = {
    'approve.sales_return_draft': CommandClass.approval,
    'cancel.sales_return_draft': CommandClass.approval,
    'approve.purchase_return_draft': CommandClass.approval,
    'cancel.purchase_return_draft': CommandClass.approval,
    'leave.approve': CommandClass.approval,
    'leave.reject': CommandClass.approval,
    'payroll.approve': CommandClass.approval,
    'payroll.post': CommandClass.financial,
    'override.approve': CommandClass.financial,
    'override.reject': CommandClass.financial,
    'field_customer.approve': CommandClass.approval,
    'field_customer.reject': CommandClass.approval,
    'voucher.receipt.create': CommandClass.financial,
    'voucher.payment.create': CommandClass.financial,
    'journal.create': CommandClass.financial,
    'cheque.change_status': CommandClass.financial,
    'user.change_mobile_password': CommandClass.self,
  };

  static bool needsStepUp(String type) => classes[type] == CommandClass.financial;
}

/// Relay status of a query or command.
enum RemoteStatus { queued, delivered, executing, done, rejected, expired }

RemoteStatus parseRemoteStatus(Object? s) =>
    RemoteStatus.values.firstWhere((v) => v.name == s, orElse: () => RemoteStatus.queued);

/// A desktop-signed payload (snapshot item or query result).
class SignedPayload {
  const SignedPayload({required this.asOf, required this.payload, required this.signature, this.kind, this.scope});
  final String? kind;
  final String? scope;
  final DateTime asOf;
  final Object? payload;
  final String signature;

  factory SignedPayload.fromJson(Map<String, Object?> m) => SignedPayload(
        kind: m['kind'] as String?,
        scope: m['scope'] as String?,
        asOf: DateTime.parse(m['asOf'] as String),
        payload: m['payload'],
        signature: m['signature'] as String? ?? '',
      );
}

class QueryRequest {
  const QueryRequest({required this.queryId, required this.type, this.params = const {}, this.fresh = false});
  final String queryId;
  final String type;
  final Map<String, Object?> params;
  final bool fresh;
  Map<String, Object?> toJson() => {'queryId': queryId, 'type': type, 'params': params, if (fresh) 'fresh': true};
}

class CommandRequest {
  const CommandRequest({required this.commandId, required this.type, this.params = const {}, this.expectedVersion});
  final String commandId;
  final String type;
  final Map<String, Object?> params;
  final Object? expectedVersion;
  Map<String, Object?> toJson() => {
        'commandId': commandId,
        'type': type,
        'params': params,
        if (expectedVersion != null) 'expectedVersion': expectedVersion,
      };
}

class RemoteResult {
  const RemoteResult({required this.status, this.result, this.signed, this.reason});
  final RemoteStatus status;
  final Map<String, Object?>? result;

  /// Query results are signed; command results are not.
  final SignedPayload? signed;
  final String? reason;
}

class MobileUser {
  const MobileUser({
    required this.globalId,
    required this.username,
    required this.displayName,
    this.permissions = const [],
    this.branchScope = const [],
  });
  final String globalId;
  final String username;
  final String displayName;

  /// Mirrored codes; `cond:<code>` marks a conditional grant (§3.3).
  final List<String> permissions;
  final List<int> branchScope;

  bool has(String code) => permissions.contains(code) || permissions.contains('cond:$code');
  bool isConditional(String code) => permissions.contains('cond:$code') && !permissions.contains(code);
}

class Session {
  const Session({required this.token, required this.expiresAt, required this.user});
  final String token;
  final DateTime expiresAt;
  final MobileUser user;
}

class PairResult {
  const PairResult({required this.deviceToken, required this.desktopSigningKey, this.user, this.terminalCode, this.branchCode});
  final String deviceToken;
  final String desktopSigningKey;
  final MobileUser? user;
  final String? terminalCode;
  final String? branchCode;
}

/// Cloud `/manage/*` for M-A (§2.2). Implemented in M-1.
abstract interface class ManageApi {
  Future<PairResult> pair({required String code, required String deviceId, required String deviceName, required String appVersion});
  Future<Session> login({required String username, required String password, String? totp});
  Future<String> stepUp({String? password, String? totp});
  Future<List<SignedPayload>> snapshots(List<String> kinds, {int? branchId});
  Future<RemoteResult> submitQuery(QueryRequest q);
  Future<RemoteResult> pollQuery(String queryId, {Duration wait});
  Future<RemoteResult> submitCommand(CommandRequest c, {String? stepUpToken});
  Future<RemoteResult> pollCommand(String commandId, {Duration wait});
}

/// Desktop LAN `/api/m1/admin/*` for M-A (§2.4). Implemented in M-2.
abstract interface class M1AdminApi {
  Future<LanSession> session({required String username, required String password});
  Future<RemoteResult> query(QueryRequest q);
  Future<RemoteResult> command(CommandRequest c);
  Future<List<SignedPayload>> snapshots(List<String> kinds);
}

/// Desktop LAN `/api/m1/pos/*` for M-B (§2.4). Implemented in M-5/M-6.
abstract interface class M1PosApi {
  Future<LanSession> session({required String username, required String pin});
  Future<Map<String, Object?>> bootstrap();
  Future<PullPage> pull(String entity, {int? since, String? cursor});
  Future<PushResult> pushSale(Map<String, Object?> sale);
  Future<PushResult> pushReturn(Map<String, Object?> ret);
}

class LanSession {
  const LanSession({required this.token, required this.user, this.maxDiscountPercent, this.branchId});
  final String token;
  final MobileUser user;
  final String? maxDiscountPercent;
  final int? branchId;
}

class PullPage {
  const PullPage({required this.rows, required this.hasMore, required this.serverTime, this.cursor});
  final List<Map<String, Object?>> rows;
  final bool hasMore;
  final int serverTime;
  final String? cursor;
}

/// Per-document push outcome (same semantics as the rep app).
enum PushStatus { accepted, duplicate, rejected }

class PushResult {
  const PushResult(this.status, {this.code, this.serverId, this.number});
  final PushStatus status;
  final String? code;
  final String? serverId;
  final String? number;

  /// `duplicate` means the server already has it: the outbox treats it as done.
  bool get done => status != PushStatus.rejected;
}
