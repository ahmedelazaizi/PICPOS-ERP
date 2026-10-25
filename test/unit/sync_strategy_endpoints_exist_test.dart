// FLEET-1 / FLEET-3 guard: every endpoint a client sync strategy GETs
// (`String get apiEndpoint => '/api/...'`) must be a registered GET route of
// the embedded server. Before this guard two strategies (pos_terminals,
// sale_bom_consumptions) pulled paths that answered 404 on every first sync.
//
// The route table is `test/golden/api_routes.txt` (kept equal to
// `ApiHandler.buildRouter()` by api_routes_golden_test.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _endpoint = RegExp(r"String\s+get\s+apiEndpoint\s*=>\s*'([^']+)'");

void main() {
  final getRoutes = File('test/golden/api_routes.txt')
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.startsWith('GET '))
      .map((l) => l.substring(4))
      .toSet();

  test('every sync strategy apiEndpoint is a registered GET route', () {
    final dir = Directory('lib/services/sync/strategies');
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    final seen = <String, String>{};
    for (final f in files) {
      for (final m in _endpoint.allMatches(f.readAsStringSync())) {
        seen[m.group(1)!] = f.path.split(RegExp(r'[\\/]')).last;
      }
    }
    expect(seen, isNotEmpty, reason: 'no strategy endpoints parsed');
    final missing = [
      for (final e in seen.entries)
        if (!getRoutes.contains(e.key)) '${e.key}  (${e.value})',
    ];
    expect(missing, isEmpty,
        reason: 'sync strategies request GET paths the router does not '
            'register:\n${missing.join('\n')}');
  });

  test('the two FLEET read routes are registered', () {
    expect(getRoutes, contains('/api/pos-terminals'));
    expect(getRoutes, contains('/api/sale-bom-consumptions'));
  });
}
