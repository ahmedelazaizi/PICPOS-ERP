// ═══════════════════════════════════════════════════════════════════════════
// SPEC 097 — Dev Tools _ChangeModeSection has the 4th mirror segment
// ═══════════════════════════════════════════════════════════════════════════
//
// Before Spec 097 the SegmentedButton in Developer Tools' _ChangeModeSection
// rendered only 3 options (standalone/server/client). Mirror was reachable
// ONLY from the Setup Wizard. These source pins enforce the 4th option
// (A1 update: applying a target no longer opens a pairing dialog; every target
// goes through "re-provision this device" - see the pins below.)
//
// _ChangeModeSection is a private widget so we pin via source — same
// pattern as `spec_088_admin_bypass_test.dart`.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final devToolsSrc =
      File('lib/presentation/screens/developer_tools_screen.dart')
          .readAsStringSync();
  final dialogSrc =
      File('lib/presentation/widgets/settings/mirror_pairing_dialog.dart')
          .readAsStringSync();

  group('Spec 097 — Dev Tools _ChangeModeSection', () {
    // A1 (intentional redesign): the section no longer pairs/switches in place.
    // Every target (mirror included) goes through "re-provision this device",
    // so the pairing dialog + MirrorState gate are gone from this screen.
    test('imports the re-provision confirm dialog, not MirrorPairingDialog', () {
      expect(devToolsSrc,
          contains("import 'first_run/reprovision_confirm_dialog.dart'"),
          reason: 'The apply path asks confirmReprovision.');
      expect(devToolsSrc, isNot(contains('mirror_pairing_dialog.dart')),
          reason: 'No direct mirror pairing path from Developer Tools.');
      expect(devToolsSrc, isNot(contains('MirrorPairingDialog')));
    });

    test('renders 4 ButtonSegment values including DeploymentMode.mirror', () {
      // Locate the SegmentedButton block in _ChangeModeSection.
      final start = devToolsSrc.indexOf('SegmentedButton<DeploymentMode>');
      expect(start, isNot(-1),
          reason: 'The toggle segment widget must exist.');
      final block = devToolsSrc.substring(start, start + 1200);

      expect(block, contains('DeploymentMode.standalone'));
      expect(block, contains('DeploymentMode.server'));
      expect(block, contains('DeploymentMode.client'));
      expect(block, contains('DeploymentMode.mirror'),
          reason: 'The 4th first-class mode must appear as a segment.');
      // All four labels in Arabic.
      expect(block, contains("Text(tr('مستقل'))"));
      expect(block, contains("Text(tr('سيرفر'))"));
      expect(block, contains("Text(tr('عميل'))"));
      expect(block, contains("Text(tr('مرآة'))"));
    });

    test('_apply sends EVERY target (mirror included) through re-provision; '
        'no direct mode switch, no pairing dialog', () {
      // Scope to _ChangeModeSection — there's also a profile-section _apply.
      final sectionStart =
          devToolsSrc.indexOf('class _ChangeModeSectionState');
      expect(sectionStart, isNot(-1),
          reason: 'The mode-section State class must exist.');
      final applyStart =
          devToolsSrc.indexOf('Future<void> _apply() async {', sectionStart);
      expect(applyStart, isNot(-1));
      final applyEnd = devToolsSrc.indexOf('Widget build(', applyStart);
      expect(applyEnd, greaterThan(applyStart));
      final body = devToolsSrc.substring(applyStart, applyEnd);

      // Confirm first, then re-provision (the committed choice is made in the
      // first-run flow after the restart).
      final confirm = body.indexOf('confirmReprovision(context)');
      final reprovision =
          body.indexOf('provisioningActionsProvider).reprovision()');
      expect(confirm, isNot(-1));
      expect(reprovision, greaterThan(confirm),
          reason: 'reprovision() must run only after the operator confirmed.');

      // No target-specific branch: a mirror target is not special-cased.
      expect(body, isNot(contains('DeploymentMode.mirror')));
      expect(body, isNot(contains('MirrorState')));
      expect(body, isNot(contains('MirrorPairingDialog')));
      expect(body, isNot(contains('.setMode(')),
          reason: 'A1: the mode changes through re-provisioning only.');

      // A declined confirmation must revert _selected so the segmented
      // control matches the actual current mode.
      expect(body, contains('_selected = widget.snapshot.mode'),
          reason: 'Declined confirmation must restore the original mode.');
    });

    test('_modeLabel covers all 4 enum values', () {
      final start = devToolsSrc.indexOf('String _modeLabel(DeploymentMode m)');
      expect(start, isNot(-1));
      final body = devToolsSrc.substring(start, start + 400);
      expect(body, contains('DeploymentMode.standalone'));
      expect(body, contains('DeploymentMode.server'));
      expect(body, contains('DeploymentMode.client'));
      expect(body, contains('DeploymentMode.mirror'));
    });
  });

  group('Spec 097 — MirrorPairingDialog double-submit guard (R2)', () {
    test('declares _busy bool OUTSIDE the build method', () {
      // ENGINEERING_GUIDELINES.md R2: async DB writes need a guard declared at the State
      // level so concurrent taps cannot bypass it. Field bug pattern.
      final classStart =
          dialogSrc.indexOf('class _MirrorPairingDialogState');
      expect(classStart, isNot(-1));
      final classBody = dialogSrc.substring(classStart, classStart + 1500);
      expect(classBody, contains('bool _busy = false'),
          reason: 'R2: guard must be a State field, not a builder-local.');
    });

    test('_pair short-circuits when _busy is already true', () {
      final start = dialogSrc.indexOf('Future<void> _pair() async {');
      expect(start, isNot(-1));
      final body = dialogSrc.substring(start, start + 400);
      expect(body, contains('if (_busy) return'),
          reason: 'Re-entrant taps must be no-ops, not double-submits.');
    });

    test('uses MirrorPairingService.instance.pair (no inline duplication)',
        () {
      expect(dialogSrc, contains('MirrorPairingService.instance.pair('),
          reason: 'Pairing logic must come from the shared service so the '
              'wizard and the dialog cannot drift apart.');
    });
  });
}
