// ═══════════════════════════════════════════════════════════════════════════
// SPEC 097 — Dev Tools _ChangeModeSection has the 4th mirror segment
// ═══════════════════════════════════════════════════════════════════════════
//
// Before Spec 097 the SegmentedButton in Developer Tools' _ChangeModeSection
// rendered only 3 options (standalone/server/client). Mirror was reachable
// ONLY from the Setup Wizard. These source pins enforce the 4th option
// and the inline pairing-dialog launch on first selection.
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
    test('imports MirrorState + MirrorPairingDialog', () {
      expect(devToolsSrc, contains("import '../../services/mirror_state.dart'"),
          reason: 'Pairing-gate check needs MirrorState.isConfigured.');
      expect(
          devToolsSrc,
          contains(
              "import '../widgets/settings/mirror_pairing_dialog.dart'"),
          reason: 'The 4th-option apply path opens MirrorPairingDialog.');
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

    test('_apply opens MirrorPairingDialog when target is mirror + unconfigured',
        () {
      // Scope to _ChangeModeSection — there's also a profile-section _apply.
      final sectionStart =
          devToolsSrc.indexOf('class _ChangeModeSectionState');
      expect(sectionStart, isNot(-1),
          reason: 'The mode-section State class must exist.');
      final applyStart =
          devToolsSrc.indexOf('Future<void> _apply() async {', sectionStart);
      expect(applyStart, isNot(-1));
      final body = devToolsSrc.substring(applyStart, applyStart + 1800);

      // The gating predicate must check BOTH "target = mirror" AND
      // "MirrorState not configured". Without the second clause we'd
      // re-prompt on every mode-flip back to mirror.
      expect(body, contains('DeploymentMode.mirror'));
      expect(body, contains('MirrorState.instance.isConfigured'));
      expect(body, contains('MirrorPairingDialog.show'));

      // If pairing fails, the UI must revert _selected so the segmented
      // control matches the actual current mode — otherwise a stuck
      // "selected mirror" state lies to the operator.
      expect(body, contains('widget.snapshot.mode'),
          reason: 'Revert path must restore the original mode on failure.');
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
