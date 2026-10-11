// ═══════════════════════════════════════════════════════════════════════════
// SPEC 083 — Cash deficit/surplus JE attribution by safe name
// ═══════════════════════════════════════════════════════════════════════════
//
// Pre-fix: shift-close variance JE in `_postVarianceJournalEntry` emitted
//   header = 'قيد فرق إقفال وردية #N'
//   line   = 'تعديل نقدية — عجز'   (and friends)
// — no safe attribution. Multi-safe installs couldn't tell which till had
// the shortage from the GL view.
//
// Post-fix: `primarySafe?.name` is interpolated into the header and into
// each of the 4 line descriptions (shortage Dr/Cr + surplus Dr/Cr). The
// suffix is null-safe — falls back to the unattributed format when
// primarySafe is null (legacy installs).
//
// These are source-string grep guards (cheaper than spinning up a full
// shift-close end-to-end) because the change is purely a description-text
// format. Any future refactor that drops the suffix will fail here loudly.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spec 083 — shift-close variance JE includes safe name', () {
    late String src;

    setUpAll(() {
      src = File('lib/data/database/daos/treasury_shift_settlement_dao.dart').readAsStringSync();
    });

    test('safeSuffix is derived from primarySafe?.name and null-safe', () {
      // The exact one-liner that builds the suffix. Pin its shape so any
      // refactor that drops the null-safety or renames the variable
      // surfaces here.
      expect(src, contains('final safeName = primarySafe?.name;'),
          reason: 'primarySafe.name must be read null-safely — legacy installs '
              'with no pos_cash_safe_id setting must still close shifts');
      expect(
          src,
          contains(
              "final safeSuffix = safeName != null ? ' — \$safeName' : '';"),
          reason: 'safeSuffix template must collapse to empty when safeName '
              'is null so the legacy unattributed description still works');
    });

    test('JE header description includes safeSuffix', () {
      // Pre-fix: 'قيد فرق إقفال وردية #\$shiftId'
      // Post-fix: 'قيد فرق إقفال وردية #\$shiftId\$safeSuffix'
      expect(
          src,
          contains("description: 'قيد فرق إقفال وردية #\$shiftId\$safeSuffix',"),
          reason: 'JE header must carry the safe attribution so دفتر اليومية '
              'shows WHICH till had the variance, not just the shift number');
    });

    test('shortage line descriptions include safeSuffix (both Dr and Cr)', () {
      // Dr عجز صندوق
      expect(
          src,
          contains(
              "description: 'عجز صندوق — إقفال وردية #\$shiftId\$safeSuffix',"),
          reason: 'Shortage Dr line must name the safe');
      // Cr تعديل نقدية — عجز (this is the EXACT line the user complained
      // about in the GL screenshot)
      expect(src, contains("description: 'تعديل نقدية — عجز\$safeSuffix',"),
          reason: 'Shortage Cr line — the one visible in the GL screenshot '
              '— must include the safe name. This is the precise bug the '
              'user reported.');
    });

    test('surplus line descriptions include safeSuffix (both Dr and Cr)', () {
      expect(
          src,
          contains(
              "description: 'فائض نقدية — إقفال وردية #\$shiftId\$safeSuffix',"),
          reason: 'Surplus Dr line must name the safe');
      expect(
          src,
          contains("description: 'فائض صندوق — إقفال وردية\$safeSuffix',"),
          reason: 'Surplus Cr line must name the safe');
    });

    test('legacy pre-fix descriptions are gone (regression guard)', () {
      // These exact pre-fix strings must NOT survive — if a future refactor
      // accidentally restores the unattributed form, this test catches it.
      expect(src, isNot(contains("description: 'تعديل نقدية — عجز',")),
          reason: 'Pre-fix unattributed shortage Cr description must not '
              'reappear — that is the regression we are guarding against');
      expect(src, isNot(contains("description: 'فائض صندوق — إقفال وردية',")),
          reason: 'Pre-fix unattributed surplus Cr description must not '
              'reappear');
    });
  });
}
