// ═══════════════════════════════════════════════════════════════════════════
// مزامنةُ الصلاحيّات كانت تموت صامتةً في كلِّ إقلاعٍ على PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════
//
// اتّصالُ PostgreSQL مُعترَضٌ بـ`_PgCompatInterceptor` الذي يترجم كلَّ SQL خامّ
// — ومنه **علامةُ الاستفهام** `? → $1, $2, …` (‏`PgCompatSql.fixSql` خطوة ١٠).
// لكنّ ما يعمل داخلَ `beforeOpen` **لا يمرُّ بالمُعترِض**.
//
// والمقيسُ في سياق الإقلاع نفسِه قبل الإصلاح:
//     SELECT ?  AS a   ⇒ 42601: syntax error at or near "AS"
//     SELECT $1 AS a   ⇒ يعمل
// ونفسُ الجملتين خارجَه تعملان — فالفارقُ السياقُ لا الجملة.
//
// ── الأثرُ الذي يراه المشغّل ───────────────────────────────────────────────
//
// `syncAllPermissions` تُدرج صلاحيّاتِ `masterList` وتمنح الجديدَ منها لمدير
// النظام، وتعمل في `beforeOpen`. فكانت تموت عند **أوّل** إدراج، ومعها
// `grantMissingDefaults` (أوّلُ سطرٍ فيها ينادي الأولى) — وكلاهما مبتلَعٌ في
// `catch` يطبع سطراً ويمضي.
//
// فالتنصيبُ الأوّلُ يبقى سليماً (معالجُ البدء يبذر خارجَ `beforeOpen`)، لكنّ
// **أيَّ صلاحيّةٍ تضيفها نسخةٌ لاحقةٌ لا تصل قاعدةَ PostgreSQL أبداً** ولا
// تُمنَح لمدير النظام — وشفاءُ المنح الذاتيُّ الموضوعُ لإصلاح ذلك ميّت.
//
// ⚠️ **والقياسُ على عدد الصفوف بعد إقلاعٍ كامل** — لا على نجاح جملةٍ مفردة:
// الإخفاقُ كان مبتلَعاً، فنجاحُ الإقلاع لم يكن دليلاً قطُّ.
//
// ⚠️ يعمل عبر `melos test:pg` وحدَه.

@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database.dart';

import '_support/pg_fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    final fx = await bootPgTestSchema();
    addTearDown(fx.tearDown);
    db = fx.db;
    await db.select(db.accounts).get(); // تُجبر الهجرةَ ومسارَ الإقلاع
  });

  test('🔴 الإقلاعُ على PostgreSQL يملأ جدولَ الصلاحيّات', () async {
    final perms = await db.select(db.permissions).get();

    // مرساة: السجلُّ نفسُه غيرُ فارغ، وإلّا كان «صفرٌ == صفر» يمرُّ زوراً.
    expect(PermissionCodes.masterList, isNotEmpty,
        reason: 'مرساة: قائمةُ الصلاحيّات المصدرُ ليست فارغة');

    expect(perms.length, PermissionCodes.masterList.length,
        reason: 'كان الجدولُ يخرج **فارغاً تماماً**: أوّلُ إدراجٍ يرمي 42601 '
            'لأنّ علامةَ `?` لا تُترجَم داخلَ `beforeOpen`، والإخفاقُ مبتلَع');
  });

  test('علامةُ `?` تُترجَم في SQL الخامّ على PG', () async {
    // الجملةُ التي كانت تسقط بعينها — والقياسُ على النتيجة لا على غياب الرمي.
    final row = await db
        .customSelect('SELECT ? AS a, ? AS b',
            variables: const [Variable<int>(7), Variable<int>(9)])
        .getSingle();

    expect(row.data['a'], 7);
    expect(row.data['b'], 9);
  });

  // 🔴 والأثرُ أوسعُ من الصلاحيّات: **بذرُ الإقلاع كلُّه** كان يموت صامتاً على
  //    PostgreSQL لنفس السبب — فتخرج قاعدةٌ بلا مديرِ نظامٍ ولا أدوار، بينما
  //    SQLite تبذرهما. وهذا الفحصُ يقفل التوحيدَ بين الخلفيّتين.
  test('🔴 الإقلاعُ على PostgreSQL يبذر مديرَ النظام ودورَه', () async {
    final users = await db.select(db.users).get();
    final roles = await db.select(db.roles).get();

    expect(users, isNotEmpty,
        reason: 'كان الجدولُ يخرج فارغاً على PG وحدَها — بذرٌ ميّتٌ صامت');
    expect(roles, isNotEmpty, reason: 'ولا أدوارَ معه');
  });

  test('ومدير النظام يُمنَح الصلاحيّاتِ غيرَ الحسّاسة', () async {
    final admin = await (db.select(db.roles)
          ..where((r) => r.name.equals('مدير النظام')))
        .get();
    if (admin.isEmpty) {
      // تجهيزةُ الاختبار قد لا تبذر الأدوار — لا يُدّعى ما لا يُقاس.
      return;
    }

    final granted = await db.getPermissionsForRole(admin.first.id);
    expect(granted, isNotEmpty,
        reason: 'حلقةُ المنح تلي حلقةَ الإدراج في نفس الدالّة — '
            'فسقوطُ الأولى كان يمنع الثانية كلَّها');
  });
}
