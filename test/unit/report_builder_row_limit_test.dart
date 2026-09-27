// ═══════════════════════════════════════════════════════════════════════════
// منشئ التقارير كان يقصّ عند ١٠٠٠٠ صفٍّ **بلا أن ينطق**.
// ═══════════════════════════════════════════════════════════════════════════
//
// `_buildReportQuery` كان يُلحق `LIMIT 10000 // Safety limit` بكل استعلام. فمن
// يبني تقريراً على ١٥ ألف حركةِ مخزون يرى عشرةَ آلاف، ويجمع عمودَ القيمة،
// ويقدّم الرقمَ على أنه إجماليُّ الفترة. **لا رسالةَ ولا علامة** — والتقريرُ
// المقتطعُ لا يُميَّز عن التقريرِ الكامل.
//
// وهذا أخطرُ من تقريرٍ يفشل: الفشلُ يُرى، والقصُّ الصامتُ يُقرأ كأنه الحقيقة.
//
// ── ليه معامل اختياري لا كسرُ توقيع ─────────────────────────────────────────
// `executeReport` له مُنادٍ إنتاجيٌّ واحد لكن نحو ٢٠ موضعاً في الاختبارات، ومنها
// ملفٌّ تحمله رقعةُ نقلٍ سابقة لـUralCash — فكسرُ التوقيع يوسّع الرقعة ويخلق
// تعارضاً مع ما رُكِّب. والمعاملُ الاختياري يُبلِّغ من يسأل بلا أن يلمس من لا
// يسأل.
//
// ── والقصُّ يُكتشَف بجلبِ صفٍّ زائد ──────────────────────────────────────────
// `LIMIT n` وحده لا يفرّق بين «توجد n صفوفٍ بالضبط» و«قُصَّت». فالاستعلامُ يجلب
// `n + 1` ويُرجِع `n` — ووجودُ الزائد هو الدليل.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  Future<int> report(String entity, String columns) =>
      db.into(db.customReports).insert(CustomReportsCompanion.insert(
          name: 'ت', sourceEntity: entity, columns: columns));

  Future<void> seedParties(int count) async {
    await db.batch((b) {
      for (var i = 0; i < count; i++) {
        b.insert(
          db.parties,
          PartiesCompanion.insert(name: 'طرف ${i.toString().padLeft(5, '0')}'),
        );
      }
    });
  }

  setUp(() async => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  group('حدُّ الصفوف يُبلَّغ عنه', () {
    test('تقريرٌ تحت الحدّ لا يُبلِّغ قصّاً', () async {
      await seedParties(5);
      final id = await report('parties', 'name');

      var reported = -1;
      final rows = await db.executeReport(
        id,
        onRowLimitReached: (limit) => reported = limit,
      );

      expect(rows.length, greaterThan(0));
      expect(reported, -1, reason: 'لا قصَّ ⇒ لا نداء');
    });

    test('تقريرٌ فوق الحدّ يُبلِّغ الحدَّ ويُرجِع الحدَّ بالضبط', () async {
      // حدٌّ صغيرٌ مُمرَّر عوضاً عن زرع ١٠٠٠١ صفّ — نفسُ المنطق بربعِ الثانية.
      await seedParties(25);
      final id = await report('parties', 'name');

      var reported = -1;
      final rows = await db.executeReport(
        id,
        rowLimit: 10,
        onRowLimitReached: (limit) => reported = limit,
      );

      expect(rows.length, 10, reason: 'الصفُّ الزائدُ دليلٌ لا بيانات');
      expect(reported, 10);
    });

    test('عددٌ يساوي الحدَّ بالضبط لا يُبلِّغ قصّاً', () async {
      // الفخُّ الذي يجعل `rows.length == limit` وحده كشفاً كاذباً.
      // ‏`forTesting()` يزرع أطرافاً افتراضية، فيُقاس العددُ الفعلي أولاً.
      final id = await report('parties', 'name');
      final baseline = (await db.executeReport(id)).length;

      var reported = -1;
      final rows = await db.executeReport(
        id,
        rowLimit: baseline,
        onRowLimitReached: (limit) => reported = limit,
      );

      expect(rows.length, baseline);
      expect(reported, -1,
          reason: 'قصٌّ مُبلَّغٌ بلا قصٍّ يجعل المستخدم يشكّ في تقريرٍ كامل');
    });

    test('الحدُّ الافتراضي معلَنٌ لا رقمٌ مدفون', () async {
      expect(kReportBuilderRowLimit, 10000);
    });

    test('القصُّ لا يمنع تسجيل التشغيل بعدد الصفوف المُرجَع', () async {
      await seedParties(25);
      final id = await report('parties', 'name');

      final rows = await db.executeReport(id, rowLimit: 10);

      final runs = await (db.select(db.savedReportRuns)
            ..where((r) => r.reportId.equals(id)))
          .get();
      expect(runs.length, 1);
      expect(runs.first.rowCount, rows.length,
          reason: 'سجلُّ التشغيل يوافق ما رآه المستخدم');
    });
  });
}
