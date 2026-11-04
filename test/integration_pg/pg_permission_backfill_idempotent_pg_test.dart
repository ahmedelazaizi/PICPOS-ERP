// الإقلاعُ على PostgreSQL: ترحيلاتُ منح الصلاحيّات (journal approval، return
// approve، hr attendance، hr payroll) كانت تطبع
// `permission backfill failed: 23505 role_permissions_pkey` لأنّ drift يُسقط
// insertOrIgnore على postgres. الإصلاح: `onConflict: DoNothing(target: [])`.
// + DeltaPullColumnFilter يكتشف الأعمدة عبر information_schema على PG.

@Tags(['pg'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/delta_pull_column_filter.dart';

import '_support/pg_fixture.dart';

const _flags = [
  'approve_journal_backfill_done',
  'return_approve_backfill_done',
  'hr_attendance_perm_backfill_done',
  'hr_payroll_perm_backfill_done',
];

Future<int> _count(AppDatabase db) async => (await db
        .customSelect('SELECT count(*) AS c FROM role_permissions')
        .getSingle())
    .read<int>('c');

void main() {
  test('إعادةُ تشغيل ترحيلات المنح لا ترمي ولا تضاعف الصفوف', () async {
    final fx = await bootPgTestSchema();
    addTearDown(fx.tearDown);
    var db = fx.db;
    await db.select(db.accounts).get();

    // بذرُ منحٍ يجعل الأهدافَ موجودةً مسبقاً ⇒ التكرارُ حتميّ عند إعادة التشغيل.
    await db.customStatement(
      'INSERT INTO roles (name) VALUES (?) ON CONFLICT DO NOTHING',
      ['probe_role'],
    );
    final roleId = (await db
            .customSelect("SELECT id FROM roles WHERE name = 'probe_role'")
            .getSingle())
        .read<int>('id');
    await db.customStatement(
      'INSERT INTO role_permissions (role_id, permission_id) '
      "SELECT ?, id FROM permissions WHERE code IN "
      "('hr_view','hr_manage','hr_payroll_process','hr_advance_record',"
      "'sales_return_view','purchases_return_view')"
      ' ON CONFLICT DO NOTHING',
      [roleId],
    );

    final logs = <String>[];
    final oldPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {
      if (m != null) logs.add(m);
    };
    addTearDown(() => debugPrint = oldPrint);

    // مرّتان: الأولى تمنح، الثانية بعد مسح الأعلام تصطدم بكلِّ ما مُنح.
    for (var i = 0; i < 2; i++) {
      for (final f in _flags) {
        await db.customStatement('DELETE FROM settings WHERE key = ?', [f]);
      }
      await db.backfillJournalApprovalPermissionOnce();
      await db.backfillReturnApprovePermissionsOnce();
      await db.backfillHrAttendancePermissionsOnce();
      await db.backfillHrPayrollPermissionsOnce();
    }
    final afterSecond = await _count(db);

    // وإقلاعٌ كاملٌ ثانٍ بعد مسح الأعلام (مسار beforeOpen الحقيقي).
    for (final f in _flags) {
      await db.customStatement('DELETE FROM settings WHERE key = ?', [f]);
    }
    await db.close();
    db = openExtraPgConnection();
    addTearDown(db.close);
    await db.select(db.accounts).get();

    expect(logs.where((l) => l.contains('backfill failed')), isEmpty);
    expect(await _count(db), afterSecond, reason: 'عددُ الصفوف ثابت');
    expect(afterSecond, greaterThan(0));
  });

  test('DeltaPullColumnFilter يعمل على PG ولا يُفسد المعاملة', () async {
    final fx = await bootPgTestSchema();
    addTearDown(fx.tearDown);
    final db = fx.db;
    await db.select(db.accounts).get();

    final filter = DeltaPullColumnFilter();
    await db.transaction(() async {
      final out = await filter.apply(db, 'permissions', {
        'code': 'x',
        'name': 'n',
        'no_such_column_zzz': 1,
      });
      expect(out.keys.toSet(), {'code', 'name'});
      // المعاملة ما زالت سليمة (PRAGMA كان يُفسدها بـ42601).
      final r = await db.customSelect('SELECT 1 AS one').getSingle();
      expect(r.read<int>('one'), 1);
    });

    // جدولٌ مجهول ⇒ الصفُّ كما هو.
    final raw = {'a': 1};
    expect(await filter.apply(db, 'no_such_table_zzz', raw), raw);
  });
}
