import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../service/errors.dart';

/// Default request-body cap (S-9): every JSON route except the bulk ones below.
const kDefaultMaxBodyBytes = 1024 * 1024;

/// Cap for the bulk routes: mobile push (up to 50 documents, expense photos
/// are <= 1 MiB each), desktop master upserts, snapshots and acks.
const kLargeMaxBodyBytes = 10 * 1024 * 1024;

const _largeBodyPaths = {
  '/mobile/sync/push',
  '/desktop/master',
  '/desktop/snapshots',
  '/desktop/documents/ack',
};

int maxBodyBytesFor(String path) => _largeBodyPaths.contains(path) ? kLargeMaxBodyBytes : kDefaultMaxBodyBytes;

/// Rejects oversized bodies with 413 `payload_too_large` BEFORE any auth or
/// rate-limit work and before the body is fully read: a declared
/// Content-Length over the cap fails immediately; a body without
/// Content-Length (chunked) is wrapped in a stream that fails once more than
/// the cap has been consumed (the excess is never buffered).
Middleware bodyLimit() => (inner) => (req) {
      final limit = maxBodyBytesFor(req.requestedUri.path);
      final declared = req.contentLength;
      if (declared != null && declared > limit) throw ApiError(413, 'payload_too_large');
      return inner(req.change(body: _capped(req.read(), limit)));
    };

Stream<List<int>> _capped(Stream<List<int>> source, int limit) async* {
  var seen = 0;
  await for (final chunk in source) {
    seen += chunk.length;
    if (seen > limit) throw ApiError(413, 'payload_too_large');
    yield chunk;
  }
}

/// Reads a JSON object body; the 413 raised by [bodyLimit] must pass through.
Future<Map<String, Object?>> readJsonObject(Request req) async {
  try {
    final v = jsonDecode(await req.readAsString());
    if (v is Map) return v.cast<String, Object?>();
  } on ApiError {
    rethrow;
  } catch (_) {}
  throw ApiError(400, 'invalid_json');
}
