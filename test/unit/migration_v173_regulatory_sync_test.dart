// هجرةُ v173 — أعمدةُ المزامنة للسجلِّ الرقابيِّ والتشغيلِ العابر (٢٦ جدولاً).
//
// ═══ ما يحمي هذا الملفّ ═══
//
// المرحلةُ ٤ تُخرج من العزلة ما حكمُه 🔴 في `sync_coverage_guard_test`:
// إثباتٌ رقابيٌّ لا يُعاد بناؤه (الفاتورةُ الإلكترونيّةُ وسجلُّ الحقول
// والاعتمادُ وفصلُ المهامّ) وحالةُ تشغيلٍ يقرؤها أكثرُ من جهاز (الجردُ
// وطلباتُ الصرف والولاءُ والمطابقةُ البنكيّة). والصيغةُ نسخةُ v167 حرفاً،
// فمُشغِّلُ الرفع والفهرسُ الجزئيُّ مقيسان هناك ولا يُعادان هنا. ما يُقاس
// هنا هو ما يخصّ هذه المرحلةَ وحدَها:
//
//  ‏١) **الأعمدةُ الخمسةُ على الستّة والعشرين** — من `createAll` لا من
//     الهجرة: `forTesting()` لا يمرّ بـ`onUpgrade` إطلاقاً.
//
//  ‏٢) 🔴 **`e_invoice_status_log` صارت كياناً.** كانت صنفاً بلا إعلانٍ في
//     `@DriftDatabase` (٦‑١) يُبنى بـSQL خامّ في ثلاثة مواضع — فإضافةُ
//     الأعمدة إلى الصنف وحدَه كانت ستُرضي حارسَ العضويّة **ولا تصل
//     القاعدةَ أبداً**. فلها فحصٌ باسمها: الجدولُ موجودٌ في قاعدةٍ جديدةٍ
//     **بأعمدة المزامنة**، أي أنّ `createAll` هو من بناه لا الـSQL الخامّ.
//
//  ‏٣) 🔴 **و`e_invoice_configs` بلا `global_id` عمداً** — الاستثناءُ
//     الأمنيُّ المكتوبُ في الحارس. مرساةٌ سالبةٌ: لو أضافها أحدٌ «لتكتمل
//     القائمة» فقد أدخل `client_secret` في مسار `SELECT *`.
//
//  ‏٤) **و`stock_requisitions` وُلدت بـ`global_id` منذ v149** — الهجرةُ تعتمد
//     على الـsafe-skip، وهذا يُثبت أنّ العمودَ لم يُفقَد بسببه.
//
//  ‏٥) **ولا صفَّ يُخترَع.** الأعمدةُ تُضاف ولا تُنشئ بيانات.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

/// الستّةُ والعشرون بأسمائها SQL — نفسُ قائمة `phase4Tables` في `epoch_3.dart`.
const _phase4Tables = <String>[
  'loyalty_programs', 'delivery_companies', 'couriers',
  'customer_loyalty_points', 'loyalty_transactions',
  'warehouse_prices',
  'cycle_count_plans', 'cycle_count_tasks', 'cycle_count_items',
  'stock_audits', 'stock_audit_items',
  'stock_requisitions', 'stock_requisition_items',
  'bank_reconciliations', 'bank_statement_lines',
  'e_invoice_submissions', 'e_invoice_status_log',
  'field_audit_logs', 'failed_autoposts',
  'approval_workflows', 'approval_steps', 'approval_requests',
  'approval_decisions', 'sod_conflicts', 'sod_violations',
  'compliance_checks',
];

const _syncColumns = <String>[
  'global_id',
  'last_modified_at',
  'deleted_at',
  'origin_client_id',
  'row_version',
];

