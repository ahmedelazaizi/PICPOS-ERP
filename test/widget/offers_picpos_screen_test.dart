// test/widget/offers_picpos_screen_test.dart
//
// اختبارُ **تركيب** شاشة العروض بهويّة PicPos — لا اختبارُ قطعةٍ منها.
//
// ⚠️ الخزينةُ شُحنت **بيضاء** واختباراتُ ودجتاتها كلُّها خضراء: العطبُ لم يكن
// في أيّ ودجت بل في تركيبها (`stretch` داخلَ `Column` يطلب ارتفاعاً لا
// نهائيّاً). وفي بناء الإصدار لا تظهر الشاشةُ الحمراء — يُرسم بياض. فتُضخّ
// الشاشةُ كاملةً هنا مع `takeException`.
//
// ⚠️ و**بعرضَين**: فيضٌ ثابتٌ عبرهما = خليّةٌ ضيّقة، ومتغيّرٌ = حسابُ أعمدة.
//
// ⚠️ ولا يُكتفى بـ«لم تنهر»: شاشةٌ تُرسم فارغةً تمرّ على ذلك الشرط. فيُقاس
// نصٌّ من محتواها الفعليّ.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/offers_repository.dart';
import 'package:ural_erp/presentation/offers_picpos/offers_picpos_screen.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_dialog.dart';

class _FakeOffersRepo implements IOffersRepository {
  _FakeOffersRepo(this._offers);
  final List<Offer> _offers;

  @override
  Stream<List<Offer>> watchOffers() => Stream.value(_offers);

  // البطاقةُ تقرأ أصنافَ العرض لتعرض عددَها — فتُجاب بقائمةٍ فارغةٍ لا
  // بـ`noSuchMethod` ترمي، وإلّا صار الفشلُ في المزيَّف لا في الشاشة.
  @override
  Future<List<OfferItem>> getOfferItems(int offerId) async => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Offer _offer({
  required int id,
  required String name,
  bool isActive = true,
  DateTime? endDate,
}) =>
    Offer(
      id: id,
      name: name,
      offerType: 'bundle',
      offerPrice: 100,
      isActive: isActive,
      startDate: DateTime(2026, 1, 1),
      endDate: endDate,
      currentUses: 0,
      isGlobal: true,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  Future<void> pump(WidgetTester tester, double width,
      {List<Offer>? offers}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          offersRepositoryProvider.overrideWithValue(
            _FakeOffersRepo(offers ??
                [
                  _offer(id: 1, name: 'باقة الإفطار'),
                  _offer(id: 2, name: 'خصم نهاية الأسبوع', isActive: false),
                  _offer(
                    id: 3,
                    name: 'عرض منتهٍ',
                    endDate: DateTime(2026, 1, 2),
                  ),
                ]),
          ),
          // ⚠️ بلا هذا يبتلع `PermissionGuard` الضغطةَ ويُظهر رسالةَ منعٍ
          //    بدل أن يفتح الحوار — فيبدو الفشلُ كأنّ الحوارَ لا يُبنى.
          currentUserPermissionsProvider
              .overrideWith((ref) async => const ['system_admin']),
        ],
        child: const MaterialApp(home: OffersPicPosScreen()),
      ),
    );
    await tester.pump();
  }

  for (final width in [1280.0, 1920.0]) {
    testWidgets('تُبنى بلا استثناءِ تخطيطٍ عند عرض ${width.toInt()}',
        (tester) async {
      await pump(tester, width);
      expect(tester.takeException(), isNull);
    });

    testWidgets('وتعرض محتواها فعلاً عند عرض ${width.toInt()}',
        (tester) async {
      await pump(tester, width);

      // ترويسةُ الغلاف المشترك — لا ترويسةٌ خاصّةٌ بالشاشة.
      expect(find.text('العروض'), findsWidgets);
      // عدّاداتُ الحالة — وهي ما ينقص حين تُرسم الشاشةُ بيضاء.
      expect(find.text('إجمالي العروض'), findsOneWidget);
      expect(find.text('فعّالة الآن'), findsOneWidget);
      // وصفٌّ حقيقيٌّ من الشبكة.
      expect(find.text('باقة الإفطار'), findsWidgets);
    });
  }

  testWidgets('العدّاداتُ مقيسةٌ من الصفوف لا مخترَعة', (tester) async {
    await pump(tester, 1280);

    // ثلاثةٌ: فعّالٌ واحدٌ · موقوفٌ واحدٌ · منتهٍ واحد.
    expect(find.text('3'), findsWidgets, reason: 'الإجمالي');
    // «فعّالة الآن» = ١: الموقوفُ يخرج بعلَمه والمنتهي بتاريخه.
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('حوارُ «إضافة عرض» يُفتح بهويّة PicPos لا بـAlertDialog خام',
      (tester) async {
    // ⚠️ الشاشةُ صارت بالهويّة والحوارُ كان يبقى بالشكل القديم — فيُقاس
    //    الفتحُ فعلاً لا وجودُ الصنف في الكود. و`PicPosDialog` هو ما يميّزه:
    //    عنوانٌ وسطرٌ خافتٌ تحته وزرٌّ أساسيٌّ موسوم.
    await pump(tester, 1280, offers: const []);

    await tester.tap(find.text('إضافة عرض').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.byType(PicPosDialog), findsOneWidget);
    expect(find.text('إضافة عرض جديد'), findsWidgets);
    // ⚠️ زرُّ الإلغاء: `onCancel` افتراضُها `null` = لا زرَّ إلغاء، فحوارٌ
    //    بلا مخرجٍ غيرِ الحفظ. يُقاس صراحةً.
    expect(find.text('إلغاء'), findsWidgets);

    // ⚠️ الحوارُ يفتح مؤقّتاتٍ (حركةٌ وقراءاتٌ من المستودع) تبقى معلَّقةً
    //    فيسقط الاختبارُ بـ`!timersPending`. فكِّك الشجرةَ وادفع إطاراً —
    //    **داخلَ جسم الاختبار** لا في `addTearDown` (تلك تعمل بعد الفحص).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('لا عروضَ ⇒ حالةُ فراغٍ تشرح ولا تترك الشاشةَ بيضاء',
      (tester) async {
    await pump(tester, 1280, offers: const []);

    expect(tester.takeException(), isNull);
    expect(find.text('لا توجد عروض'), findsOneWidget);
    expect(find.textContaining('أنشئ باقةً'), findsOneWidget);
  });
}
