// طرقُ الدفع المعروضةُ في شاشة بيع PicPos — قرارٌ خالصٌ قابلٌ للقياس.
//
// ── العطبُ الأصليّ (مقيسٌ 2026-08-14) ───────────────────────────────────────
// كان الترشيحُ يعيش داخل `_allowedPaymentMethods` في
// `picpos_pos_operations.dart`، وذيلُه:
//
//     } catch (_) {
//       return codeFor.keys.toSet();   // ← الطرقُ الخمسُ كلُّها
//     }
//
// أيْ **يفشل مفتوحاً**: أيُّ خطأِ قاعدةٍ أو تعذُّرِ قراءةٍ للصلاحيات يمنح
// الكاشيرَ البيعَ الآجلَ والبطاقةَ والتحويلَ والمتعدّدَ دفعةً واحدة. وهو
// نفسُ نمطِ `4f774fd3` («الحارسُ كان يفشل مفتوحاً مع كلّ حفظِ فاتورة»):
// الاستثناءُ يُقرأ «لا تُعطّل التِلّ» فيُترجَم عملياً «افتح كلَّ شيء».
//
// والحراسةُ لم تكن قابلةً للقياس أصلاً لأنها داخل دالّةٍ خاصّةٍ في `State`،
// فاستُخرج القرارُ إلى دالّةٍ خالصةٍ — وهذا الملفُّ يقيسها.
//
// ── وطلبُ المالك (2026-08-14) ───────────────────────────────────────────────
// «عند التأشير للنقديّ فقط لا تظهر الطرقُ الأخرى» — إعدادٌ للتنصيبة **فوق**
// الصلاحية لا بدلاً منها. فالمُظهَرُ تقاطعُ الاثنين: ما أذنت به الصلاحيةُ
// **و** أشّرت عليه الإعدادات.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/presentation/pos_picpos/widgets/picpos_payment_methods.dart';

