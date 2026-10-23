// test/unit/template_resolution_chain_test.dart
//
// حارسُ «الشاشةُ تشرح ما يفعله الراسمُ فعلاً».
//
// ── العطبُ الذي يمنعه ────────────────────────────────────────────────────
// `resolve` هي التي يمشيها مسارُ الطباعة، و`explain` هي التي تعرضها شاشةُ
// الحسم. وهما تنفيذان اثنان لسلسلةٍ واحدة. فلو انحرف أحدُهما عن الآخر صارت
// الشاشةُ تشرح عطباً **غيرَ** الواقع — وهو أسوأُ من غيابها: المستخدمُ يطارد
// المستوى الخطأ ويثق بالإجابة.
//
// فهذا الملفُّ لا يقيس `explain` وحدَها، بل يقيس **اتّفاقَها مع `resolve`**
// على كلِّ تركيبةٍ من الفرع والطابعة واللغة وحضورِ الافتراضيّ.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/printing/template_resolver.dart';

void main() {
  // رابطاتٌ تغطّي المستوياتِ الأربعةَ الأولى، كلٌّ بقالبٍ مميَّزٍ كي يُقرأ
  // الفائزُ من رقمه لا من ترتيبه.
  const l1 = BindingRule(
      templateId: 101,
      documentType: 'sales_invoice',
      branchId: 3,
      printerId: 7,
      locale: 'ar');
  const l2 = BindingRule(
      templateId: 102, documentType: 'sales_invoice', branchId: 3, locale: 'ar');
  const l3 =
      BindingRule(templateId: 103, documentType: 'sales_invoice', locale: 'ar');
  const l4 = BindingRule(templateId: 104, documentType: 'sales_invoice');

  group('السلسلةُ سبعةُ مستوياتٍ دائماً', () {
    test('بلا رابطةٍ ولا مِزلاجٍ ولا افتراضيّ ⇐ المدمجُ يفوز والستّةُ قبله أُخفقت', () {
      final chain = TemplateResolver.explain(
        documentType: 'sales_invoice',
        category: 'invoice',
        bindings: const [],
      );

      expect(chain, hasLength(7));
      expect(chain.where((s) => s.isWinner).single.level, 7);
      expect(chain.last.templateId, isNull,
          reason: 'المدمجُ لا قالبَ له في القاعدة — و`null` هنا قصدٌ لا فقد');
      for (final s in chain.take(6)) {
        expect(s.state, ResolutionStepState.missed);
      }
    });

    test('وفائزٌ واحدٌ لا أكثر، مهما كان المستوى', () {
      for (final bindings in <List<BindingRule>>[
        [],
        [l4],
        [l3, l4],
        [l2, l3, l4],
        [l1, l2, l3, l4],
      ]) {
        final chain = TemplateResolver.explain(
          documentType: 'sales_invoice',
          category: 'invoice',
          bindings: bindings,
          branchId: 3,
          printerId: 7,
          locale: 'ar',
          categoryDefaultTemplateId: 105,
        );
        expect(chain.where((s) => s.isWinner), hasLength(1),
            reason: 'رابطات: ${bindings.map((b) => b.templateId).toList()}');
      }
    });

    test('وما بعد الفائز «لم يُجرَّب» لا «أخفق»', () {
      final chain = TemplateResolver.explain(
        documentType: 'sales_invoice',
        category: 'invoice',
        bindings: const [l1, l2, l3, l4],
        branchId: 3,
        printerId: 7,
        locale: 'ar',
      );
      expect(chain[0].isWinner, isTrue);
      for (final s in chain.skip(1)) {
        expect(s.state, ResolutionStepState.notTried,
            reason: 'المستوى ${s.level} وُسم مُخفِقاً وهو لم يُجرَّب أصلاً');
      }
    });
  });

  group('ضابط: `explain` و`resolve` لا تفترقان', () {
    // كلُّ تركيبةٍ ممكنةٍ من: مجموعةِ رابطات × فرع × طابعة × لغة ×
    // حضورِ الافتراضيّ. ‏٥ × ٢ × ٢ × ٢ × ٢ = ٨٠ حالة.
    test('نفسُ المستوى ونفسُ القالب في ثمانين تركيبة', () {
      var checked = 0;

      for (final bindings in <List<BindingRule>>[
        [],
        [l4],
        [l3, l4],
        [l2, l3, l4],
        [l1, l2, l3, l4],
      ]) {
        for (final branchId in <int?>[3, null]) {
          for (final printerId in <int?>[7, null]) {
            for (final locale in <String?>['ar', null]) {
              for (final def in <int?>[105, null]) {
                final r = TemplateResolver.resolve(
                  documentType: 'sales_invoice',
                  category: 'invoice',
                  bindings: bindings,
                  branchId: branchId,
                  printerId: printerId,
                  locale: locale,
                  categoryDefaultTemplateId: def,
                );
                final chain = TemplateResolver.explain(
                  documentType: 'sales_invoice',
                  category: 'invoice',
                  bindings: bindings,
                  branchId: branchId,
                  printerId: printerId,
                  locale: locale,
                  categoryDefaultTemplateId: def,
                );
                final w = chain.where((s) => s.isWinner).single;

                final where = 'b=${bindings.length} branch=$branchId '
                    'printer=$printerId locale=$locale def=$def';
                expect(w.level, r.level, reason: 'المستوى اختلف عند $where');
                expect(w.templateId, r.templateId,
                    reason: 'القالبُ اختلف عند $where');
                checked++;
              }
            }
          }
        }
      }

      // «صفرُ المطابقات = نمطٌ غلط» — فالعدُّ يُثبت أنّ الحلقةَ دارت فعلاً.
      expect(checked, 80);
    });

    test('وضابطٌ للضابط: قيمةٌ محسوبةٌ يدوياً لا «متساويان»', () {
      // فرعٌ ولغةٌ يطابقان `l2` وحدَها: `l1` تشترط طابعةً و`printerId` هنا
      // `null`، فالمستوى الثاني هو الفائزُ المحسوبُ باليد.
      final chain = TemplateResolver.explain(
        documentType: 'sales_invoice',
        category: 'invoice',
        bindings: const [l1, l2, l3, l4],
        branchId: 3,
        locale: 'ar',
      );
      final w = chain.where((s) => s.isWinner).single;
      expect(w.level, 2);
      expect(w.templateId, 102);
      expect(chain[0].state, ResolutionStepState.missed);
    });
  });

  group('المفاتيحُ المعروضةُ تصف الاستعلامَ لا الرابطة', () {
    test('النجمةُ تعميمُ المستوى والشَّرطةُ نقصُ الاستعلام — وهما ليسا سواءً',
        () {
      // ⚠️ بلا هذا التفريق تظهر الثلاثةُ الأولى بمفتاحٍ **واحدٍ حرفيّاً** حين
      //    يُفحَص «كلُّ الفروع» بلا طابعة، فلا تقول اللوحةُ أيُّها أخفق ولماذا.
      final chain = TemplateResolver.explain(
        documentType: 'sales_invoice',
        category: 'invoice',
        bindings: const [],
        locale: 'ar',
      );

      expect(chain[0].key, 'sales_invoice · — · — · ar',
          reason: 'الأوّلُ يشترط فرعاً وطابعةً ولم يحملهما الاستعلام');
      expect(chain[1].key, 'sales_invoice · — · * · ar',
          reason: 'الثاني يعمّم الطابعةَ ويشترط الفرع');
      expect(chain[2].key, 'sales_invoice · * · * · ar');
      expect(chain[3].key, 'sales_invoice · * · * · *');
      expect(chain[4].key, 'pos_receipt_template',
          reason: 'المستوى الخامسُ إعدادٌ واحدٌ لا مفتاحَ نطاقٍ له');
      expect(chain[5].key, 'invoice · * · * · *',
          reason: 'المستوى السادسُ يُفهرَس بالفئة لا بنوع المستند');

      // والدليلُ القاطع: أربعةُ مفاتيحَ متمايزةٍ لا مفتاحٌ مكرَّر.
      expect(chain.take(4).map((s) => s.key).toSet(), hasLength(4));
    });

    test('والمحدَّدُ يُكتب بقيمته', () {
      final chain = TemplateResolver.explain(
        documentType: 'sales_return',
        category: 'invoice',
        bindings: const [],
        branchId: 3,
        printerId: 7,
        locale: 'ar',
      );
      expect(chain[0].key, 'sales_return · 3 · 7 · ar');
      expect(chain[1].key, 'sales_return · 3 · * · ar');
      expect(chain[2].key, 'sales_return · * · * · ar');
      expect(chain[3].key, 'sales_return · * · * · *');
    });
  });
}
