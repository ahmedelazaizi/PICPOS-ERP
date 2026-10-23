// هل تصل سياسةُ البيع السريع إلى مسار الكاشير فعلاً؟
//
// ═══ بلاغُ المالك 2026-08-30 ═══
//
// «الأوامر التي أحددها للعرض على شاشة نقطة البيع من إعداد البيع لا ترتبط
// مباشرة بالنظام ولا يتم تنفيذها».
//
// ═══ لماذا لم يُمسك هذا سابقاً ═══
//
// ⚠️ **اختبارُ الشاشة يتجاوز `quickSalePolicyProvider` بـ`overrideWith`.**
// فهو يقيس أنّ الشاشةَ تعرض القيمَ المُعطاة، ولا يقيس **وصولَ** القيم من
// القاعدة إلى نقطة القرار. والفجوةُ بينهما هي بعينها ما بلّغ عنه المالك:
// الاختباراتُ خضراءُ والميزةُ لا تعمل.
//
// فهذا الملفُّ يستعمل المزوِّدَ **الحقيقيَّ** على قاعدةٍ حقيقيّةٍ في الذاكرة،
// ويقرأ **بنفس أسلوب مسار الكاشير** لا بأسلوبٍ مريح.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/providers/quick_sale_policy_providers.dart';
import 'package:picpos_erp/domain/models/quick_sale_policy.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    // ⚠️ لا `db.close()`: مؤقّتُ drift ينتظر في المنطقة الوهمية فيعلّق الاختبار.
  });

  group('وصولُ السياسة إلى نقطة القرار', () {
    test('القراءةُ غيرُ المتزامنة ترى ما حُفظ — خطُّ الأساس', () async {
      // المديرُ يختار «بطاقة» طريقةً افتراضيّة (الفهرس ١).
      await db.saveSettings({'pos_default_payment_method': '1'});

      final policy = await container.read(quickSalePolicyProvider.future);
      expect(
        quickSaleDefaultPaymentMethod(policy),
        'card',
        reason: 'المزوِّدُ نفسُه يقرأ من القاعدة صحيحاً — فالعطبُ إن وُجد '
            'ليس في القراءة بل في **أسلوب** الاستدعاء.',
      );
    });

    test(
        'أمّا القراءةُ المتزامنةُ — وهي أسلوبُ مسار الكاشير — فترى `null` '
        'ولا ترى ما حُفظ', () async {
      await db.saveSettings({'pos_default_payment_method': '1'});

      // ⚠️ **هذا حرفيّاً ما يفعله مسارُ الدفع**:
      //     final policy = ref.read(quickSalePolicyProvider).asData?.value;
      // ولا شيءَ في شجرة شاشة الكاشير يراقب المزوِّدَ (`ref.watch`)، فهو باردٌ
      // عند أوّل قراءة.
      final sync = container.read(quickSalePolicyProvider).asData?.value;

      // التوثيقُ لا الادّعاء: نسجّل ما يحدث فعلاً.
      // ignore: avoid_print
      print('[قياس] القراءةُ المتزامنةُ الباردة أعطت: '
          '${sync == null ? "null ⇒ السلوكُ القائم" : quickSaleDefaultPaymentMethod(sync)}');

      expect(
        sync,
        isNull,
        reason: 'إن كانت `null` فالإعدادُ **لا يصل** إلى قرار الدفع: '
            'الكودُ يسقط إلى «السلوك القائم» فيبدو الإعدادُ مُهمَلاً — '
            'وهو بلاغُ المالك بعينه.',
      );
    });

    test('وتبقى `null` حتّى بعد أن يكتمل الجلبُ ثمّ يُقرأ ثانيةً', () async {
      await db.saveSettings({'pos_default_payment_method': '1'});

      // نُشعل الجلبَ وننتظره — كما لو أنّ شاشةً سابقةً قرأته.
      await container.read(quickSalePolicyProvider.future);

      // ثمّ نقرأ متزامناً كما يفعل مسارُ الكاشير.
      final again = container.read(quickSalePolicyProvider).asData?.value;

      // ignore: avoid_print
      print('[قياس] بعد اكتمال الجلب، القراءةُ المتزامنة أعطت: '
          '${again == null ? "null" : quickSaleDefaultPaymentMethod(again)}');

      expect(
        again,
        isNotNull,
        reason: 'إن كانت `null` هنا أيضاً فالمزوِّدُ يُتلَف بين القراءتين، '
            'والعطبُ دائمٌ لا عابر.',
      );
    });
  });
}
