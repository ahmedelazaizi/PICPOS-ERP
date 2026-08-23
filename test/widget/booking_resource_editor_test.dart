// test/widget/booking_resource_editor_test.dart
//
// محرِّرُ المورد — حقلُ ربطِ الموظَّف.
//
// ⚠️ بلاغُ المالك 2026-08-23: «أنشأتُ موظَّفين ولا يظهرون في حجز جديد». وكان
// المحرِّرُ لا يعرض حقلَ الموظَّف أصلاً، فلا سبيلَ لربطِ المورد بملفّه مهما
// حاول المستخدم.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/config/app_config.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/bookings_picpos/widgets/booking_catalog_editors.dart';

void main() {
  late AppDatabase db;
  late FeaturePolicy original;

  setUp(() async {
    db = AppDatabase.forTesting();
    // ⚠️ حالةٌ ساكنةٌ عالميّة — تُستعاد في `tearDown` وإلّا سرّبت إلى ملفّاتٍ
    //    أخرى فأسقطتها بترتيبٍ عشوائيّ.
    original = AppConfig.features;
    await db.into(db.employees).insert(
          EmployeesCompanion.insert(
            name: 'محمد الفنان',
            salary: const Value(3000),
          ),
        );
  });

  tearDown(() => AppConfig.updateFeatures(original));

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          // ⚠️ بثٌّ ثابتٌ بدل بثِّ drift الحيّ: الأخيرُ يترك مؤقّتاً معلَّقاً
          //    فيسقط الاختبارُ بـ`!timersPending`. ونفسُ النمط في
          //    `picpos_booking_panels_test.dart`.
          bookingLinkableEmployeesProvider.overrideWith(
            (ref) => Stream.value([
              Employee(
                id: 1,
                name: 'محمد الفنان',
                role: 'موظف',
                salary: 3000,
                salaryType: 'monthly',
                isActive: true,
                hiredAt: DateTime(2026, 1, 1),
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showResourceEditor(context),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();

    // ⚠️ مزوِّدُ الموظَّفين يبثّ من drift، ومؤقّتُه يبقى معلَّقاً فيسقط
    //    الاختبارُ بـ`!timersPending`. الوصفةُ: فكِّك الشجرةَ وادفع إطاراً —
    //    **ولا تُغلق القاعدة** (‏`close()` ينتظر نفسَ المؤقّت فيعلّق).
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('الموارد البشريّة مفعَّلةٌ ⇒ يظهر حقلُ ربطِ الموظَّف',
      (tester) async {
    AppConfig.updateFeatures(original.copyWith(hrEnabled: true));

    await pumpEditor(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('الموظَّف في الموارد البشريّة'), findsWidgets);
  });

  testWidgets('الموارد البشريّة مطفأةٌ ⇒ لا يظهر الحقلُ ولا يُعطّل الحفظ',
      (tester) async {
    // ملفَّا `restaurant` و`cafe` يفتحان الحجوزاتِ و`hrEnabled` مطفأةٌ
    // عندهما — فحقلٌ يشير إلى وحدةٍ محجوبةٍ تشويشٌ لا فائدة.
    AppConfig.updateFeatures(original.copyWith(hrEnabled: false));

    await pumpEditor(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('الموظَّف في الموارد البشريّة'), findsNothing);
    expect(find.text('الاسم'), findsWidgets,
        reason: 'بقيّةُ المحرِّر تعمل كما هي');
  });
}
