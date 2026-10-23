// test/unit/setup_step_order_test.dart
//
// **اختبارُ توصيفٍ يُكتَب قبل أوّلِ سطرِ تنسيق.**
//
// ═══ لماذا هذا الملفّ أوّلاً ═══
//
// معالجُ البدء ٣٨٤١ سطراً في ثمانية ملفّات و**بلا اختبارِ تخطيطٍ واحد**.
// وأخطرُ ما فيه ترتيبُ خطواته: هو الذي يقرّر ماذا يُسأل عنه كلُّ جهازٍ عند
// تنصيبه. وحين تبدأ إعادةُ تنسيقٍ بصريّةٌ فوق ذلك بلا شبكةِ أمان، تُنقَل
// كتلةٌ فتُزاح خطوةٌ ولا شيءَ يقول — ويظهر النقصُ بعد أيّامٍ في تنصيبِ عميل.
//
// ═══ ⚠️ والأرقامُ هنا **قرارُ مالكٍ مثبَّت** ═══
//
// كان القرارُ (‏2026-08-28) إبقاءَ المسار القديم وإعادةَ التنسيق وحدَها. ثمّ
// صدر **بندُ المالك ٦** (‏المرحلة ح) صريحاً بإعادة الهيكلة: ترحيبٌ ولغة ←
// الشركةُ والنشاط ← العملةُ والضريبة ← الفرع ← الصناديق ← الدليل ← المستخدمون
// ← المراجعة. فالأرقامُ أدناه تنفّذ البندَ ٦ — وما كان خطوةً مستقلّةً صار
// قسماً (‏لا شيءَ سقط: يحرس ذلك `setup_finish_runner_parity_test.dart`).
//
// وتبقى من القرار القديم قيودُه على الأنماط: العميلُ **مع** المستخدمين وبلا
// منتجاتٍ ولا PostgreSQL، والخادمُ بلا منتجات.
//
// 🔴 فسقوطُ فحصٍ هنا ليس عطباً في الكود بالضرورة — قد يكون تعديلاً للمسار
//    بلا قرارِ مالكٍ جديد. راجع القرارَ قبل تعديل الرقم.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/setup_step_order.dart';

