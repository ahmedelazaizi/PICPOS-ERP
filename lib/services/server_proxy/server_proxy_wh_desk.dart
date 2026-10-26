// ServerProxy - the accountant's warehouse-receipts inbox on the MAIN (WH-002).
part of '../server_proxy.dart';

/// `/api/m1/wh/desk/*` calls of [ServerProxy]. Returns the HTTP status and the
/// decoded body; a network failure is thrown (the caller decides what
/// "unreachable" means). The answer is never turned into a success here.
extension ServerProxyWhDesk on ServerProxy {
  Future<(int, Map<String, dynamic>)> whDeskCall(
    String method,
    String path, {
    String? idempotencyKey,
  }) async {
    final headers = Map<String, String>.from(_authHeaders);
    if (idempotencyKey != null) headers['X-Idempotency-Key'] = idempotencyKey;
    final url = Uri.parse('$_baseUrl$path');
    final client = TlsTrust.httpClient();
    final response = await (method == 'GET'
            ? client.get(url, headers: headers)
            : client.post(url, headers: headers, body: '{}'))
        .timeout(ServerProxy.requestTimeout);
    var decoded = <String, dynamic>{};
    try {
      final d = json.decode(response.body);
      if (d is Map<String, dynamic>) decoded = d;
    } catch (_) {}
    return (response.statusCode, decoded);
  }
}