void main() {
  const allFive = {'cash', 'card', 'click', 'credit', 'multiple'};

  const everyPermission = <String>[
    PermissionCodes.posPaymentCash,
    PermissionCodes.posPaymentCard,
    PermissionCodes.posPaymentTransfer,
    PermissionCodes.posPaymentCredit,
    PermissionCodes.posPaymentMultiple,
  ];

  group('الفشلُ يُقفِل لا يُفتِح', () {
    test('تعذُّرُ قراءة الصلاحيات يترك النقديَّ وحدَه', () {
      // `permissions: null` = رمى `currentUserPermissionsProvider`.
      // قبل الإصلاح كانت النتيجةُ `allFive`.
      expect(
        resolveAllowedPaymentMethods(
          permissions: null,
          enabledBySetting: null,
        ),
        equals({'cash'}),
      );
    });

    test('ولا يوسّعه إعدادٌ يؤشّر على الخمسة', () {
      // الإعدادُ لا يمنح ما منعته قراءةٌ فاشلة — وإلا لكان بابَ التفاف.
      expect(
        resolveAllowedPaymentMethods(
          permissions: null,
          enabledBySetting: allFive,
        ),
        equals({'cash'}),
      );
    });
  });

  group('الإعدادُ يضيّق على المأذون', () {
    test('التأشيرُ على النقديّ وحدَه يخفي الباقيَ رغم كلِّ الصلاحيات', () {
      expect(
        resolveAllowedPaymentMethods(
          permissions: everyPermission,
          enabledBySetting: {'cash'},
        ),
        equals({'cash'}),
      );
    });

    test('ويضيّق على مدير النظام أيضاً — الإعدادُ للتنصيبة لا للدور', () {
      // مديرُ النظام يتخطّى الصلاحيةَ لا الإعداد: «نقديٌّ فقط» قرارُ تشغيلٍ
      // للفرع كلِّه، فلو تخطّاه المديرُ لظهرت له طرقٌ قرّر صاحبُ المحلّ
      // إخفاءَها.
      expect(
        resolveAllowedPaymentMethods(
          permissions: const ['system_admin'],
          enabledBySetting: {'cash', 'card'},
        ),
        equals({'cash', 'card'}),
      );
    });

    test('والتقاطعُ حقيقيّ: مؤشَّرٌ بلا صلاحيةٍ لا يظهر', () {
      expect(
        resolveAllowedPaymentMethods(
          permissions: const [PermissionCodes.posPaymentCash],
          enabledBySetting: {'cash', 'credit'},
        ),
        equals({'cash'}),
      );
    });

    test('وإعدادٌ غيرُ مضبوطٍ (null) لا يضيّق شيئاً', () {
      // تنصيبةٌ لم تُفتح فيها الشاشةُ قطّ: السلوكُ كما كان قبل الإعداد.
      expect(
        resolveAllowedPaymentMethods(
          permissions: everyPermission,
          enabledBySetting: null,
        ),
        equals(allFive),
      );
    });
  });

  group('ما كان يعمل يبقى يعمل', () {
    test('الصلاحياتُ وحدَها ترشّح', () {
      expect(
        resolveAllowedPaymentMethods(
          permissions: const [
            PermissionCodes.posPaymentCash,
            PermissionCodes.posPaymentCredit,
          ],
          enabledBySetting: null,
        ),
        equals({'cash', 'credit'}),
      );
    });

    test('ومديرُ النظام يمرّ بلا كودٍ صريح', () {
      expect(
        resolveAllowedPaymentMethods(
          permissions: const ['system_admin'],
          enabledBySetting: null,
        ),
        equals(allFive),
      );
    });

    test('وعميلُ المنصّة آجلٌ وحدَه — قيدُ العميل فوق قيدِ المستخدم', () {
      expect(
        resolveAllowedPaymentMethods(
          permissions: const [PermissionCodes.posPaymentCash],
          enabledBySetting: {'cash'},
          isPlatformCustomer: true,
        ),
        equals({'credit'}),
      );
    });

    test('وحتّى حين تتعذّر قراءةُ الصلاحيات — المنصّةُ آجلٌ لا نقديّ', () {
      // القيدُ على مستوى العميل: فاتورةُ منصّةٍ نقديّةٌ خطأٌ تشغيليّ، لا
      // تشديدٌ أمنيّ.
      expect(
        resolveAllowedPaymentMethods(
          permissions: null,
          enabledBySetting: null,
          isPlatformCustomer: true,
        ),
        equals({'credit'}),
      );
    });
  });

  test('لا طريقةَ دفعٍ بلا كودِ صلاحيةٍ مسجَّل', () {
    // يمنع أن تُضاف طريقةٌ سادسةٌ للشاشة وتفوتَ الترشيحَ بالكامل.
    expect(paymentMethodPermissionCodes.keys.toSet(), equals(allFive));
  });

  group('المسارُ السريع حين تُؤشَّر طريقةٌ واحدة', () {
    test('النقديُّ وحدَه يتخطّى حوارَ الدفع', () {
      // طلبُ المالك: «بطريقةٍ أسهل وأسرع». تنصيبةٌ نقديّةٌ بحتة لا يصحّ أن
      // تُسأل عن طريقةٍ لا بديلَ لها.
      expect(singlePaymentMethodFastPath({'cash'}), equals('cash'));
    });

    test('والبطاقةُ والتحويلُ كذلك — اختيارُ الخزنة يقع بعدُ على مسار الكتابة',
        () {
      expect(singlePaymentMethodFastPath({'card'}), equals('card'));
      expect(singlePaymentMethodFastPath({'click'}), equals('click'));
    });

    test('لكنّ الآجلَ لا يُتخطّى — الحوارُ هو من يلتقط العميل', () {
      // بلا عميلٍ تصير الفاتورةُ ديناً بلا مدين. القاعدةُ ليست ذوقاً.
      expect(singlePaymentMethodFastPath({'credit'}), isNull);
    });

    test('ولا المتعدّدُ — الحوارُ هو من يقسّم المبالغ', () {
      expect(singlePaymentMethodFastPath({'multiple'}), isNull);
    });

    test('وطريقتان تعنيان حواراً — والاختيارُ للكاشير', () {
      expect(singlePaymentMethodFastPath({'cash', 'card'}), isNull);
    });

    test('ولا طريقةَ إطلاقاً تعني حواراً لا تخطّياً صامتاً', () {
      // مجموعةٌ فارغةٌ = دورٌ بلا أيّ صلاحية دفع. الحوارُ يظهر فارغاً
      // فيَعلم الكاشيرُ أن ثمّة منعاً — والتخطّي كان سيحفظ بلا طريقة.
      expect(singlePaymentMethodFastPath(const <String>{}), isNull);
    });
  });

  group('قراءةُ الإعداد المخزَّن', () {
    test('غيرُ المضبوط يعني «لا تضييق» لا «امنع الكلّ»', () {
      expect(parseEnabledPaymentMethods(null), isNull);
      expect(parseEnabledPaymentMethods(''), isNull);
      expect(parseEnabledPaymentMethods('   '), isNull);
    });

    test('والقائمةُ تُقرأ بفواصلَ وتتحمّل الفراغات', () {
      expect(
        parseEnabledPaymentMethods(' cash , card '),
        equals({'cash', 'card'}),
      );
    });

    test('ومفتاحٌ مجهولٌ يُهمَل ولا يُسقط الباقي', () {
      expect(
        parseEnabledPaymentMethods('cash,bitcoin,card'),
        equals({'cash', 'card'}),
      );
    });

    test('وقيمةٌ كلُّها مجهولةٌ تُقرأ «غيرَ مضبوطة» لا «صفرَ طرق»', () {
      // إعدادٌ تالفٌ يجب ألّا يوقف التِلَّ تماماً: صفرُ طرقٍ = لا بيع.
      expect(parseEnabledPaymentMethods('bitcoin,gold'), isNull);
    });
  });
}