void main() {
  group('ترتيبُ الخطوات لكلّ نمط', () {
    test('المستقلّ تسعٌ بترتيب البند ٦', () {
      expect(
        setupStepOrderFor(SetupDeploymentMode.standalone),
        [10, 0, 11, 1, 12, 13, 3, 2, 14],
      );
    });

    test('المرآةُ كالمستقلّ بلا الصناديق', () {
      // الكتابةُ في المرآة تذهب للسيرفر — فلا تُسمّى صناديقُ HQ من هنا.
      final mirror = setupStepOrderFor(SetupDeploymentMode.mirror);
      expect(mirror, [10, 0, 11, 1, 13, 3, 2, 14]);
      expect(
        mirror,
        setupStepOrderFor(SetupDeploymentMode.standalone)
            .where((s) => s != SetupStepIds.cashBanks)
            .toList(),
      );
    });

    test('العميلُ ستٌّ — بلا منتجاتٍ و**مع** المستخدمين', () {
      final order = setupStepOrderFor(SetupDeploymentMode.client);
      expect(order, [10, 0, 11, 1, 3, 14]);

      // 🔴 التصميمُ يحذف «المستخدمين» من العميل — والعميلُ يحتاج كاشيراً
      //    محلّيّاً. القرارُ: تبقى.
      expect(order, contains(SetupStepIds.users));
      // ولا منتجاتٍ ولا PostgreSQL ولا صناديقَ ولا دليل — يأخذها من الخادم.
      expect(order, isNot(contains(SetupStepIds.products)));
      expect(order, isNot(contains(SetupStepIds.postgres)));
      expect(order, isNot(contains(SetupStepIds.cashBanks)));
      expect(order, isNot(contains(SetupStepIds.chartOfAccounts)));
    });

    test('الخادمُ ثمانٍ — PostgreSQL ثمّ التهيئةُ قبل المراجعة، بلا منتجات', () {
      final order = setupStepOrderFor(SetupDeploymentMode.server);
      expect(order, [10, 0, 11, 1, 3, 5, 6, 14]);
      expect(order, isNot(contains(SetupStepIds.products)));
      expect(order.indexOf(SetupStepIds.postgres),
          lessThan(order.indexOf(SetupStepIds.provisioning)));
    });

    test('الأربعُ الأولى واحدةٌ في كلّ نمط — ترحيبٌ ثمّ شركةٌ ثمّ عملةٌ ثمّ فرع', () {
      for (final m in SetupDeploymentMode.values) {
        expect(setupStepOrderFor(m).take(4).toList(), [10, 0, 11, 1],
            reason: '$m');
      }
    });

    test('المراجعةُ آخرُ كلّ مسار — وهي وحدَها تشغّل الإعداد', () {
      for (final m in SetupDeploymentMode.values) {
        expect(setupStepOrderFor(m).last, SetupStepIds.review, reason: '$m');
      }
    });

    test('المستخدمون (‏ومعهم كلمةُ المطوّر) في كلّ نمط', () {
      // كلمةُ المطوّر كانت خطوةً في كلّ نمط؛ صارت قسماً في «المستخدمين»،
      // فسقوطُ «المستخدمين» من نمطٍ يُسقطها معه.
      for (final m in SetupDeploymentMode.values) {
        expect(setupStepOrderFor(m), contains(SetupStepIds.users),
            reason: '$m');
      }
    });

    test('لا خطوةَ مكرّرةٌ في أيّ نمط', () {
      for (final m in SetupDeploymentMode.values) {
        final order = setupStepOrderFor(m);
        expect(order.toSet().length, order.length, reason: '$m');
      }
    });

    test('الخطواتُ المستوعَبة (٤ و٧ و٨ و٩) لم تعد في أيّ مسار', () {
      for (final m in SetupDeploymentMode.values) {
        final order = setupStepOrderFor(m);
        for (final gone in [
          SetupStepIds.tax,
          SetupStepIds.developerPassword,
          SetupStepIds.businessProfile,
          SetupStepIds.touchMode,
        ]) {
          expect(order, isNot(contains(gone)), reason: '$m: $gone');
        }
      }
    });

    test('الاختياريّةُ ثلاث — ولها كلِّها افتراضيٌّ أو لا كتابةَ فيها', () {
      expect(kOptionalSetupSteps, {
        SetupStepIds.products,
        SetupStepIds.cashBanks,
        SetupStepIds.chartOfAccounts,
      });
    });
  });

  group('التنقّل أماماً وخلفاً', () {
    final order = setupStepOrderFor(SetupDeploymentMode.standalone);

    test('يتقدّم خطوةً خطوةً حتّى آخر المسار ثمّ يقف', () {
      var s = order.first;
      final visited = <int>[s];
      for (var i = 0; i < order.length + 3; i++) {
        final next = setupNextStep(order, s);
        if (next == s) break;
        s = next;
        visited.add(s);
      }
      expect(visited, order);
      // وآخرُ خطوةٍ لا تتقدّم.
      expect(setupNextStep(order, order.last), order.last);
    });

    test('ويرجع خطوةً خطوةً حتّى أوّله ثمّ يقف', () {
      var s = order.last;
      final visited = <int>[s];
      for (var i = 0; i < order.length + 3; i++) {
        final prev = setupPreviousStep(order, s);
        if (prev == s) break;
        s = prev;
        visited.add(s);
      }
      expect(visited, order.reversed.toList());
      expect(setupPreviousStep(order, order.first), order.first);
    });

    test('🔴 خطوةٌ خارجَ المسار لا تقفز إلى أوّله', () {
      // تبديلُ نمط التشغيل يبدّل المسارَ تحت المستخدم، فتصير خطوةٌ كان يقف
      // عليها خارجَه. و`indexOf` تُرجع `-1`، و`-1 + 1 == 0` يقفز به إلى
      // **أوّل** المسار بلا سبب.
      final client = setupStepOrderFor(SetupDeploymentMode.client);
      expect(client, isNot(contains(SetupStepIds.products)));

      expect(setupNextStep(client, SetupStepIds.products),
          SetupStepIds.products);
      expect(setupPreviousStep(client, SetupStepIds.products),
          SetupStepIds.products);
    });
  });

  group('نسبةُ التقدّم', () {
    final order = setupStepOrderFor(SetupDeploymentMode.standalone);

    test('أوّلُ خطوةٍ صفرٌ لا ١/٩', () {
      // 🔴 شريطٌ يبدأ ممتلئاً جزئيّاً قبل أن يُكتَب حرفٌ يَعِد بما لم يقع.
      expect(setupProgress(order, order.first), 0);
    });

    test('وآخرُ خطوةٍ ٨/٩ لا ١ — فالمسارُ لم يكتمل بعد', () {
      expect(setupProgress(order, order.last), closeTo(8 / 9, 1e-9));
    });

    test('والخطوةُ الرابعةُ ٣/٩ بالضبط', () {
      expect(setupProgress(order, order[3]), closeTo(3 / 9, 1e-9));
    });

    test('وخطوةٌ خارجَ المسار صفرٌ لا سالب', () {
      final client = setupStepOrderFor(SetupDeploymentMode.client);
      expect(setupProgress(client, SetupStepIds.products), 0);
    });
  });
}
