// ═══════════════════════════════════════════════════════════════════════════
// §٦‑٢ على PostgreSQL — جدولُ مستند مرتجع الشراء
// ═══════════════════════════════════════════════════════════════════════════
//
// `purchase_returns` (v172) كيانُ drift، فـ`_createAllForPostgres` يبنيه على
// قاعدةٍ جديدة و`onUpgrade` متجاوَزٌ هناك — والخطوةُ v172 للقواعد المُرقّاة
// وحدَها. وهذا يقيس الطرفَ الذي لا يمسّه اختبارُ SQLite: أنّ الجدولَ يصل
// **خادمَ PostgreSQL** بأعمدته وفهارسه.
//
// وهو الطرفُ الذي يهمّ عمليّاً: PG خلفيّةُ الخادم في تنصيبة العميل/المرآة،
// وتسويةُ ض.ق.م تُقرأ هناك.
//
// ⚠️ يعمل عبر `melos test:pg` وحدَه.

@Tags(['pg'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';
import 'package:picpos_erp/services/id_namespace_service.dart';

import '_support/pg_fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    final fx = await bootPgTestSchema();
    addTearDown(fx.tearDown);
    db = fx.db;
    await db.select(db.accounts).get(); // يُجبر الهجرةَ ومسارَ الإقلاع
  });

  test('الجدولُ موجودٌ على PG بأعمدةِ المستند وأعمدةِ المزامنة', () async {
    final rows = await db
        .customSelect(
          "SELECT column_name FROM information_schema.columns "
          "WHERE table_name = 'purchase_returns'",
        )
        .get();
    final cols = rows
        .map((r) => (r.data['column_name'] as String).toLowerCase())
        .toSet();

    expect(cols, isNotEmpty, reason: 'مرساة: الجدولُ أُنشئ على PG');

    expect(
      cols,
      containsAll(<String>[
        'original_invoice_id',
        'supplier_id',
        'return_date',
        'subtotal',
        'tax',
        'total',
      ]),
      reason: 'أعمدةُ المستند — و`tax` هو الحقلُ الذي وُجد الجدولُ لأجله',
    );

    expect(
      cols,
      containsAll(<String>[
        'global_id',
        'last_modified_at',
        'deleted_at',
        'origin_client_id',
        'row_version',
      ]),
      reason: 'أعمدةُ الدلتا الخمس — بدونها يبتلع `_upsertRow` الإدراجَ '
          'صامتاً فيبدو السحبُ عاملاً ولا صفَّ يصل',
    );
  });

  test('الجدولُ مُدرَجٌ في عقود المزامنة الثلاثة', () {
    // بنيويٌّ لا يحتاج PG، لكنّه هنا كي يُقرأ مع نظيره: عضويّةٌ بلا أعمدةٍ
    // أو أعمدةٌ بلا عضويّةٍ كلاهما يفشل صامتاً.
    expect(DeltaPullService.pullTables, contains('purchase_returns'),
        reason: 'وإلّا لم يُسحَب أصلاً');
    expect(DeltaPullService.deltaOnlyTables, contains('purchase_returns'),
        reason: 'بلا استراتيجيّةِ `fullSync` ⇒ لا تُبذَر علامتُه المائيّة، '
            'وإلّا لم يرَ عميلٌ جديدٌ مرتجعاً سابقاً أبداً');
    expect(IdNamespaceService.namespacedTables, contains('purchase_returns'),
        reason: 'بلا أرضيّةِ ترقيمٍ يصطدم صفُّ العميل بصفِّ الخادم');
  });

  test('فهرسا التاريخ والفاتورة الأصليّة موجودان', () async {
    final rows = await db
        .customSelect(
          "SELECT indexname FROM pg_indexes "
          "WHERE tablename = 'purchase_returns'",
        )
        .get();
    final names = rows
        .map((r) => (r.data['indexname'] as String).toLowerCase())
        .toSet();

    expect(names, isNotEmpty, reason: 'مرساة');
    expect(
      names,
      containsAll(<String>[
        'idx_purchase_returns_date',
        'idx_purchase_returns_invoice',
      ]),
      reason: 'التسويةُ تُرشِّح بالمدى الزمنيّ، والإبطالُ بالفاتورة الأصليّة',
    );
  });
}
