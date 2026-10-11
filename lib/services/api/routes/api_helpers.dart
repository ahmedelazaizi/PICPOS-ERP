// ApiHandler - shared response helpers (404, json, error).
part of '../api_handler.dart';

/// shared response helpers (404, json, error) (see [ApiHandler]).
extension ApiHandlerHelpers on ApiHandler {
  // ═══════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════

  Response _notFound(Request request) {
    debugPrint('[API] 404 — url: ${request.url}, requestedUri: ${request.requestedUri}');
    return Response.notFound(
      json.encode({
        'error': 'Not found',
        'path': request.requestedUri.path,
        'url': request.url.toString(),
        'method': request.method,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _json(Map<String, dynamic> data, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: json.encode(data),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _error(String message, {int statusCode = 500}) {
    return Response(
      statusCode,
      body: json.encode({'error': message}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
