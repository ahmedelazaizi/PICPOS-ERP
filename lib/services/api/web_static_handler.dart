// تقديم ملفات بناء الويب (`flutter build web` → `build/web`) من نفس أصل الـAPI
// (م3-9). لا تدخل ملفات البناء في git؛ المجلد قابل للضبط من إعدادات الديسكتوب.
//
// * `GET /` و أي مسار بلا امتداد ⇒ `index.html` (fallback لتطبيق صفحة واحدة).
// * مسار بامتداد غير موجود ⇒ 404.
// * محميّ من الخروج عن الجذر (`..`، مسارات مطلقة).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'web_security_headers.dart';

class WebStaticHandler {
  WebStaticHandler(String rootDir) : _root = p.normalize(p.absolute(rootDir));

  final String _root;

  /// هل في [dir] بناءُ ويب صالح (`index.html`)؟
  static bool hasBuild(String? dir) =>
      dir != null && dir.trim().isNotEmpty && File(p.join(dir, 'index.html')).existsSync();

  /// يركّب تقديم الملفات الثابتة على [router] (قبل الـcatch-all) إن وُجد بناء.
  static void mount(Router router, String? dir, Handler notFound) {
    if (dir == null || !hasBuild(dir)) return;
    final statics = WebStaticHandler(dir);
    router.get('/<path|.*>', (Request r, String _) {
      final path = '/${r.url.path}';
      // الـAPI والقنوات لا تسقط إلى index.html أبداً.
      if (path.startsWith('/api/') || path == '/ws' || path == '/webdb') {
        return notFound(r);
      }
      return statics.call(r);
    });
  }

  static const _types = <String, String>{
    '.html': 'text/html; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.mjs': 'application/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.map': 'application/json; charset=utf-8',
    '.txt': 'text/plain; charset=utf-8',
    '.wasm': 'application/wasm',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.ttf': 'font/ttf',
    '.otf': 'font/otf',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
  };

  Future<Response> call(Request request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response(405, headers: {'allow': 'GET, HEAD'});
    }
    final segments = request.url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.any((s) => s == '..' || s.contains('\\') || s.contains(':'))) {
      return Response.notFound('Not found');
    }
    var file = File(p.joinAll([_root, ...segments]));
    final resolved = p.normalize(p.absolute(file.path));
    if (resolved != _root && !p.isWithin(_root, resolved)) {
      return Response.notFound('Not found');
    }
    var isIndex = false;
    if (segments.isEmpty || !await file.exists()) {
      final last = segments.isEmpty ? '' : segments.last;
      if (segments.isEmpty || !last.contains('.')) {
        file = File(p.join(_root, 'index.html'));
        isIndex = true;
      } else {
        return Response.notFound('Not found');
      }
    }
    if (!await file.exists()) return Response.notFound('Not found');
    final ext = p.extension(file.path).toLowerCase();
    final headers = <String, String>{
      'content-type': _types[ext] ?? 'application/octet-stream',
      // index.html و ملفّات الإقلاع لا تُخزَّن؛ لا نريد واجهةً قديمة بعد ترقية.
      'cache-control': isIndex || ext == '.html' || file.path.endsWith('flutter_service_worker.js')
          ? 'no-cache'
          : 'public, max-age=3600',
      'x-content-type-options': 'nosniff',
      ...WebSecurityHeaders.forFlutterWeb(),
    };
    if (request.method == 'HEAD') return Response.ok(null, headers: headers);
    return Response.ok(file.openRead(), headers: {
      ...headers,
      'content-length': (await file.length()).toString(),
    });
  }
}
