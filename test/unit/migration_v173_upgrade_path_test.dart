// v173 على **مسار الترقية** — لا على التنصيبة الجديدة.
//
// ═══ لماذا ملفٌّ ثانٍ ═══
//
// `migration_v173_regulatory_sync_test` يقيس `AppDatabase.forTesting()`، وهي
// تبني بـ`createAll` من كيانات drift **ولا تمرّ بـ`onUpgrade` إطلاقاً**.
// فالأعمدةُ تظهر هناك حتى لو كانت خطوةُ الهجرة معطَّلةً بالكامل.
//
// وخطوةُ v173 كلُّها ملفوفةٌ في `try/catch` تطبع وتمضي (‏وهو الصحيح: عمودٌ
// موجودٌ سلفاً يجب ألّا يُسقط الإقلاع). لكنّ الوجهَ الآخرَ أنّ إخفاقاً
// **حقيقيّاً** يُبتلَع بنفس الطريقة، وتُختَم القاعدةُ بالرقم الجديد بلا
// أعمدة — وهي سابقةٌ مسجَّلةٌ في هذا المستودع أكثرَ من مرّة (v161 وv165).
// فالقاعدةُ المُرقّاةُ تصير: `pullTables` فيها الجدولُ، و`_upsertRow` يبتلع
// خطأَ العمود المفقود بـ`debugPrint`، فلا صفَّ يصل ولا اختبارَ يحمرّ.
//
// ═══ ما يُقاس ═══
//
//  ‏١) جدولٌ بشكلِ ما قبلَ v173 (بلا عمودِ مزامنةٍ واحد) ⇒ الترقيةُ تُضيف
//     الخمسةَ فعلاً.
//  ‏٢) 🔴 **والتعبئةُ تملأ الصفوفَ القائمة**: صفٌّ كُتب قبل الترقية يخرج
//     بـ`global_id` غيرِ فارغ. بلا ذلك يبقى كلُّ صفٍّ تاريخيٍّ بلا هويّةٍ
//     فلا يُطابَق على الخادم أبداً — ويُدرَج مكرَّراً عند أوّل دفع.
//  ‏٣) **والمُشغِّلُ يُركَّب على الجدول المُرقّى** لا على المبنيِّ حديثاً.
//  ‏٤) ومرساةٌ سالبة: التجهيزةُ تبدأ **بلا** الأعمدة، وإلّا لم تقس شيئاً.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

/// شكلُ `bank_reconciliations` قبلَ v173 — بلا أعمدة المزامنة الخمسة.
const _preV173BankReconciliations = '''
CREATE TABLE "bank_reconciliations" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "bank_account_id" INTEGER NOT NULL REFERENCES accounts (id),
  "period_start" INTEGER NOT NULL,
  "period_end" INTEGER NOT NULL,
  "statement_balance" REAL NOT NULL,
  "book_balance" REAL NOT NULL,
  "difference" REAL NOT NULL DEFAULT 0,
  "total_matched" INTEGER NOT NULL DEFAULT 0,
  "total_unmatched" INTEGER NOT NULL DEFAULT 0,
  "status" TEXT NOT NULL DEFAULT 'draft',
  "prepared_by" INTEGER NULL,
  "completed_at" INTEGER NULL,
  "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
)''';

/// وجدولٌ ثانٍ من فئةٍ أخرى — كي لا يُقاس نجاحُ الحلقة على عنصرٍ واحد.
const _preV173ComplianceChecks = '''
CREATE TABLE "compliance_checks" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "category" TEXT NOT NULL,
  "check_name" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "details" TEXT NULL,
  "score" REAL NOT NULL DEFAULT 0,
  "last_checked_at" INTEGER NULL,
  "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
)''';

