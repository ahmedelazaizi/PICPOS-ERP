// بطاقةُ الأصل الثابت — تصميمُ المالك `(9)` و`(8)`.
//
// ═══ ما يقيسه هذا الملفّ ═══
//
// ‏١) 🔴 **العمرُ يُعرَض بالشهور**: «٣٦ شهراً» لا «٣ سنوات». والعمودُ
//    `usefulLifeYears` بالسنوات، و٣٦ فيه = إهلاكٌ على ستٍّ وثلاثين سنةً بدل
//    ثلاث — والقيدُ متّزنٌ على الرقم الخاطئ فلا فحصَ اتّزانٍ يمسكه.
//
// ‏٢) 🔴 **ثلاثةُ حقولٍ تُعرَض ولا تُحرَّر وسببُها مكتوب**: التكلفةُ دخلت
//    الأستاذَ بقيد اقتناءٍ مرحَّل، وتاريخُ الاقتناء أساسُ جدول الإهلاك،
//    والفئةُ تحدّد حسابَي الأصل والإهلاك. و`updateFixedAsset` لا تقبل أيّاً
//    منها أصلاً — فحقلٌ يَعِد بالتعديل ولا يفعله أسوأُ من حقلٍ يقول لماذا.
//
// ‏٣) 🔴 **وسمُ «مُرحَّل / متوقَّع» على كلّ صفّ**: التصميمُ يضع وسماً واحداً
//    فوق الجدول، وجدولُ أصلٍ نصفُه مُرحَّلٌ ونصفُه توقّعٌ هو الحالةُ
//    الطبيعيّةُ بعد أوّل شهر.
//
// ‏٤) **ورفعُ العهدة فعلٌ صريح**: `null` وحدَها تعني «لا تلمس» في توقيع
//    `updateFixedAsset`، فالبطاقةُ ترفع الرايةَ حين تُفرَّغ القائمة.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/fixed_assets_picpos/screens/asset_card_picpos.dart';
import 'package:ural_erp/data/providers/providers.dart';
import '../helpers/attachments_test_overrides.dart';

AssetCardValue _asset({
  String status = 'active',
  double lifeYears = 3,
  int? custodian,
  String? notes,
}) =>
    (
      id: 1,
      code: 'FA-001',
      name: 'جهاز حاسوب',
      categoryId: 9,
      categoryName: 'أجهزة مكتبية',
      location: 'الإدارة',
      purchasePrice: 12000,
      purchaseDate: DateTime(2026, 1, 1),
      usefulLifeYears: lifeYears,
      salvageValue: 0,
      depreciationMethod: 'straight_line',
      accumulatedDepreciation: 2000,
      status: status,
      notes: notes,
      custodianUserId: custodian,
    );

const _custodians = <AssetCustodianOption>[
  (id: 7, name: 'أحمد'),
  (id: 8, name: 'سارة'),
];

