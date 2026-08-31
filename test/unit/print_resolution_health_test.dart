// test/unit/print_resolution_health_test.dart
//
// تصنيفُ حالِ مسارِ الطباعة — الدالّةُ التي تكتب شارةَ العمود الأخير.
//
// ── لماذا تُقاس ──────────────────────────────────────────────────────────
// الشارةُ هي كلُّ ما يراه المالكُ عن مسارٍ لا يعمل. فشارةٌ خاطئةٌ أسوأُ من
// عمودٍ فارغ: «مضبوط» على مسارٍ يطبع بالتصميم المدمج تُقفل التحقيقَ عند
// أوّل نظرة.
//
// ⚠️ وتصنيفٌ واحدٌ لا مجموعة — فالترتيبُ جوهرُ الدالّة، وهو ما تقيسه
// المجموعةُ الأخيرة: كلُّ زوجٍ متعارضٍ يُثبَّت أيُّهما يفوز.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/print_resolution_row.dart';
import 'package:ural_erp/services/printing/paper_compatibility.dart';

void main() {
  ResolutionHealth call({
    required int level,
    bool wired = true,
    bool shares = false,
    PaperFit fit = PaperFit.ok,
  }) =>
      classifyResolution(
        level: level,
        wired: wired,
        sharesCategoryDefault: shares,
        fit: fit,
      );

  group('كلُّ حالٍ يُبلَغ من وقائعه', () {
    test('السابعُ ⇐ بلا قالب', () {
      expect(call(level: 7), ResolutionHealth.builtIn);
    });

    test('الأوّلُ والثاني ⇐ من الفرع', () {
      expect(call(level: 1), ResolutionHealth.branchScoped);
      expect(call(level: 2), ResolutionHealth.branchScoped);
    });

    test('الثالثُ والرابعُ ⇐ مضبوط', () {
      expect(call(level: 3), ResolutionHealth.bound);
      expect(call(level: 4), ResolutionHealth.bound);
    });

    // ⚠️ المِزلاجُ **اختيارٌ صريحٌ من المدير** لا سقوطٌ إلى عَلَمٍ عالميّ،
    // فحالُه «مضبوط» لا «بالفئة». ولا تصادمَ فيه: مِزلاجٌ واحدٌ لا يخدم إلّا
    // `sales_receipt`، فالتقاسمُ لا يبلغه أصلاً.
    test('الخامسُ (مِزلاجُ البيع السريع) ⇐ مضبوط', () {
      expect(call(level: 5), ResolutionHealth.bound);
      expect(call(level: 5, shares: true), ResolutionHealth.bound,
          reason: 'التصادمُ حكمُ مستوى الفئة وحدَه');
    });

    test('السادسُ وحدَه ⇐ بالفئة', () {
      expect(call(level: 6), ResolutionHealth.categoryOnly);
    });

    test('والسادسُ مُتقاسَماً ⇐ تصادمُ فئة', () {
      expect(call(level: 6, shares: true), ResolutionHealth.collision);
    });

    test('وقالبٌ صحيحٌ بلا منادٍ ⇐ بانتظار التوصيل', () {
      expect(call(level: 4, wired: false), ResolutionHealth.unwired);
    });

    test('وقالبٌ أعرضُ من طابعته ⇐ ورقٌ غيرُ مطابق', () {
      expect(call(level: 4, fit: PaperFit.tooWide),
          ResolutionHealth.paperMismatch);
    });

    test('والأضيقُ ليس عدمَ توافق — هامشٌ أبيضُ لا فقدُ بيان', () {
      expect(call(level: 4, fit: PaperFit.narrower), ResolutionHealth.bound);
    });
  });

  group('الترتيبُ عند تعارض الوقائع — أسوأً فأسوأ', () {
    test('«بلا قالب» تسبق «بانتظار التوصيل»', () {
      // عرضُ سعرٍ: لا قالبَ ولا منادٍ. والمستخدمُ يواجه غيابَ القالب أوّلاً.
      expect(call(level: 7, wired: false), ResolutionHealth.builtIn);
    });

    test('و«بلا قالب» تسبق «ورقاً غيرَ مطابق»', () {
      expect(call(level: 7, fit: PaperFit.tooWide), ResolutionHealth.builtIn);
    });

    test('و«ورقٌ غيرُ مطابق» تسبق «تصادمَ فئة»', () {
      expect(call(level: 6, shares: true, fit: PaperFit.tooWide),
          ResolutionHealth.paperMismatch);
    });

    test('و«تصادمُ فئة» تسبق «بانتظارَ التوصيل»', () {
      expect(call(level: 6, shares: true, wired: false),
          ResolutionHealth.collision);
    });

    test('و«بانتظار التوصيل» تسبق «بالفئة» و«من الفرع» و«مضبوط»', () {
      expect(call(level: 6, wired: false), ResolutionHealth.unwired);
      expect(call(level: 1, wired: false), ResolutionHealth.unwired);
      expect(call(level: 4, wired: false), ResolutionHealth.unwired);
    });
  });

  group('عدّادُ «يحتاج معالجة» يعدّ الأحمرَ وحدَه', () {
    test('الثلاثةُ الحمراءُ تُعدّ', () {
      for (final h in [
        ResolutionHealth.builtIn,
        ResolutionHealth.paperMismatch,
        ResolutionHealth.collision,
      ]) {
        expect(h.needsAttention, isTrue, reason: h.label);
      }
    });

    test('و«بانتظار التوصيل» لا تُعدّ — نقصُ امتدادٍ لا عطبُ إعداد', () {
      expect(ResolutionHealth.unwired.needsAttention, isFalse);
    });

    test('والسليمةُ الثلاثُ لا تُعدّ', () {
      for (final h in [
        ResolutionHealth.bound,
        ResolutionHealth.branchScoped,
        ResolutionHealth.categoryOnly,
      ]) {
        expect(h.needsAttention, isFalse, reason: h.label);
      }
    });
  });

  test('ولكلِّ حالٍ تسميةٌ وشرحٌ — لا فراغَ في الشارة', () {
    for (final h in ResolutionHealth.values) {
      expect(h.label, isNotEmpty, reason: '$h');
      expect(h.note, isNotEmpty, reason: '$h');
    }
    // تسمياتٌ متكرّرةٌ تعني شارتين لا تُفرَّقان في الشاشة.
    expect(ResolutionHealth.values.map((h) => h.label).toSet(),
        hasLength(ResolutionHealth.values.length));
  });
}