const _syncColumns = <String>[
  'global_id',
  'last_modified_at',
  'deleted_at',
  'origin_client_id',
  'row_version',
];

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    // أعِد بناءَ الجدولَين بشكلِ ما قبلَ v173، مع صفٍّ قائمٍ في كلٍّ منهما.
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement('DROP TABLE bank_reconciliations');
    await db.customStatement(_preV173BankReconciliations);
    await db.customStatement('DROP TABLE compliance_checks');
    await db.customStatement(_preV173ComplianceChecks);
    await db.customStatement(
      "INSERT INTO bank_reconciliations "
      "(id, bank_account_id, period_start, period_end, statement_balance, "
      " book_balance) VALUES (1, 1, 100, 200, 500.0, 480.0)",
    );
    await db.customStatement(
      "INSERT INTO compliance_checks (id, category, check_name, description) "
      "VALUES (1, 'vat', 'فحصٌ قديم', 'صفٌّ سبق الترقية')",
    );
    await db.customStatement('PRAGMA foreign_keys = ON');
  });

  // لا `db.close()`: مؤقّتُ drift ينتظر في المنطقة الوهميّة فيعلّق الاختبار.
  tearDown(() async {});

  Future<Set<String>> columnsOf(String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.data['name'] as String).toSet();
  }

  test('مرساة سالبة: التجهيزةُ تبدأ بلا أعمدةِ المزامنة', () async {
    final cols = await columnsOf('bank_reconciliations');
    expect(cols, contains('statement_balance'),
        reason: 'مرساةٌ موجبة: الجدولُ أُعيد بناؤه فعلاً');
    for (final c in _syncColumns) {
      expect(cols.contains(c), isFalse,
          reason: 'العمودُ $c موجودٌ قبلَ الترقية ⇒ الاختبارُ لا يقيس شيئاً');
    }
  });

  test('🔴 الترقيةُ 172 ← 173 تُضيف الأعمدةَ الخمسةَ على الجدولَين', () async {
    await db.runOnUpgrade(Migrator(db), 172, 173);

    expect(await columnsOf('bank_reconciliations'), containsAll(_syncColumns),
        reason: 'الخطوةُ ملفوفةٌ في try/catch تبتلع الإخفاقَ وتمضي — فتُختَم '
            'القاعدةُ ١٧٣ بلا أعمدة، و`_upsertRow` يبتلع خطأَ العمود المفقود '
            'فلا صفَّ يصل ولا اختبارَ يحمرّ.');
    expect(await columnsOf('compliance_checks'), containsAll(_syncColumns),
        reason: 'الحلقةُ توقّفت عند أوّل جدول؟');
  });

  test('🔴 والتعبئةُ تُعطي الصفَّ القائمَ هويّةً — لا تتركه فارغاً', () async {
    await db.runOnUpgrade(Migrator(db), 172, 173);

    for (final t in const ['bank_reconciliations', 'compliance_checks']) {
      final row = (await db
              .customSelect('SELECT global_id FROM $t WHERE id = 1')
              .get())
          .single
          .data;
      final gid = row['global_id'] as String?;
      expect(gid, isNotNull,
          reason: 'صفُّ $t التاريخيُّ بلا هويّة ⇒ لا يُطابَق على الخادم '
              'أبداً، ويُدرَج مكرَّراً عند أوّل دفع.');
      expect(gid, isNotEmpty);
    }
  });

  test('والمُشغِّلُ يُركَّب على الجدول المُرقّى ويرفع النسخة', () async {
    await db.runOnUpgrade(Migrator(db), 172, 173);

    final before = (await db
            .customSelect(
                'SELECT row_version, last_modified_at FROM bank_reconciliations '
                'WHERE id = 1')
            .get())
        .single
        .data;
    expect(before['row_version'], 0);
    expect(before['last_modified_at'], isNull,
        reason: 'صفٌّ قديمٌ يبدأ بلا ختمِ زمن');

    await db.customStatement(
      "UPDATE bank_reconciliations SET status = 'completed' WHERE id = 1",
    );

    final after = (await db
            .customSelect(
                'SELECT row_version, last_modified_at FROM bank_reconciliations '
                'WHERE id = 1')
            .get())
        .single
        .data;
    expect(after['row_version'], 1,
        reason: 'المُشغِّلُ لم يُركَّب ⇒ `row_version` رقمٌ ميّتٌ يبدو صحيحاً '
            'في أيّ فحصِ مخطَّط، وإقفالُ المطابقة لا يصل جهازاً آخر.');
    expect(after['last_modified_at'], isNotNull,
        reason: 'بلا ختمِ زمنٍ لا يلتقط سحبُ الدلتا الصفَّ');
  });

  test('وإعادةُ تشغيل الخطوة لا تُفسد شيئاً — الترقيةُ متحايدة', () async {
    // قاعدةٌ رُقّيت ثمّ أُعيد تشغيلُ الخطوة (يقع فعلاً: حرّاسٌ تُرفَع إلى رقمٍ
    // واحدٍ فتمرّ بها كلُّ قاعدةٍ تحته).
    await db.runOnUpgrade(Migrator(db), 172, 173);
    final gidBefore = (await db
            .customSelect('SELECT global_id FROM bank_reconciliations WHERE id = 1')
            .get())
        .single
        .data['global_id'] as String?;

    await db.runOnUpgrade(Migrator(db), 172, 173);

    final gidAfter = (await db
            .customSelect('SELECT global_id FROM bank_reconciliations WHERE id = 1')
            .get())
        .single
        .data['global_id'] as String?;
    expect(gidAfter, gidBefore,
        reason: 'التعبئةُ سكّت هويّةً جديدةً لصفٍّ له هويّة ⇒ الخادمُ يراه '
            'صفّاً مختلفاً فيُدرِجه مكرَّراً.');
    expect(await columnsOf('bank_reconciliations'), containsAll(_syncColumns));
  });
}
