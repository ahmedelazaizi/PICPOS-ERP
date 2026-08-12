// قالبُ إغلاق الوردية الأقدمُ من §٥-٢ لا يعرف قناةَ «كليك» — والبذرةُ لا
// تصلح ما هو موجود.
//
// ── فئةُ العطب (‏بلاغٌ ميدانيّ 2026-08-12 بلقطتَي شاشة) ────────────────────
// الشاشةُ تعرض «تفاصيل التسوية» بالقنوات الثلاث صحيحةً — النقد ١٠ والبطاقة
// ٣٠ وكليك ١٥ — لأنها تقرأ من `ShiftClosingSnapshot` مباشرةً. والمطبوعُ
// يعرض كتلتَين فقط ثم «إجمالي النظام 55.00». فالقارئُ يجمع ما يراه (٤٠)
// ولا يطابق الإجمالي، فيظنّ العطبَ في الحساب — والحسابُ سليم.
//
// كلُّ طبقات §٥-٢ نزلت فعلاً: `resolveShiftValue` يدعم مفاتيحَ كليك،
// و`_seedShiftClosingElements` تزرع صفوفَها. لكنّ الزرعَ مشروطٌ بـ
// `if (!existingTypes.contains('shift_closing'))` — فقاعدةٌ فيها قالبٌ
// سلفاً لا تراه أبداً. و`_seedMissingElements` لا تنقذ: تعالج القوالبَ
// **الفارغة** وحدَها، ولا تعرف `shift_closing` أصلاً.
//
// فالإصلاحُ وصل الكودَ ولم يصل القاعدة. وهذا يفسّر خضرةَ البوابة: كلُّ
// اختبارٍ يبني قاعدةً جديدةً فيأخذ البذرةَ الكاملة، والعطبُ لا يظهر إلا على
// قاعدةٍ قديمة — وجهازُ المالك يحمل واحدة.
//
// العلاج: إلحاقُ الناقص لا إعادةُ البناء (قرارُ المالك 2026-08-12) — تصميمُه
// يبقى كما هو، والمتعادلةُ تسمح بالتشغيل كلَّ إقلاع.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  /// قالبٌ على حال ما قبل §٥-٢: النقدُ والبطاقةُ بلا كليك.
  Future<int> seedStaleTemplate() async {
    final id = await db.into(db.invoiceTemplates).insert(
          InvoiceTemplatesCompanion.insert(
            name: 'تقرير إغلاق الوردية',
            type: const Value('shift_closing'),
            templateCategory: const Value('shift_closing'),
            paperSize: const Value('80mm'),
            paperWidth: const Value(80),
            isDefault: const Value(true),
          ),
        );
    const stale = [
      'shift_system_cash',
      'shift_actual_cash',
      'shift_cash_variance',
      'shift_system_card',
      'shift_actual_card',
      'shift_card_variance',
    ];
    for (var i = 0; i < stale.length; i++) {
      await db.into(db.invoiceTemplateElements).insert(
            InvoiceTemplateElementsCompanion.insert(
              templateId: id,
              elementType: 'variable',
              sortOrder: Value(i),
              xPosition: const Value(10),
              yPosition: Value(20.0 + i * 12),
              width: const Value(60),
              height: const Value(10),
              content: Value(stale[i]),
            ),
          );
    }
    return id;
  }

  Future<List<String>> variablesOf(int id) async {
    final els = await db.getTemplateElements(id);
    return els
        .where((e) => e.elementType == 'variable')
        .map((e) => e.content ?? '')
        .toList();
  }

  test('الإلحاقُ يضيف قناةَ كليك ولا يمسّ النقدَ والبطاقة', () async {
    final id = await seedStaleTemplate();
    expect(await variablesOf(id), hasLength(6));

    await db.backfillShiftClosingChannelElements();

    final vars = await variablesOf(id);
    expect(vars, containsAll(<String>[
      'shift_system_click',
      'shift_actual_click',
      'shift_click_variance',
    ]));
    // النقدُ والبطاقةُ كما هما — لا تكرارَ ولا حذف.
    for (final kept in [
      'shift_system_cash',
      'shift_actual_cash',
      'shift_cash_variance',
      'shift_system_card',
      'shift_actual_card',
      'shift_card_variance',
    ]) {
      expect(vars.where((v) => v == kept), hasLength(1), reason: kept);
    }
  });

  test('عنوانُ القناة يُلحق معها — وإلا فصفوفٌ بلا اسم', () async {
    final id = await seedStaleTemplate();
    await db.backfillShiftClosingChannelElements();

    final els = await db.getTemplateElements(id);
    final heading = els.where(
      (e) => e.elementType == 'text' && (e.content ?? '').contains('كليك'),
    );
    expect(heading, hasLength(1));

    // العنوانُ فوق صفوفه لا تحتها.
    final headingY = heading.first.yPosition;
    final systemClick =
        els.firstWhere((e) => e.content == 'shift_system_click');
    expect(headingY, lessThan(systemClick.yPosition));
  });

  test('متعادلة — تشغيلةٌ ثانيةٌ لا تضيف شيئاً', () async {
    final id = await seedStaleTemplate();
    await db.backfillShiftClosingChannelElements();
    final after1 = (await db.getTemplateElements(id)).length;

    await db.backfillShiftClosingChannelElements();
    expect((await db.getTemplateElements(id)).length, after1);
  });

  test('قالبٌ كاملٌ لا يُمَسّ', () async {
    final id = await db.into(db.invoiceTemplates).insert(
          InvoiceTemplatesCompanion.insert(
            name: 'تقرير إغلاق الوردية',
            type: const Value('shift_closing'),
            templateCategory: const Value('shift_closing'),
            paperSize: const Value('80mm'),
            paperWidth: const Value(80),
          ),
        );
    await db.seedShiftClosingElementsForTest(id);
    final before = (await db.getTemplateElements(id)).length;

    await db.backfillShiftClosingChannelElements();
    expect((await db.getTemplateElements(id)).length, before);
  });
}