void main() {
  /// ما وصل `onSave` — يُفحَص بدل مراقبة نداءٍ صامت.
  late List<Map<String, Object?>> saved;
  late int backTaps;

  setUp(() {
    saved = [];
    backTaps = 0;
  });

  Future<void> pump(
    WidgetTester tester, {
    AssetCardValue? asset,
    List<AssetCardPosted> posted = const [],
    List<AssetCardMovement> movements = const [],
    bool canEdit = true,
    Size size = const Size(1400, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        // v176 / §٨ — البطاقةُ تحمل لوحَ مرفقاتٍ يقرأ مستودعاً.
        // بلا تجاوزٍ تُفتَح قاعدةٌ حقيقيّةٌ ولا يستقرّ `pumpAndSettle`.
        overrides: [
          attachmentsRepositoryProvider
              .overrideWithValue(fakeAttachmentsRepo()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AssetCardPicpos(
              asset: asset ?? _asset(),
              custodians: _custodians,
              posted: posted,
              movements: movements,
              canEdit: canEdit,
              onBack: () => backTaps++,
              onSave: ({
                required String name,
                required String? location,
                required String? notes,
                required int? custodianUserId,
                required bool clearCustodian,
              }) async {
                saved.add({
                  'name': name,
                  'location': location,
                  'notes': notes,
                  'custodian': custodianUserId,
                  'clear': clearCustodian,
                });
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('🔴 بيانات الأصل', () {
    testWidgets('الترويسةُ والتبويباتُ الثلاثة', (tester) async {
      await pump(tester);
      expect(find.text('FA-001'), findsOneWidget);
      expect(find.textContaining('بطاقة أصل ثابت'), findsWidgets);
      for (final t in ['بيانات الأصل', 'الإهلاك', 'الحركات']) {
        expect(find.text(t), findsWidgets, reason: 'التبويبة «$t» غائبة');
      }
      expect(find.text('قيد الاستخدام'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('🔴 وثلاثةُ حقولٍ تُعرَض ولا تُحرَّر — وسببُها مكتوب',
        (tester) async {
      await pump(tester);
      for (final label in ['الفئة', 'تاريخ الاقتناء', 'التكلفة']) {
        expect(find.text(label), findsWidgets, reason: 'الحقل «$label» غائب');
      }
      expect(find.textContaining('بقيد اقتناءٍ مرحَّل'), findsWidgets,
          reason: 'التكلفةُ معطَّلةٌ بلا كلمة — والمستخدمُ يظنّ الشاشةَ '
              'معطوبة');
      expect(find.textContaining('أساسُ جدول الإهلاك'), findsWidgets);
      expect(find.textContaining('حسابَي الأصل والإهلاك'), findsWidgets);
      // ولا حقلَ نصٍّ لأيٍّ منها.
      expect(find.text('12,000.00'), findsWidgets);
      await teardownTree(tester);
    });

    testWidgets('🔴 والعمرُ بالشهور لا بالسنوات', (tester) async {
      await pump(tester);
      expect(find.textContaining('36 شهراً'), findsWidgets,
          reason: '🔴 ٣٦ في حقل سنواتٍ = إهلاكٌ على ٣٦ سنةً بدل ٣');
      await teardownTree(tester);
    });

    testWidgets('✅ والمرفقاتُ لوحٌ لا لافتةُ تأجيل', (tester) async {
      await pump(tester);
      expect(find.text('ملاحظات'), findsOneWidget);
      // ✅ v176 — كانت هنا لافتةٌ تقول «المرفقاتُ في التصميم لا
      // تُبنى». بُنيت، فصار المطلوبُ **اللوحَ نفسَه** لا سببَ غيابِه.
      expect(find.byKey(const Key('attachments_panel')), findsOneWidget,
          reason: 'لوحُ المرفقات غاب عن بطاقة الأصل');
      await teardownTree(tester);
    });
  });

  group('🔴 المسؤول', () {
    testWidgets('يُسنَد ويصل الحفظَ', (tester) async {
      await pump(tester);
      await tester.tap(find.text('— بلا مسؤول —').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('سارة').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('حفظ التعديلات'));
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      expect(saved.single['custodian'], 8);
      expect(saved.single['clear'], isFalse);
      await teardownTree(tester);
    });

    testWidgets('🔴 وتفريغُه يرفع الرايةَ — لا `null` وحدَها', (tester) async {
      await pump(tester, asset: _asset(custodian: 7));
      await tester.tap(find.text('أحمد').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('— بلا مسؤول —').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('حفظ التعديلات'));
      await tester.pumpAndSettle();

      expect(saved.single['custodian'], isNull);
      expect(saved.single['clear'], isTrue,
          reason: '`null` وحدَها تعني «لا تلمس» — فالعهدةُ تبقى على مَن ترك '
              'العمل');
      await teardownTree(tester);
    });

    testWidgets('ومسؤولٌ لم يعد في القائمة يُقال صراحةً', (tester) async {
      await pump(tester, asset: _asset(custodian: 99));
      expect(find.textContaining('لم يعد في قائمة المستخدمين'), findsOneWidget,
          reason: 'قائمةٌ تبدو فارغةً بلا سببٍ تُقرأ «لا مسؤولَ له»');
      await teardownTree(tester);
    });
  });

  group('🔴 جدولُ الإهلاك — وسمٌ لكلّ صفّ', () {
    testWidgets('بلا ترحيلٍ: الصفوفُ كلُّها «متوقَّع»', (tester) async {
      await pump(tester);
      await openTab(tester, 'الإهلاك');
      expect(find.text('متوقَّع'), findsWidgets);
      expect(find.text('مُرحَّل'), findsNothing);
      expect(find.textContaining('الجدولُ كلُّه توقّع'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('🔴 وشهرٌ مُرحَّلٌ يُوسَم وحدَه', (tester) async {
      await pump(tester, posted: [
        (
          periodDate: DateTime(2026, 1, 28),
          amount: 333.33,
          accumulated: 333.33,
          bookValue: 11666.67
        ),
      ]);
      await openTab(tester, 'الإهلاك');
      expect(find.text('مُرحَّل'), findsOneWidget,
          reason: 'وسمٌ واحدٌ فوق الجدول كان يكذب على أحد النصفين');
      expect(find.text('متوقَّع'), findsWidgets);
      await teardownTree(tester);
    });

    testWidgets('والمجاميعُ حاضرة', (tester) async {
      await pump(tester);
      await openTab(tester, 'الإهلاك');
      expect(find.text('مجموع الإهلاك المتراكم'), findsOneWidget);
      expect(find.text('صافي القيمة الدفترية'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('و«فترة المعاينة حتى» تقول إنّها لا تُرحّل', (tester) async {
      await pump(tester);
      await openTab(tester, 'الإهلاك');
      expect(find.text('فترة المعاينة حتى'), findsOneWidget);
      expect(find.textContaining('يمدّ التوقّعَ ولا يُرحّل شيئاً'),
          findsOneWidget);
      await teardownTree(tester);
    });
  });

  group('الحركات', () {
    testWidgets('لا حركاتٍ ⇒ نائبٌ صريحٌ لا جدولٌ فارغ', (tester) async {
      await pump(tester);
      await openTab(tester, 'الحركات');
      expect(find.text('لا حركاتٍ على هذا الأصل'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('والنوعُ يُسمّى بالعربيّة لا برمزه', (tester) async {
      await pump(tester, movements: [
        (
          date: DateTime(2026, 1, 1),
          entryNumber: 'JV-0001',
          description: 'شراء أصل ثابت',
          referenceType: 'fixed_asset',
          isPosted: true,
        ),
        (
          date: DateTime(2026, 2, 1),
          entryNumber: 'JV-0002',
          description: 'إهلاك أصل',
          referenceType: 'asset_depreciation',
          isPosted: true,
        ),
      ]);
      await openTab(tester, 'الحركات');
      expect(find.text('اقتناء'), findsOneWidget);
      expect(find.text('إهلاك'), findsWidgets);
      expect(find.text('JV-0002'), findsOneWidget);
      await teardownTree(tester);
    });
  });

  group('🔴 والحفظُ محروس', () {
    testWidgets('بلا صلاحيّةٍ: الحقولُ والزرُّ معطَّلة', (tester) async {
      await pump(tester, canEdit: false);
      final btn = tester.widget<FilledButton>(find.ancestor(
        of: find.text('حفظ التعديلات'),
        matching: find.byType(FilledButton),
      ));
      expect(btn.onPressed, isNull,
          reason: '`assets_view` يفتح الشاشةَ للقراءة — والتعديلُ فعلُ '
              'كتابةٍ أعلى');
      await teardownTree(tester);
    });

    testWidgets('🔴 وأصلٌ مستبعدٌ بطاقتُه للقراءة وسببُه مكتوب',
        (tester) async {
      await pump(tester, asset: _asset(status: 'disposed'));
      expect(find.textContaining('أصلٌ خارجَ الخدمة'), findsOneWidget);
      final btn = tester.widget<FilledButton>(find.ancestor(
        of: find.text('حفظ التعديلات'),
        matching: find.byType(FilledButton),
      ));
      expect(btn.onPressed, isNull);
      await teardownTree(tester);
    });

    testWidgets('و«رجوع» يعود', (tester) async {
      await pump(tester);
      await tester.tap(find.text('رجوع'));
      await tester.pumpAndSettle();
      expect(backTaps, 1);
      await teardownTree(tester);
    });
  });

  group('ومراسي تركيب', () {
    for (final w in const [1100.0, 1400.0, 1920.0]) {
      testWidgets('البطاقةُ بلا فيضٍ عند ${w ~/ 1}', (tester) async {
        await pump(tester, size: Size(w, 1000), posted: [
          (
            periodDate: DateTime(2026, 1, 28),
            amount: 333.33,
            accumulated: 333.33,
            bookValue: 11666.67
          ),
        ]);
        expect(tester.takeException(), isNull);
        await openTab(tester, 'الإهلاك');
        expect(tester.takeException(), isNull);
        await openTab(tester, 'الحركات');
        expect(tester.takeException(), isNull);
        await teardownTree(tester);
      });
    }
  });
}
