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
// ═══ ⚠️ والأرقامُ هنا **قرارُ مالكٍ مثبَّت** (‏2026-08-28) ═══
//
// تصميمُ `PicPos Setup Wizard.dc.html` يخالفها في الأنماط الأربعة: يحذف
// «المستخدمين» من العميل، ويضيف «المنتجات» و«المستخدمين» للخادم، ويُنزل
// المرآةَ إلى خمس خطوات. وسُئل المالكُ صراحةً فاختار **إبقاءَ المسار الحاليّ
// وإعادةَ التنسيق وحدَها**.
//
// 🔴 فسقوطُ فحصٍ هنا ليس عطباً في الكود بالضرورة — قد يكون تنفيذاً للتصميم
//    بلا قرارِ مالكٍ جديد. راجع القرارَ قبل تعديل الرقم.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/setup_step_order.dart';

void main() {
  group('ترتيبُ الخطوات لكلّ نمط', () {
    test('المستقل ثمانٍ بالترتيب الحاليّ', () {
      expect(
        setupStepOrderFor(SetupDeploymentMode.standalone),
        [0, 8, 7, 1, 9, 2, 3, 4],
      );
    });

    test('المرآةُ تشارك المستقلَّ حرفاً', () {
      // المرآةُ تُنهي اقترانَها داخلَ الخطوة ١، فلا تحتاج خطوةً زائدة.
      expect(
        setupStepOrderFor(SetupDeploymentMode.mirror),
        setupStepOrderFor(SetupDeploymentMode.standalone),
      );
    });

    test('العميلُ سبعٌ — بلا منتجاتٍ و**مع** المستخدمين', () {
      final order = setupStepOrderFor(SetupDeploymentMode.client);
      expect(order, [0, 8, 7, 1, 9, 3, 4]);

      // 🔴 التصميمُ يحذف «المستخدمين» من العميل — والعميلُ يحتاج كاشيراً
      //    محلّيّاً. القرارُ: تبقى.
      expect(order, contains(SetupStepIds.users));
      // ولا منتجاتٍ ولا PostgreSQL — يأخذهما من الخادم بالمزامنة.
      expect(order, isNot(contains(SetupStepIds.products)));
      expect(order, isNot(contains(SetupStepIds.postgres)));
    });

    test('الخادمُ سبعٌ — بلا منتجاتٍ ولا مستخدمين', () {
      final order = setupStepOrderFor(SetupDeploymentMode.server);
      expect(order, [0, 8, 7, 1, 9, 5, 6]);

      // 🔴 التصميمُ يضيفهما — والخادمُ يزرع المديرَ ويتوقّع إنشاءَهم بعد
      //    الإعداد، والمنتجاتُ تُستورَد لا تُكتَب هنا. القرارُ: تبقى محذوفة.
      expect(order, isNot(contains(SetupStepIds.users)));
      expect(order, isNot(contains(SetupStepIds.products)));

      expect(order, contains(SetupStepIds.postgres));
      expect(order, contains(SetupStepIds.provisioning));
    });

    test('«نمطُ الإدخال» في نفس الموضع في الأنماط كلِّها', () {
      // Feature 031 · research D13 — بعد اختيار الشبكة وقبل أوّل خطوةِ
      // بيانٍ ثقيلة، ليراه المشغّلُ على أيّ شكلِ نشر.
      for (final m in SetupDeploymentMode.values) {
        final order = setupStepOrderFor(m);
        expect(order.indexOf(SetupStepIds.touchMode), 4, reason: '$m');
        expect(order[3], SetupStepIds.branchAndMode, reason: '$m');
      }
    });

    test('الأربعةُ الأولى واحدةٌ في كلّ نمط', () {
      // الشركةُ ثمّ النشاطُ ثمّ كلمةُ المطوّر ثمّ الشبكة — يُختاران قبل أيّ
      // عملٍ ثقيلٍ لأنّ تبديلَهما بعد الإعداد يحتاج كلمةَ المطوّر.
      for (final m in SetupDeploymentMode.values) {
        expect(setupStepOrderFor(m).take(4).toList(), [0, 8, 7, 1],
            reason: '$m');
      }
    });

    test('لا خطوةَ مكرّرةٌ في أيّ نمط', () {
      for (final m in SetupDeploymentMode.values) {
        final order = setupStepOrderFor(m);
        expect(order.toSet().length, order.length, reason: '$m');
      }
    });

    test('🔴 ولا خطوةَ «مراجعة» — التصميمُ يطلبها ولم تُبنَ', () {
      // `review` في التصميم شاشةُ ملخّصٍ لكلّ ما أُدخل. بناءٌ لا تنسيق،
      // وإدراجُها في السجلّ بلا جسمٍ يبنيها يعطي خطوةً فارغة. وقرارُ المالك
      // (‏2026-08-28) أنّها خارجَ هذه الدفعة.
      for (final m in SetupDeploymentMode.values) {
        expect(setupStepOrderFor(m).every((s) => s <= 9), isTrue, reason: '$m');
      }
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
      // تبديلُ نمط التشغيل في الخطوة ١ يبدّل المسارَ تحت المستخدم، فتصير
      // خطوةٌ كان يقف عليها خارجَه. و`indexOf` تُرجع `-1`، و`-1 + 1 == 0`
      // يقفز به إلى **أوّل** المسار بلا سبب.
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

    test('أوّلُ خطوةٍ صفرٌ لا ١/٨', () {
      // 🔴 شريطٌ يبدأ ممتلئاً جزئيّاً قبل أن يُكتَب حرفٌ يَعِد بما لم يقع.
      expect(setupProgress(order, order.first), 0);
    });

    test('وآخرُ خطوةٍ ٧/٨ لا ١ — فالمسارُ لم يكتمل بعد', () {
      expect(setupProgress(order, order.last), closeTo(7 / 8, 1e-9));
    });

    test('والخطوةُ الخامسةُ ٤/٨ بالضبط', () {
      expect(setupProgress(order, order[4]), closeTo(0.5, 1e-9));
    });

    test('وخطوةٌ خارجَ المسار صفرٌ لا سالب', () {
      final client = setupStepOrderFor(SetupDeploymentMode.client);
      expect(setupProgress(client, SetupStepIds.products), 0);
    });
  });
}