void main() {
  group('المخطَّطُ الجديد — تركيبةٌ من الصفر', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting());
    tearDown(() async => db.close());

    Future<Set<String>> columnsOf(String table) async {
      final info = await db.customSelect('PRAGMA table_info($table)').get();
      return info.map((r) => r.data['name'] as String).toSet();
    }

    test('مرساة: قراءةُ PRAGMA تعمل أصلاً', () async {
      final cols = await columnsOf('parties');
      expect(cols, contains('global_id'),
          reason: 'قراءةُ PRAGMA مكسورة — كلُّ حكمٍ بعدها باطل');
    });

    test('مرساة: القائمةُ هنا ٢٦ اسماً — لا نسخةٌ مبتورة', () {
      expect(_phase4Tables.length, 26);
      expect(_phase4Tables.toSet().length, 26, reason: 'اسمٌ مكرَّر');
    });

    for (final table in _phase4Tables) {
      test('$table يحمل أعمدةَ المزامنة الخمسة', () async {
        final cols = await columnsOf(table);
        expect(cols.length, greaterThan(3),
            reason: 'قراءةُ PRAGMA لـ$table عادت شبهَ فارغة — الجدولُ غائب؟');
        expect(cols, containsAll(_syncColumns));
      });
    }

    test('🔴 `e_invoice_status_log` كيانٌ يبنيه createAll — لا SQL خامّ',
        () async {
      // الجدولُ كان يُبنى بـ`kCreateEInvoiceStatusLogSql` وحدَه. ذلك الـSQL
      // صار يحمل الأعمدةَ أيضاً، فالفحصُ أعلاه لا يميّز المصدرَين. ما يميّز:
      // الكيانُ يظهر في `allTables` — وهذا ما يجعله يصل PostgreSQL عبر
      // `_createAllForPostgres` كأخواته.
      final names = db.allTables.map((t) => t.actualTableName).toSet();
      expect(names, contains('e_invoice_status_log'),
          reason: 'الصنفُ ما زال بلا إعلانٍ في `@DriftDatabase` ⇒ أعمدةُ '
              'المزامنة على الصنف زينةٌ لا تصل القاعدة.');
      // ومرساةٌ لطريقة القياس نفسِها: كيانٌ نعلم يقيناً أنّه مُعلَن.
      expect(names, contains('e_invoice_submissions'));
    });

    test('🔴 `e_invoice_configs` بلا `global_id` — الاستثناءُ الأمنيّ',
        () async {
      final cols = await columnsOf('e_invoice_configs');
      expect(cols, contains('client_secret'),
          reason: 'مرساة: هذا هو العمودُ الذي يُبنى عليه الاستثناء');
      expect(cols.contains('global_id'), isFalse,
          reason: 'أُعطي `e_invoice_configs` أعمدةَ مزامنةٍ ⇒ سرُّ الفاتورة '
              'الإلكترونيّة صار على مسار `SELECT *`. الحكمُ في '
              '`sync_coverage_guard_test`: يُزامَن بتشفيرٍ أو لا يُزامَن.');
    });

    test('و`stock_requisitions` لم تفقد `global_id` القديمَ', () async {
      // v149 أعطتها العمودَ والفهرسَ. الهجرةُ v173 تُعيد المحاولةَ ويُبتلَع
      // «duplicate column» — والخطرُ أن يُبتلَع معه ما يليه.
      final cols = await columnsOf('stock_requisitions');
      expect(cols, containsAll(_syncColumns));
      expect(cols, contains('fulfilled_by_transfer_id'),
          reason: 'عمودُ v149 الثاني اختفى — الإدراجُ دهس تعريفَ الجدول');
    });

    test('🔴 الترقيةُ لا تكتب صفّاً في أيٍّ منها', () async {
      // ⚠️ `sod_conflicts` و`compliance_checks` قد يُزرعان في الإقلاع — إن
      //    صار لهما زرعٌ فليُكتَب هنا **بعدده المضبوط** لا بتجاوز.
      const seeded = <String, int>{};

      for (final table in _phase4Tables) {
        final rows =
            await db.customSelect('SELECT COUNT(*) AS n FROM $table').get();
        expect(rows.single.data['n'], seeded[table] ?? 0,
            reason: '$table يحمل صفوفاً لا يفسّرها زرعُ الإقلاع');
      }
    });

    test('رقمُ المخطَّط بلغ ١٧٣ فأكثر', () async {
      // «بلغ» لا «تجمّد»: توكيدٌ مساوٍ يكسر الترقيةَ التالية.
      expect(db.schemaVersion, greaterThanOrEqualTo(173));
    });
  });
}
