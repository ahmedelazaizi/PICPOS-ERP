// تقسيمُ رصيد الخزينة إلى نقديٍّ وبنكيّ.
//
// ما يُقاس: القسمةُ على صفرٍ (‏تعطي `NaN` في Dart لا استثناءً، فتنفجر في
// طبقة الرسم بعيداً عن سببها)، والمجموعُ السالب (‏صندوقٌ مسحوبٌ عليه)، وأن
// نوعاً مجهولاً يُعدُّ نقداً فلا يختفي رصيدُه من المجموع.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/domain/models/picpos_treasury_view.dart';

({String kind, double balance}) _safe(String kind, double balance) =>
    (kind: kind, balance: balance);

void main() {
  group('PicPosTreasurySplit', () {
    test('قائمةٌ فارغةٌ ⇒ صفرٌ بلا NaN ولا شريط', () {
      final s = PicPosTreasurySplit.from(const []);
      expect(s.total, 0);
      expect(s.hasBar, isFalse);
      for (final sl in s.slices) {
        expect(sl.fraction, 0);
        expect(sl.fraction.isNaN, isFalse);
      }
    });

    test('يفصل النقديَّ عن البنكيّ ويجمعهما', () {
      final s = PicPosTreasurySplit.from([
        _safe('cash', 300),
        _safe('cash', 200),
        _safe('bank', 500),
      ]);
      expect(s.total, closeTo(1000, 1e-9));
      expect(s.slices.firstWhere((x) => x.kind == 'cash').value,
          closeTo(500, 1e-9));
      expect(s.slices.firstWhere((x) => x.kind == 'bank').value,
          closeTo(500, 1e-9));
    });

    test('النسبُ تجمع إلى واحدٍ على مجموعٍ موجب', () {
      final s = PicPosTreasurySplit.from([
        _safe('cash', 750),
        _safe('bank', 250),
      ]);
      expect(s.slices.firstWhere((x) => x.kind == 'cash').fraction,
          closeTo(0.75, 1e-9));
      expect(s.slices.firstWhere((x) => x.kind == 'bank').fraction,
          closeTo(0.25, 1e-9));
      expect(s.slices.fold<double>(0, (a, x) => a + x.fraction),
          closeTo(1.0, 1e-9));
    });

    // ⚠️ الحارسُ الأهمّ: بلا هذا كان الشريطُ يُرسم بعرضٍ `NaN` فيرمي في
    // طبقة الرسم — بعيداً عن سببه.
    test('مجموعٌ صفريٌّ ⇒ نسبٌ صفريّةٌ لا NaN', () {
      final s = PicPosTreasurySplit.from([
        _safe('cash', 500),
        _safe('bank', -500),
      ]);
      expect(s.total, closeTo(0, 1e-9));
      expect(s.hasBar, isFalse);
      for (final sl in s.slices) {
        expect(sl.fraction.isNaN, isFalse);
        expect(sl.fraction, 0);
      }
    });

    test('مجموعٌ سالبٌ ⇒ لا شريطَ والأرقامُ تبقى ظاهرة', () {
      final s = PicPosTreasurySplit.from([_safe('cash', -200)]);
      expect(s.total, closeTo(-200, 1e-9));
      expect(s.hasBar, isFalse);
      expect(s.slices.firstWhere((x) => x.kind == 'cash').value,
          closeTo(-200, 1e-9));
    });

    // ⚠️ عطبٌ شُحن ثمّ صُحّح: النسخةُ الأولى ضمّت «كلَّ ما ليس بنكاً» إلى
    // النقديّ، فكانت محفظةُ كليك تختفي في خانة النقد — مجموعٌ صحيحٌ وتوزيعٌ
    // خاطئ. و`click` نوعٌ قائمٌ في التنصيبة الحيّة لا مفترَض.
    test('كليك شريحةٌ مستقلّةٌ لا تُضمّ إلى النقديّ', () {
      final s = PicPosTreasurySplit.from([
        _safe('cash', 100),
        _safe('click', 300),
      ]);
      expect(s.slices.firstWhere((x) => x.kind == 'click').value,
          closeTo(300, 1e-9));
      expect(s.slices.firstWhere((x) => x.kind == 'cash').value,
          closeTo(100, 1e-9));
    });

    test('الشرائحُ ثلاثٌ دائماً بترتيبٍ ثابت', () {
      final s = PicPosTreasurySplit.from(const []);
      expect(s.slices.map((x) => x.kind).toList(), ['cash', 'bank', 'click']);
    });

    test('النسبُ الثلاثُ تجمع إلى واحد', () {
      final s = PicPosTreasurySplit.from([
        _safe('cash', 200),
        _safe('bank', 700),
        _safe('click', 100),
      ]);
      expect(s.slices.fold<double>(0, (a, x) => a + x.fraction),
          closeTo(1.0, 1e-9));
      expect(s.slices.firstWhere((x) => x.kind == 'bank').percentLabel, '70%');
    });

    // نوعٌ يُضاف لاحقاً يجب أن يظهر في المجموع لا أن يسقط منه بصمت.
    test('نوعٌ مجهولٌ يُعدُّ نقداً فلا يختفي رصيدُه', () {
      final s = PicPosTreasurySplit.from([_safe('wallet', 400)]);
      expect(s.total, closeTo(400, 1e-9));
      expect(s.slices.firstWhere((x) => x.kind == 'cash').value,
          closeTo(400, 1e-9));
    });

    test('النصوصُ تستعمل decimalPlaces لا رقماً مكتوباً باليد', () {
      final s = PicPosTreasurySplit.from([_safe('cash', 12.5)]);
      expect(s.totalLabel,
          (12.5).toStringAsFixed(AppConstants.decimalPlaces));
    });

    test('نصُّ النسبة بلا كسور', () {
      final s = PicPosTreasurySplit.from([
        _safe('cash', 2),
        _safe('bank', 1),
      ]);
      expect(s.slices.firstWhere((x) => x.kind == 'cash').percentLabel, '67%');
    });
  });
}
