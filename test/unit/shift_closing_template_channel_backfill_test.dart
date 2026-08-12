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
      // الإجمالياتُ والحالةُ في الذيل — كما في قالب المالك.
      'shift_total_system',
      'shift_total_actual',
      'shift_status',
    ];
    for (var i = 0; i < stale.length; i++) {
      await db.into(db.invoiceTemplateElements).insert(
            InvoiceTemplateElementsCompanion.insert(
              templateId: id,
              elementType: 'variable',
              sortOrder: Value(i),
              xPosition: const Value(10),
              yPosition: Value(20.0 + i * 23),
              width: const Value(60),
              height: const Value(20),
              content: Value(stale[i]),
              labelAr: const Value('رصيد النظام'),
            ),
          );
    }
    return id;
  }

  Future<List<String>> orderedVariables(int id) async {
    final els = await db.getTemplateElements(id);
    final sorted = els.where((e) => e.elementType == 'variable').toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return sorted.map((e) => e.content ?? '').toList();
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
    // ستُّ قنواتٍ (نقد + بطاقة) وثلاثةُ ذيل (إجمالياتٌ وحالة) — بلا كليك.
    expect(await variablesOf(id), hasLength(9));

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

  test('كلُّ صفٍّ يسمّي قناتَه — لا «رصيد النظام» ثلاثَ مرّاتٍ بلا تمييز',
      () async {
    final id = await seedStaleTemplate();
    await db.backfillShiftClosingChannelElements();

    final els = await db.getTemplateElements(id);
    String labelOf(String key) =>
        els.firstWhere((e) => e.content == key).labelAr ?? '';

    expect(labelOf('shift_system_cash'), 'النقد — رصيد النظام');
    expect(labelOf('shift_actual_card'), 'البطاقة — المبلغ الفعلي');
    expect(labelOf('shift_click_variance'), 'كليك — الفارق');
  });

  test('المُلحَقُ يسبق الإجمالياتِ لا يتلوها', () async {
    // ⚠️ المُصيِّر يرتّب مفاتيحَ `shift_*` بـ`sortOrder` (كلُّها في أولوية
    // «غيرُ معروف» عنده)، فصفٌّ مُلحَقٌ في الذيل يظهر **بعد** «إجمالي
    // النظام» و«الحالة» — رقمٌ شاردٌ بعد الخلاصة. رُصد على ورقٍ حقيقيّ
    // 2026-08-12 قبل هذا التثبيت.
    final id = await seedStaleTemplate();
    await db.backfillShiftClosingChannelElements();

    final order = await orderedVariables(id);
    expect(
      order.indexOf('shift_system_click'),
      lessThan(order.indexOf('shift_total_system')),
    );
    expect(
      order.indexOf('shift_click_variance'),
      lessThan(order.indexOf('shift_status')),
    );
    // والنقدُ والبطاقةُ لم يتزحزحا عن مقدّمة الترتيب.
    expect(order.first, 'shift_system_cash');
  });

  test('قالبٌ صفوفُه في الذيل يُضبط ترتيبُه — لا يُترك لأنه «غيرُ ناقص»',
      () async {
    // نسخةٌ أولى من هذا الإصلاح ألحقت في الذيل، فالقوالبُ التي مرّت بها
    // كاملةُ الصفوف ومقلوبةُ الترتيب — والإلحاقُ وحدَه لا يراها.
    final id = await seedStaleTemplate();
    for (final key in [
      'shift_system_click',
      'shift_actual_click',
      'shift_click_variance',
    ]) {
      await db.into(db.invoiceTemplateElements).insert(
            InvoiceTemplateElementsCompanion.insert(
              templateId: id,
              elementType: 'variable',
              sortOrder: const Value(99),
              xPosition: const Value(10),
              yPosition: const Value(500),
              width: const Value(200),
              height: const Value(20),
              content: Value(key),
            ),
          );
    }

    await db.backfillShiftClosingChannelElements();

    final order = await orderedVariables(id);
    expect(
      order.indexOf('shift_click_variance'),
      lessThan(order.indexOf('shift_total_system')),
    );
  });

  test('متعادلة — تشغيلةٌ ثانيةٌ لا تضيف شيئاً', () async {
    final id = await seedStaleTemplate();
    await db.backfillShiftClosingChannelElements();
    final after1 = (await db.getTemplateElements(id)).length;

    await db.backfillShiftClosingChannelElements();
    expect((await db.getTemplateElements(id)).length, after1);
  });

  group('إعادةُ البناء بالترتيب المبذور', () {
    // ⚠️ `AppDatabase.forTesting()` يشغّل طورَ الإقلاع فعلاً، فالمراجعةُ
    // تُكتب قبل أن ينشئ الاختبارُ قالبَه. مسحُها يحاكي قاعدةً قديمةً
    // حقيقيّة — وهي الحالةُ الوحيدةُ التي تُعنى بها الدالّة.
    Future<void> clearRev() =>
        db.setSetting('shift_closing_template_rev', '');

    test('تُنظّف قالباً تراكمت عليه رقعتان', () async {
      final id = await seedStaleTemplate();
      await clearRev();
      // أثرُ نسخةٍ سابقةٍ من الإصلاح: عنوانٌ استُغني عنه في الذيل.
      await db.into(db.invoiceTemplateElements).insert(
            InvoiceTemplateElementsCompanion.insert(
              templateId: id,
              elementType: 'text',
              sortOrder: const Value(98),
              xPosition: const Value(10),
              yPosition: const Value(600),
              width: const Value(200),
              height: const Value(20),
              content: const Value('كليك'),
            ),
          );

      expect(await db.resetShiftClosingTemplateToSeed(), isTrue);

      final order = await orderedVariables(id);
      // القنواتُ التسعُ كلُّها حاضرة، والإجمالياتُ بعدها.
      for (final key in [
        'shift_system_cash',
        'shift_actual_cash',
        'shift_cash_variance',
        'shift_system_card',
        'shift_actual_card',
        'shift_card_variance',
        'shift_system_click',
        'shift_actual_click',
        'shift_click_variance',
      ]) {
        expect(order, contains(key), reason: key);
        expect(
          order.indexOf(key),
          lessThan(order.indexOf('shift_total_system')),
          reason: '$key قبل الإجماليات',
        );
      }

      final els = await db.getTemplateElements(id);
      expect(
        els.firstWhere((e) => e.content == 'shift_system_click').labelAr,
        'كليك — رصيد النظام',
      );
      // ولا أثرَ للرقعة القديمة: عنصرُ نصٍّ «كليك» عارياً بلا كتلته.
      expect(
        els.where((e) => e.elementType == 'text' && e.content == 'كليك'),
        hasLength(1),
      );
    });

    test('مرّةً واحدةً — لا تهدم تصميمَ المستخدم كلَّ إقلاع', () async {
      final id = await seedStaleTemplate();
      await clearRev();
      expect(await db.resetShiftClosingTemplateToSeed(), isTrue);

      // تعديلٌ بعد إعادة البناء — يمثّل تصميمَ المستخدم.
      final mine = (await db.getTemplateElements(id)).first;
      await (db.update(db.invoiceTemplateElements)
            ..where((t) => t.id.equals(mine.id)))
          .write(const InvoiceTemplateElementsCompanion(fontSize: Value(33)));

      expect(await db.resetShiftClosingTemplateToSeed(), isFalse);
      expect(
        (await db.getTemplateElements(id))
            .firstWhere((e) => e.id == mine.id)
            .fontSize,
        33,
        reason: 'المراجعةُ مخزَّنة، فلا إعادةَ بناءٍ ثانية',
      );
    });
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
