// A scripted main system for the gate tests (no network).
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/auth_session_gate.dart';
import 'package:picpos_erp/services/server_proxy.dart';

class FakeAuthority implements SessionAuthorityPort {
  SessionMintOutcome acquireOutcome = SessionMintOutcome.unreachable;
  SessionMintOutcome directOutcome = SessionMintOutcome.unreachable;
  PasswordChangeResult change =
      const PasswordChangeResult(PasswordChangeOutcome.unreachable);

  /// What the token-bearing feed pull does (e.g. inserts the user).
  Future<bool> Function(AppDatabase db, String token)? onPull;

  final acquireCalls = <({int userId, String? username, String? password, String? cardCode})>[];
  final directCalls = <({String? username, String? password, String? cardCode})>[];
  final changeCalls = <String>[];
  int pulls = 0;
  final tokens = <int>{};

  @override
  Future<SessionMintResult> acquire(
      {required int userId, String? username, String? password, String? cardCode}) async {
    acquireCalls.add((userId: userId, username: username, password: password, cardCode: cardCode));
    if (acquireOutcome == SessionMintOutcome.ok) tokens.add(userId);
    return SessionMintResult(acquireOutcome,
        token: acquireOutcome == SessionMintOutcome.ok ? 'tok-$userId' : null,
        userId: userId);
  }

  @override
  Future<SessionMintResult> mintDirect(
      {String? username, String? password, String? cardCode}) async {
    directCalls.add((username: username, password: password, cardCode: cardCode));
    return SessionMintResult(directOutcome,
        token: directOutcome == SessionMintOutcome.ok ? 'direct-tok' : null);
  }

  @override
  Future<PasswordChangeResult> changeOwnPassword({
    String? username,
    String? currentPassword,
    String? cardCode,
    required String newPassword,
  }) async {
    changeCalls.add('$username');
    return change;
  }

  @override
  Future<bool> pullCredentialFeeds(AppDatabase db, String token) async {
    pulls++;
    return onPull == null ? true : onPull!(db, token);
  }

  @override
  bool hasSessionToken(int userId) => tokens.contains(userId);
}
