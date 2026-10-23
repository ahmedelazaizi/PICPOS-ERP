// Guards the route table of `ApiHandler.buildRouter()`.
//
// `api_handler.dart` registers its routes through `_register*Routes` methods
// that live in `lib/services/api/routes/`. This test (1) walks buildRouter's
// call sequence over those sources and compares the ordered
// (method, path) list with `test/golden/api_routes.txt` (captured before the
// split), and (2) builds the real router and checks that every parameter-less
// GET route actually resolves to a handler rather than the catch-all 404.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_handler.dart';

final _token = RegExp(
  r"router\.(get|post|put|delete|patch|all|head|options)\(\s*'([^']+)'"
  r'|WebStaticHandler\.mount\('
  r'|(_register\w+)\(router\)',
);

String _stripComments(String s) => s
    .split('\n')
    .where((l) => !l.trim().startsWith('//'))
    .join('\n');

/// Body of `name(...) {` up to the closing brace at two-space indent.
String _bodyOf(String src, String header) {
  final start = src.indexOf(header);
  if (start < 0) return '';
  final open = src.indexOf('{', start);
  final end = src.indexOf('\n  }\n', open);
  return src.substring(open, end);
}

List<String> _expand(String body, String routesSrc, List<String> out) {
  for (final m in _token.allMatches(_stripComments(body))) {
    if (m.group(3) != null) {
      final name = m.group(3)!;
      final inner = _bodyOf(routesSrc, 'void $name(Router router)');
      expect(inner, isNotEmpty, reason: '$name not found in routes/');
      _expand(inner, routesSrc, out);
    } else if (m.group(1) != null) {
      out.add('${m.group(1)!.toUpperCase()} ${m.group(2)}');
    } else {
      out.add('MOUNT WebStaticHandler.mount');
    }
  }
  return out;
}

List<String> _actualRoutes() {
  final main = File('lib/services/api/api_handler.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final routesDir = Directory('lib/services/api/routes');
  final routesSrc = routesDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.readAsStringSync().replaceAll('\r\n', '\n'))
      .join('\n');
  return _expand(
      _bodyOf(main, 'Router buildRouter()'), '$main\n$routesSrc', <String>[]);
}

void main() {
  final golden = File('test/golden/api_routes.txt')
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();

  test('buildRouter registers the golden (method, path) list in order', () {
    expect(_actualRoutes(), golden);
  });

  test('catch-all stays last', () {
    expect(golden.last, 'ALL /<ignored|.*>');
    expect(golden[golden.length - 2], 'MOUNT WebStaticHandler.mount');
  });

  test('every plain GET route resolves to a handler, not the catch-all',
      () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final router = ApiHandler(db).buildRouter();
    // Streaming / upgrade endpoints cannot be probed with a plain request.
    const skip = {'/ws', '/webdb', '/api/cfd/stream'};
    final gets = golden
        .where((l) => l.startsWith('GET '))
        .map((l) => l.substring(4))
        .where((p) => !p.contains('<') && !skip.contains(p));
    expect(gets, isNotEmpty);
    for (final path in gets) {
      final res = await router
          .call(shelf.Request('GET', Uri.parse('http://localhost$path')))
          .timeout(const Duration(seconds: 30));
      final text = await res.readAsString();
      var isCatchAll = false;
      try {
        final j = jsonDecode(text);
        isCatchAll = j is Map &&
            j['error'] == 'Not found' &&
            j.containsKey('url') &&
            j.containsKey('method');
      } catch (_) {}
      expect(isCatchAll, isFalse, reason: 'GET $path fell to the catch-all');
    }
  });
}