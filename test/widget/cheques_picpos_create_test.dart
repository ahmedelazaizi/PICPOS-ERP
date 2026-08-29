// test/widget/cheques_picpos_create_test.dart
//
// «ورقة جديدة» — الفعلُ الأوّلُ في رأس التصميم، وكان الفوركُ بلا أيٍّ منه.
//
// ═══ الفجوةُ المقيسة ═══
//
// `HEADS.main` في `PicPos Cheques.dc.html` يعرّف فعلَين: «ورقة جديدة»
// و«إيداع دفعة شيكات». وفوركُ PicPos كان بلا `headerActions` إطلاقاً —
// فالشاشةُ تعرض الأوراقَ ولا تُنشئ ورقةً، والمستخدمُ يرجع إلى الشاشة
// القديمة ليضيف شيكاً ثمّ يعود ليراه هنا.
//
// ⚠️ **والمقيسُ هنا الحارسُ والتحقّق، لا ظهورُ الزرّ.** إنشاءُ ورقةٍ يفتح
//    ذمّةً ويكتب على الخادم في وضع العميل — فزرٌّ بلا حارسٍ ثغرة، وحوارٌ
//    يحفظ بحقلٍ ناقصٍ يكتب ورقةً لا تُقرأ.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/commercial_papers_repository.dart'
    show ICommercialPapersRepository;
import 'package:ural_erp/presentation/settings_picpos/screens/cheques_picpos_screen.dart';

class _FakePapersRepo implements ICommercialPapersRepository {
  @override
  Stream<List<CommercialPaperData>> watchCommercialPapers({
    String? direction,
    String? status,
  }) =>
      Stream.value(const []);

  @override
  Stream<List<PaperStatusHistoryData>> watchPaperHistory(int id) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTreasuryRepo implements ITreasuryRepository {
  @override
  Future<List<SafeData>> getSafesList() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(
  WidgetTester tester,
  double width, {
  List<String> perms = const ['commercial_papers_manage'],
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        commercialPapersRepositoryProvider
            .overrideWithValue(_FakePapersRepo()),
        treasuryRepositoryProvider.overrideWithValue(_FakeTreasuryRepo()),
        allPartiesProvider.overrideWith((ref) => Stream.value(const <Party>[])),
        currentUserPermissionsProvider.overrideWith((ref) async => perms),
      ],
      child: const MaterialApp(home: ChequesPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    group('عرض $w', () {
      testWidgets('«ورقة جديدة» حاضرٌ في الرأس', (tester) async {
        await _open(tester, width);

        expect(find.text('ورقة جديدة'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('🔴 وبلا صلاحيةٍ لا يظهر — الشاشةُ للقراءة لا للإنشاء',
          (tester) async {
        // ⚠️ حصرُ التنقّل يفتح الشاشةَ لمن يقرأ الأوراق. فزرُّ الإنشاء
        //    يحرسه كودُه هو (`commercial_papers_manage`) لا كودُ الشاشة.
        await _open(tester, width, perms: const ['settings_view']);

        expect(find.text('ورقة جديدة'), findsNothing);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('والضغطُ يفتح حوارَ التصميم بعنوانه وأقسامِه',
          (tester) async {
        await _open(tester, width);

        await tester.tap(find.text('ورقة جديدة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('ورقة تجارية جديدة'), findsOneWidget);
        expect(find.text('شيك أو كمبيالة — وارد من عميل أو صادر لمورد'),
            findsOneWidget);
        expect(find.text('النوع والاتجاه'), findsOneWidget);
        expect(find.text('بيانات الورقة'), findsOneWidget);
        expect(find.text('وارد من عميل'), findsOneWidget);
        expect(find.text('صادر لمورد'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('🔴 ونموذجٌ ناقصٌ لا يُحفَظ — والسببُ مكتوبٌ لا مسكوتٌ عنه',
          (tester) async {
        // ⚠️ الحوارُ القديمُ يرتدّ **صامتاً** حين ينقص حقلٌ إلزاميّ
        //    (‏تعليقٌ صريحٌ فيه: «Should show validation but handled in
        //    caller for now»). فالمستخدمُ يضغط ولا يحدث شيءٌ ولا يعرف
        //    لماذا. وهذا الفوركُ يُعطّل الزرَّ **ويقول** ما ينقص.
        await _open(tester, width);

        await tester.tap(find.text('ورقة جديدة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('رقمُ الورقة مطلوب'), findsOneWidget);

        final save = tester.widget<InkWell>(
          find
              .ancestor(
                of: find.text('حفظ الورقة'),
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(save.onTap, isNull,
            reason: 'زرٌّ مفعَّلٌ على نموذجٍ ناقصٍ يكتب ورقةً بلا رقمٍ ولا طرف');
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('واستحقاقٌ سليمٌ لا يمنع — الرقمُ وحدَه هو الناقص',
          (tester) async {
        // ⚠️ مرساةٌ للفحص نفسِه: لو ردَّ `_blocker` نصَّه الأوّلَ دائماً
        //    لمرّ الاختبارُ السابقُ على حارسٍ لا يميّز شيئاً.
        await _open(tester, width);

        await tester.tap(find.text('ورقة جديدة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        await tester.enterText(
          find.widgetWithText(TextField, 'رقم الورقة *'),
          'CHQ-77',
        );
        await tester.pump();

        // الرقمُ اكتمل ⇒ الرسالةُ انتقلت إلى الناقص التالي.
        expect(find.text('رقمُ الورقة مطلوب'), findsNothing);
        expect(find.text('المبلغُ مطلوبٌ وأكبرُ من صفر'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }
}
