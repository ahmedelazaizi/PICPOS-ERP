import 'dart:io';

/// Docker HEALTHCHECK probe (the runtime image has no curl).
Future<void> main() async {
  final port = Platform.environment['PORT'] ?? '8080';
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/health'));
    final res = await req.close();
    await res.drain<void>();
    client.close();
    exit(res.statusCode == 200 ? 0 : 1);
  } catch (_) {
    exit(1);
  }
}
