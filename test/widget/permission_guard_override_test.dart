// ═══════════════════════════════════════════════════════════════════════════
// `PermissionGuard(allowManagerOverride: true)` — running the action AFTER a
// manager approves.
//
// When the signed-in user lacks the permission, the guard renders the child
// inside an `AbsorbPointer` and handles the tap itself, so once a manager
// approves it must know what to run. The only mechanism was guessing the
// child's widget type — and on an unrecognised type it fell back to an EMPTY
// closure, which made `!= null` true and "succeeded" by doing nothing.
//
// `ListTile` was not in that list, and every «الأدوار والصلاحيات» /
// «إدارة المستخدمين» entry in both settings screens is a ListTile. Symptom:
// the cashier tapped, entered the manager password, the dialog closed, and
// nothing opened — indistinguishable from being refused.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/widgets/permission_guard.dart';

void main() {
  VoidCallback marker(List<String> log, String tag) => () => log.add(tag);

  group('extractChildAction — child types that must be reachable', () {
    test('ListTile — the type the reported bug was about', () {
      final log = <String>[];
      final action = extractChildAction(
        ListTile(title: const Text('إدارة صلاحيات الأدوار'),
            onTap: marker(log, 'tapped')),
      );

      expect(action, isNotNull,
          reason: 'a null here is exactly the silent dead-end being fixed');
      action!();
      expect(log, ['tapped']);
    });

    test('ElevatedButton', () {
      final log = <String>[];
      final action = extractChildAction(
        ElevatedButton(onPressed: marker(log, 'x'), child: const Text('t')),
      );
      expect(action, isNotNull);
      action!();
      expect(log, ['x']);
    });

    test('TextButton / OutlinedButton / IconButton', () {
      expect(
        extractChildAction(
            TextButton(onPressed: () {}, child: const Text('t'))),
        isNotNull,
      );
      expect(
        extractChildAction(
            OutlinedButton(onPressed: () {}, child: const Text('t'))),
        isNotNull,
      );
      expect(
        extractChildAction(
            IconButton(onPressed: () {}, icon: const Icon(Icons.add))),
        isNotNull,
      );
    });

    test('InkWell / InkResponse / GestureDetector', () {
      expect(extractChildAction(InkWell(onTap: () {})), isNotNull);
      expect(extractChildAction(InkResponse(onTap: () {})), isNotNull);
      expect(extractChildAction(GestureDetector(onTap: () {})), isNotNull);
    });

    test('recurses through layout wrappers', () {
      final log = <String>[];
      final action = extractChildAction(
        Padding(
          padding: EdgeInsets.zero,
          child: SizedBox(
            child: Center(
              child: ListTile(title: const Text('t'), onTap: marker(log, 'deep')),
            ),
          ),
        ),
      );

      expect(action, isNotNull);
      action!();
      expect(log, ['deep'],
          reason: 'settings entries are usually wrapped in layout widgets');
    });

    test('recurses through Tooltip / MouseRegion / Semantics', () {
      expect(
        extractChildAction(Tooltip(message: 'm', child: InkWell(onTap: () {}))),
        isNotNull,
      );
      expect(
        extractChildAction(MouseRegion(child: InkWell(onTap: () {}))),
        isNotNull,
      );
      expect(
        extractChildAction(Semantics(child: InkWell(onTap: () {}))),
        isNotNull,
      );
    });
  });

  group('extractChildAction — honest failure', () {
    test('returns null for a child that carries no action', () {
      // MUST be null, not an empty closure. The caller distinguishes "found
      // nothing" from "found something" purely on null, and reports the former
      // instead of pretending the action ran.
      expect(extractChildAction(const Text('no callback anywhere')), isNull);
    });

    test('returns null for an unknown custom widget', () {
      expect(extractChildAction(const _CustomTile()), isNull,
          reason: 'call sites with custom children must pass onGranted');
    });

    test('propagates a genuinely disabled button as null', () {
      // A button with `onPressed: null` is disabled. Approval must not
      // fabricate an action for it.
      expect(
        extractChildAction(
            const ElevatedButton(onPressed: null, child: Text('t'))),
        isNull,
      );
    });
  });

  group('PermissionGuard wiring', () {
    testWidgets('accepts onGranted without needing to inspect the child',
        (tester) async {
      // The escape hatch: the action is stated explicitly, so a child of ANY
      // shape works — including one carrying no callback at all.
      var granted = false;

      final guard = PermissionGuard(
        permission: 'x',
        allowManagerOverride: true,
        actionName: 'اختبار',
        onGranted: () => granted = true,
        child: const Text('t'),
      );

      expect(guard.onGranted, isNotNull);
      guard.onGranted!();
      expect(granted, isTrue);
      await tester.pump();
    });
  });
}

class _CustomTile extends StatelessWidget {
  const _CustomTile();

  @override
  Widget build(BuildContext context) => const Text('custom');
}
