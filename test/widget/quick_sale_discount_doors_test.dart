// سقفُ الخصم — قياسُ **الباب** لا الدالّة.
//
// ═══ لماذا widget لا unit ═══
//
// `ensureDiscountWithinPolicy` تأخذ `WidgetRef` و`BuildContext` وتفتح حوارَ
// مصادقة. فقياسُها بلا شجرةٍ يقيس نصفَها: يمرّ الرفضُ ويسقط فرعُ الموافقة —
// وهو الفرقُ كلُّه بين `discappr` مطفأً ومضاءً.
//
// وهذه **دالّةُ الإنتاج نفسُها** التي تناديها الأبوابُ الثلاثة:
//   ١. خليةُ «الخصم ٪» في الجدول — `picpos_items_table.dart:489`
//   ٢. فرعُ الخصم في حوار «تعديل الصنف» — `picpos_pos_operations.dart:1354`
//   ٣. خصمُ الفاتورة كلِّها — `picpos_pos_operations.dart:1425`
//
// والقاعدةُ حقيقيّةٌ في الذاكرة والمزوِّدُ حقيقيّ: المقيسُ هو أنّ ما يكتبه
// المديرُ يصل إلى قرار الرفض.
//
// ⚠️ **ولا `pumpAndSettle` حول حوار المصادقة**: حقلُ كلمة المرور
// `autofocus` ومؤشّرُه يومض، فالإطاراتُ لا تسكن أبداً وتنتهي المهلةُ بعد
// عشر دقائق. `pump` المتكرّرُ وحدَه يمرّ.
//
// ⚠️ ولا `db.close()` — مؤقّتُ drift يعلّق الاختبار.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/data/providers/quick_sale_policy_providers.dart';
import 'package:ural_erp/presentation/pos_picpos/widgets/picpos_cart_permissions.dart';
import 'package:ural_erp/services/manager_approval_cache.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    // ⚠️ **تسخينُ القاعدة هنا لا داخلَ `testWidgets`.** drift يفتح القاعدةَ
    // كسولاً، و`beforeOpen` يجدول مؤقّتاتٍ حقيقيّة. ووقوعُ أوّلِ استعلامٍ
    // داخلَ المنطقة الوهمية يعني مؤقّتاً لا يُطلَق أبداً — فيعلّق الاختبارُ
    // حتّى مهلة العشر دقائق قبل أن يُرسَم إطارٌ واحد. (مقيسٌ: تعليقٌ تامّ)
    await db.saveSettings({'__warmup__': '1'});
    ManagerApprovalCache.instance.clear();
  });

  tearDown(() {
    ManagerApprovalCache.instance.clear();
  });

  /// إطاراتٌ متتاليةٌ بدل `pumpAndSettle` — راجع رأسَ الملفّ.
  Future<void> beat(WidgetTester tester, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// يبني شجرةً صغيرةً تعطي `WidgetRef` و`BuildContext` حقيقيَّين، ويرجع
  /// مقابضَ تُشغِّل مسارَ الإنتاج.
  Future<
      ({
        Future<DiscountPolicyOutcome> Function(double percent) discount,
        Future<bool> Function() priceBlocked,
        ProviderContainer container,
      })> pump(
    WidgetTester tester, {
    required Map<String, String> settings,
    List<String> permissions = const [PermissionCodes.posDiscount],
  }) async {
    if (settings.isNotEmpty) await db.saveSettings(settings);

    late WidgetRef capturedRef;
    late BuildContext capturedContext;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserPermissionsProvider
              .overrideWith((ref) async => permissions),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              capturedContext = context;
              // تسخينُ المزوِّد كما تفعل شاشةُ الكاشير في `build`.
              ref.watch(quickSalePolicyProvider);
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    );
    await beat(tester);

    // ⚠️ فكِّ الشجرةَ في النهاية ولا تُغلق القاعدة — وإلّا سقط الاختبارُ
    // بـ`!timersPending` أو علّق على مؤقّت drift.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    final container = ProviderScope.containerOf(
      tester.element(find.byType(Consumer)),
      listen: false,
    );

    return (
      discount: (double percent) => ensureDiscountWithinPolicy(
            capturedRef,
            capturedContext,
            percent,
          ),
      priceBlocked: () => priceEditBlockedByPolicy(capturedRef),
      container: container,
    );
  }

  group('disccap — سقفُ الخصم اليدويّ', () {
    testWidgets('سقفٌ ١٠٪ وموافقةُ المدير مطفأة — خصمُ ٢٥٪ يُرفض بلا حوار',
        (tester) async {
      final api = await pump(tester, settings: {
        'pos_manual_discount_cap': '10',
        'pos_discount_requires_manager': 'false',
      });

      final verdict = api.discount(25);
      await beat(tester);

      expect(await verdict, DiscountPolicyOutcome.aboveCapRejected);
      expect(find.text('تصريح المسؤول مطلوب'), findsNothing,
          reason: 'لا مسارَ موافقةٍ مفعَّل — عرضُ الحوار يوهم أنّ مديراً '
              'يستطيع تجاوزَه ولا يستطيع');
      expect(discountPolicyMessage(await verdict), isNotNull,
          reason: 'الرفضُ الصامتُ يجعل الكاشيرَ يعيد المحاولةَ بلا فهم');
    });

    testWidgets('سقفٌ ١٠٪ — خصمُ ١٠٪ بالضبط يمرّ فالمساواةُ مسموحة',
        (tester) async {
      final api = await pump(tester, settings: {
        'pos_manual_discount_cap': '10',
        'pos_discount_requires_manager': 'false',
      });

      final verdict = api.discount(10);
      await beat(tester);

      expect(await verdict, DiscountPolicyOutcome.allowed);
      expect(discountPolicyMessage(await verdict), isNull);
    });

    testWidgets('سقفٌ ١٠٪ — خصمُ ١٠٫٠١٪ يُرفض', (tester) async {
      final api = await pump(tester, settings: {
        'pos_manual_discount_cap': '10',
        'pos_discount_requires_manager': 'false',
      });

      final verdict = api.discount(10.01);
      await beat(tester);

      expect(await verdict, DiscountPolicyOutcome.aboveCapRejected);
    });

    testWidgets('discappr مضاءةٌ — خصمُ ٢٥٪ فوق سقفِ ١٠٪ يفتح حوارَ مصادقة',
        (tester) async {
      final api = await pump(tester, settings: {
        'pos_manual_discount_cap': '10',
        'pos_discount_requires_manager': 'true',
      });

      final verdict = api.discount(25);
      await beat(tester);

      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget,
          reason: 'مع «يحتاج موافقة مدير» يجب أن يظهر البابُ لا أن يُرفض');
      expect(find.textContaining('خصم 25'), findsOneWidget,
          reason: 'الحوارُ يذكر النسبةَ والحدَّ — وإلّا صادق المديرُ على مجهول');
      expect(find.textContaining('فوق حدّ 10'), findsOneWidget);

      // المديرُ يلغي.
      await tester.tap(find.text('إلغاء'));
      await beat(tester);

      expect(await verdict, DiscountPolicyOutcome.approvalDenied);
      expect(discountPolicyMessage(await verdict), isNull,
          reason: 'الحوارُ تكلّم عن نفسِه — توستٌ ثانٍ ضجيج');
    });

    testWidgets('discappr مضاءةٌ لكنّ الخصمَ داخلَ السقف — لا حوارَ أصلاً',
        (tester) async {
      final api = await pump(tester, settings: {
        'pos_manual_discount_cap': '25',
        'pos_discount_requires_manager': 'true',
      });

      final verdict = api.discount(20);
      await beat(tester);

      expect(await verdict, DiscountPolicyOutcome.allowed);
      expect(find.text('تصريح المسؤول مطلوب'), findsNothing,
          reason: 'إزعاجُ المديرِ داخلَ السقف يجعل السقفَ بلا معنى');
    });

    testWidgets('تغييرُ السقف من ٢٥ إلى ٥ يسري فورَ إبطال المزوِّد',
        (tester) async {
      final api = await pump(tester, settings: {
        'pos_manual_discount_cap': '25',
        'pos_discount_requires_manager': 'false',
      });

      final first = api.discount(20);
      await beat(tester);
      expect(await first, DiscountPolicyOutcome.allowed);

      // المديرُ يشدّ السقفَ ثمّ يُبطل المزوِّدَ — كما تفعل شاشةُ الإعدادات.
      await db.saveSettings({'pos_manual_discount_cap': '5'});
      api.container.invalidate(quickSalePolicyProvider);
      await beat(tester);

      final second = api.discount(20);
      await beat(tester);
      expect(await second, DiscountPolicyOutcome.aboveCapRejected,
          reason: 'قيمةٌ قديمةٌ محتجزةٌ في المزوِّد = إعدادٌ ميّت — وهو '
              'بلاغُ المالك 2026-08-30 بعينه');
    });

    testWidgets(
        'السقفُ الافتراضيُّ في قاعدةٍ بكرٍ ١٥٪ — لا صفراً ولا «بلا حد»',
        (tester) async {
      // مفتاحُ السقف **غائبٌ** عمداً: قاعدةُ تنصيبةٍ جديدةٍ لا تحمله.
      // و`discappr` مطفأةٌ كي يُقاس الرفضُ بلا حوارٍ يعلّق الاختبار.
      final api = await pump(tester, settings: {
        'pos_discount_requires_manager': 'false',
      });

      final zero = api.discount(0);
      await beat(tester);
      expect(await zero, DiscountPolicyOutcome.allowed,
          reason: 'سقفٌ يُقرأ صفراً يمنع حتّى الخصمَ الصفر');

      final atCap = api.discount(15);
      await beat(tester);
      expect(await atCap, DiscountPolicyOutcome.allowed,
          reason: 'الافتراضُ ١٥٪ كما في التصميم');

      final overCap = api.discount(16);
      await beat(tester);
      expect(await overCap, DiscountPolicyOutcome.aboveCapRejected,
          reason: 'سقفٌ يُقرأ «بلا حد» في قاعدةٍ بكرٍ يجعل الإعدادَ زينة');
    });

    testWidgets('discappr مضاءةٌ افتراضاً — فوقَ السقف يُسأل مديرٌ لا يُرفض',
        (tester) async {
      // لا مفتاحَ لأيٍّ من الاثنين — هذا حالُ أوّلِ تشغيل.
      final api = await pump(tester, settings: const {});

      final verdict = api.discount(40);
      await beat(tester);

      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget,
          reason: 'الافتراضُ في التصميم «يحتاج موافقة مدير» مضاءٌ');

      await tester.tap(find.text('إلغاء'));
      await beat(tester);
      expect(await verdict, DiscountPolicyOutcome.approvalDenied);
    });
  });

  group('priceedit — البابُ الذي يُفحص قبل الصلاحية', () {
    testWidgets('«ممنوع» تمنع حتّى مالكَ الصلاحية', (tester) async {
      final api = await pump(
        tester,
        settings: {'pos_price_edit_policy': '0'},
        permissions: const ['system_admin'],
      );
      final blocked = api.priceBlocked();
      await beat(tester);
      expect(await blocked, isTrue,
          reason: 'التضييقُ الحقيقيُّ الذي تضيفه السياسة — «الأسعارُ ثابتةٌ '
              'في هذا المحلّ»');
    });

    testWidgets('«يحتاج موافقة» لا تمنع — تترك القرارَ للصلاحيات',
        (tester) async {
      final api = await pump(tester, settings: {'pos_price_edit_policy': '1'});
      final blocked = api.priceBlocked();
      await beat(tester);
      expect(await blocked, isFalse);
    });

    testWidgets('«مسموح» لا تمنح ما تمنعه الصلاحياتُ — تمتنع عن المنع فقط',
        (tester) async {
      final api = await pump(
        tester,
        settings: {'pos_price_edit_policy': '2'},
        permissions: const [],
      );
      final blocked = api.priceBlocked();
      await beat(tester);
      expect(await blocked, isFalse,
          reason: 'السياسةُ تضيّق ولا توسّع — والصلاحيةُ تبقى الحاكمة');
    });
  });
}
