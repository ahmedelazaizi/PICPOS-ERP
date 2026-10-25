// ServerProxy - branch-manager console context (M2) and four-eyes approval (P5).
part of '../server_proxy.dart';

/// Console + approval calls of [ServerProxy].
extension ServerProxyConsole on ServerProxy {
  /// Headers that depend on the device role, merged into every call:
  ///  * `X-Branch-Id`: on a mirror, the branch the manager works in (M2). The
  ///    main refuses a branch outside his scope.
  ///  * `X-Approval-Proof`: the held four-eyes proof, if any (P5).
  Map<String, String> _consoleHeaders() {
    final branch = NetworkService.instance.isMirror
        ? MirrorBranchContext.instance.currentBranchId
        : null;
    final proof = ApprovalProofCarrier.instance.proof;
    return {
      if (branch != null) 'X-Branch-Id': '$branch',
      'X-Approval-Proof': ?proof,
    };
  }

  /// JSON body of a write. A payload that carries `approvalProof` (stamped when
  /// the row was written, so an outbox replay keeps it) sends it as the header
  /// and never as business data.
  String _encodeBody(Map<String, String> headers, Map<String, dynamic> data) {
    final proof = data[ApprovalProofCarrier.payloadKey];
    if (proof is! String) return json.encode(data);
    headers['X-Approval-Proof'] = proof;
    return json.encode(Map<String, dynamic>.of(data)
      ..remove(ApprovalProofCarrier.payloadKey));
  }

  /// `GET /api/mirror/context` for the signed-in manager; null when the main
  /// cannot be reached or refuses (the caller keeps the read-only state).
  Future<MirrorConsoleContext?> fetchMirrorContext() async {
    try {
      final response = await TlsTrust.httpClient()
          .get(Uri.parse('$_baseUrl/api/mirror/context'), headers: _authHeaders)
          .timeout(const Duration(seconds: 8));
      if (!_isSuccessStatusCode(response.statusCode)) return null;
      return MirrorConsoleContext.fromJson(
          json.decode(response.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[ServerProxy] fetchMirrorContext: $e');
      return null;
    }
  }

  /// `POST /api/approvals/grant`: the status and body of the main's answer. A
  /// network failure is thrown (the caller decides what "unreachable" means).
  Future<(int, Map<String, dynamic>)> postApprovalGrant(
      Map<String, dynamic> body) async {
    final response = await TlsTrust.httpClient()
        .post(Uri.parse('$_baseUrl/api/approvals/grant'),
            headers: _authHeaders, body: json.encode(body))
        .timeout(ServerProxy.requestTimeout);
    Map<String, dynamic> decoded = const {};
    try {
      final d = json.decode(response.body);
      if (d is Map<String, dynamic>) decoded = d;
    } catch (_) {}
    return (response.statusCode, decoded);
  }
}
