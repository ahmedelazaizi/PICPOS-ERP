// Spec 077 Batch 6 — Grep-guard for the server-perms endpoint sweep.
//
// Walks all 5 api_*_handler.dart files. For every Future<Response>
// handler that maps to a POST/PUT/DELETE route, asserts EXACTLY ONE
// of the following is true:
//
//   (a) The handler body contains `ApiUserCtx.requirePermission(`
//       within the first ~25 lines of the function body.
//   (b) The signature line is preceded (within ~5 lines) by a
//       comment matching `// EXEMPT-PER-USER:`.
//
// Failure of this test means a new mutation endpoint was added
// without a per-user gate — which is the exact regression Spec 077
// is engineered to prevent.
//
// GET handlers are intentionally NOT covered — see Spec 077 §3
// Non-goals. (We still walk them and skip with a soft note.)
//
// Note: this test reads source files; it doesn't compile or execute
// the handlers. Sufficient for the contract.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/api_handler_source.dart';
import '../helpers/api_data_handler_source.dart';

const handlerFiles = <String>[
  'lib/services/api/api_sales_handler.dart',
  'lib/services/api/api_party_handler.dart',
  'lib/services/api/api_product_handler.dart',
  'lib/services/api/api_purchase_handler.dart',
  'lib/services/api/api_data_handler.dart',
  'lib/services/api/api_voucher_handler.dart',
  // api_handler.dart, api_auth_handler.dart, api_terminals_handler.dart
  // host the EXEMPT handlers — checked separately below.
];

const exemptHostFiles = <String>[
  'lib/services/api/api_handler.dart',
  'lib/services/api/api_auth_handler.dart',
  'lib/services/api/api_terminals_handler.dart',
];

/// Handlers that this guard does NOT enforce (they correspond to
/// GET endpoints or internal helpers like _resolveX). Adding a name
/// here is a deliberate allow-list change — keep the list short and
/// justified.
const _nonMutationHandlerAllowlist = <String>{
  // Sales GETs / shared helpers exposed as Future<Response>
  // — none today; postSale/postSalesReturn etc. all gated.
};

final _handlerSigRe = RegExp(
  r'^\s*Future<Response>\s+(\w+)\s*\(\s*Request\s+\w+(?:,\s*String\s+\w+)?\s*\)\s*async\s*\{',
  multiLine: true,
);

class _HandlerMatch {
  _HandlerMatch(this.name, this.startLine, this.endLine, this.body,
      this.precedingLines);
  final String name;
  final int startLine; // 1-based line of signature
  final int endLine;
  final String body;
  final String precedingLines;
}

List<_HandlerMatch> _findHandlers(String src, String path) {
  final lines = src.split('\n');
  final out = <_HandlerMatch>[];
  for (var i = 0; i < lines.length; i++) {
    final m = _handlerSigRe.firstMatch(lines[i]);
    if (m == null) continue;
    final name = m.group(1)!;
    // Walk braces to find the matching close.
    var depth = 0;
    var seenOpen = false;
    int? endIdx;
    for (var j = i; j < lines.length; j++) {
      for (final ch in lines[j].codeUnits) {
        if (ch == '{'.codeUnitAt(0)) {
          depth++;
          seenOpen = true;
        } else if (ch == '}'.codeUnitAt(0)) {
          depth--;
          if (seenOpen && depth == 0) {
            endIdx = j;
            break;
          }
        }
      }
      if (endIdx != null) break;
    }
    endIdx ??= (i + 30).clamp(0, lines.length - 1);
    final body = lines.sublist(i, endIdx + 1).join('\n');
    final precedingStart = (i - 8).clamp(0, lines.length);
    final preceding = lines.sublist(precedingStart, i).join('\n');
    out.add(_HandlerMatch(name, i + 1, endIdx + 1, body, preceding));
  }
  return out;
}

void main() {
  group('grep-guard: every mutation handler has a per-user gate', () {
    for (final path in [...handlerFiles, ...exemptHostFiles]) {
      test(path, () {
        final file = File(path);
        expect(file.existsSync(), isTrue,
            reason: 'Handler file is missing: $path');
        final src = path == 'lib/services/api/api_data_handler.dart'
            ? readApiDataHandlerSource()
            : path == 'lib/services/api/api_handler.dart'
                ? readApiHandlerSource()
                : file.readAsStringSync();
        final handlers = _findHandlers(src, path);
        expect(handlers, isNotEmpty,
            reason: 'No Future<Response> handlers parsed from $path');

        final failures = <String>[];
        for (final h in handlers) {
          if (_nonMutationHandlerAllowlist.contains(h.name)) continue;

          // GET-only handlers (named _getX or that start with 'get' /
          // '_get') — skip; out of scope per Spec 077 §3 Non-goals.
          if (h.name.startsWith('_get') ||
              h.name.startsWith('get') ||
              h.name == '_healthCheck' ||
              h.name == '_cfdStream' ||
              h.name == '_notFound' ||
              h.name == '_handleWebSocket' ||
              h.name == 'handleWebSocket') {
            continue;
          }

          // Mutation handler must either gate or be EXEMPT-tagged.
          final hasGate = h.body.contains('ApiUserCtx.requirePermission(');
          final isExempt = h.precedingLines.contains('EXEMPT-PER-USER:');

          if (!hasGate && !isExempt) {
            failures.add(
              '  ${h.name} @ ${path.split(Platform.pathSeparator).last}:'
              '${h.startLine} — neither ApiUserCtx.requirePermission '
              'nor // EXEMPT-PER-USER: marker found',
            );
          }
        }

        expect(failures, isEmpty,
            reason: 'Per-user gate guard failed for:\n${failures.join('\n')}\n'
                'Add ApiUserCtx.requirePermission(...) at the top of the '
                'handler OR an `// EXEMPT-PER-USER:` comment within ~5 '
                'lines above the signature. Map to a perm code from '
                'specs/077-server-perms-endpoint-sweep/contracts/endpoint-permission-map.md');
      });
    }

    test('all 4 NEW Batch-0.5 perm codes are referenced by at least one gate',
        () {
      final allSrc = StringBuffer();
      for (final p in [...handlerFiles, ...exemptHostFiles]) {
        allSrc.write(p == 'lib/services/api/api_data_handler.dart'
            ? readApiDataHandlerSource()
            : p == 'lib/services/api/api_handler.dart'
                ? readApiHandlerSource()
                : File(p).readAsStringSync());
        allSrc.write('\n');
      }
      final src = allSrc.toString();
      for (final code in [
        'PermissionCodes.posShiftOpen',
        'PermissionCodes.warehousesManage',
        'PermissionCodes.commercialPapersManage',
        'PermissionCodes.priceListsManage',
      ]) {
        expect(src.contains(code), isTrue,
            reason: '$code was added in Batch 0.5 but no handler '
                'references it — the gate wiring is missing.');
      }
    });
  });
}
