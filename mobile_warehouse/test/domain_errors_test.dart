// W14.4b: every refusal the host can answer on /api/m1/wh/* has its own
// message in the app (AR + EN); none falls to the generic `err_unknown`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_warehouse/l10n/strings.dart';
import 'package:picpos_warehouse/session/wh_session.dart';

import 'docs_flow_test.dart' show kSupervisor, openApp;
import 'fake_office.dart';

/// Codes the host can emit that the app deliberately shows through a
/// transport-level message instead of a document refusal (`errorCode` maps
/// them by [ApiErrorKind]). Each must still have an `err_` text.
const _kindMapped = {'device_scope', 'permission_denied'};

/// Codes only written to the host's logs / never answered to a phone.
/// (none today; add here with a reason rather than letting a code go unmapped)
const _internalOnly = <String>{};

final _codeLiteral = RegExp(r"""(?:WhError|_error|errorResponse)\(\s*(?:WhError\(\s*)?'(\w+)'|'error':\s*'(\w+)'""");

Set<String> _hostCodes() {
  final out = <String>{};
  final files = [
    ...Directory('../lib/services/api/m1_wh').listSync().whereType<File>().where((f) => f.path.endsWith('.dart')),
  ];
  for (final f in files) {
    for (final m in _codeLiteral.allMatches(f.readAsStringSync())) {
      out.add(m[1] ?? m[2]!);
    }
  }
  return out;
}

void main() {
  test('the scan finds the host codes it is meant to (self-check)', () {
    final codes = _hostCodes();
    expect(codes, containsAll(['overlapping_count_task', 'stale_overlap_count', 'recount_required', 'self_approval', 'stale', 'idempotency_conflict']));
  });

  test('every error code literal in lib/services/api/m1_wh has a specific message and is not err_unknown', () {
    final have = {for (final k in S.table.entries.keys) if (k.startsWith('err_')) k.substring(4)};
    final unmapped = <String>[];
    for (final c in _hostCodes().difference(_internalOnly)) {
      final code = errorCode(ApiError(kind: ApiErrorKind.rejected, code: c, status: 409));
      if (code == 'unknown' || !have.contains(code)) unmapped.add(c);
      if (!kDomainCodes.contains(c) && !_kindMapped.contains(c)) unmapped.add('$c (not in kDomainCodes)');
    }
    expect(unmapped, isEmpty, reason: 'add these to kDomainCodes + S.table (err_<code>)');
  });

  test('every domain code has an Arabic and an English text, both non-empty and different from the fallback', () {
    final unknown = S.table.entries['err_unknown']!;
    for (final c in kDomainCodes) {
      final v = S.table.entries['err_$c']!;
      expect(v.$1.trim(), isNotEmpty, reason: c);
      expect(v.$2.trim(), isNotEmpty, reason: c);
      expect(v.$1, isNot(unknown.$1), reason: c);
      expect(v.$2, isNot(unknown.$2), reason: c);
    }
  });

  group('approving a count the office refuses', () {
    const cases = <String, ({String ar, String en})>{
      'overlapping_count_task': (ar: 'جرد أقدم لنفس المخزن ونفس الصنف', en: 'older count of the same warehouse and item is still in progress'),
      'stale_overlap_count': (ar: 'يلزم إعادة العدّ', en: 'A recount is needed'),
      'recount_required': (ar: 'يلزم عدّ ثانٍ قبل الاعتماد', en: 'A recount is required before approval'),
      'self_approval': (ar: 'يعتمده شخص آخر', en: 'someone else must'),
      'stale': (ar: 'تغيّر المستند منذ آخر قراءة', en: 'changed since you read it'),
      'idempotency_conflict': (ar: 'استُعمل لطلب مختلف', en: 'already used for a different request'),
      'already_finalized': (ar: 'اعتُمد هذا الجرد سابقاً', en: 'already approved'),
      'warehouse_scope': (ar: 'خارج نطاق صلاحياتك', en: 'outside your scope'),
      'branch_access_denied': (ar: 'الفرع خارج نطاق صلاحياتك', en: 'branch is outside your access'),
    };

    for (final e in cases.entries) {
      for (final lang in ['en', 'ar']) {
        testWidgets('${e.key} shows its own $lang message, not the generic one', (tester) async {
          final office = FakeOffice()
            ..permissions = kSupervisor
            ..rejectWith = e.key;
          await openApp(tester, office, locale: Locale(lang));
          await tester.tap(find.byKey(const Key('doc.approvals')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('approval.T1')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('review.approve')));
          await tester.pumpAndSettle();

          final want = lang == 'en' ? e.value.en : e.value.ar;
          expect(find.textContaining(want), findsOneWidget);
          final generic = S.table.entries['err_unknown']!;
          expect(find.text(lang == 'en' ? generic.$2 : generic.$1), findsNothing);
        });
      }
    }
  });

  testWidgets('a count that needs a recount shows the notice and cannot be approved (inbox changed since it was listed)', (tester) async {
    final office = FakeOffice()
      ..permissions = kSupervisor
      ..review = {
        'ref': 'T1', 'warehouseId': 1, 'status': 'in_progress', 'passes': 1, 'recountNeeded': true, 'readyForApproval': false,
        'items': [
          {'productId': 5, 'name': 'Milk 1L', 'expected': '137', 'counted': '130', 'variance': '-7', 'movementsSinceCount': 0},
        ],
      };
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.approvals')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approval.T1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review.recount')), findsOneWidget);
    final btn = tester.widget<FilledButton>(find.byKey(const Key('review.approve')));
    expect(btn.onPressed, isNull);
  });
}
