// test/widget/settings_nav_rail_test.dart
//
// اختبارُ عمود أقسام الإعدادات بعرضَين.
//
// ⚠️ الاختبارُ القائمُ للإعدادات يقيس أنّ الشاشة «قابلةٌ للإنشاء» فحسب
// (`expect(const SettingsPicposScreen(), isA<Widget>())`) — وهو لا يمسك
// شيئاً. والعمودُ مفصولٌ عن الشاشة كي يُقاس فعلاً: أقسامُه ومجموعاتُه
// وتذييلُه، بلا قاعدةِ بياناتٍ ولا عشراتِ المزوِّدات.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/presentation/settings_picpos/widgets/settings_nav_rail.dart';
import 'package:picpos_erp/services/license_service.dart';

const _items = <SettingsNavRailItem>[
  SettingsNavRailItem(
      id: 'system',
      title: 'النظام والمظهر',
      icon: PhosphorIconsBold.slidersHorizontal,
      group: 'التشغيل',
      desc: 'الشركة · العملة · المظهر'),
  SettingsNavRailItem(
      id: 'devices',
      title: 'الأجهزة والطباعة',
      icon: PhosphorIconsBold.printer,
      group: 'التشغيل',
      desc: 'طابعات · نقاط بيع · قوالب'),
  SettingsNavRailItem(
      id: 'users',
      title: 'المستخدمون والأمان',
      icon: PhosphorIconsBold.shieldCheck,
      group: 'الأمان',
      desc: 'الحسابات · الأدوار · الصلاحيات'),
  SettingsNavRailItem(
      id: 'cloud',
      title: 'الربط السحابي',
      icon: PhosphorIconsBold.cloud,
      group: 'الربط',
      desc: 'السحابة · الأجهزة المقترنة'),
  SettingsNavRailItem(
      id: 'data',
      title: 'إدارة البيانات',
      icon: PhosphorIconsBold.database,
      group: 'المال والبيانات',
      desc: 'النسخ الاحتياطي · الاستعادة'),
  SettingsNavRailItem(
      id: 'about',
      title: 'عن البرنامج',
      icon: PhosphorIconsBold.info,
      group: 'الامتدادات',
      desc: 'الإصدار · الترخيص · التشخيص'),
];

void main() {
  Future<String?> pump(
    WidgetTester tester,
    double width, {
    List<SettingsNavRailItem> items = _items,
    String selectedId = 'system',
    bool activated = true,
  }) async {
    String? tapped;
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activationStatusProvider.overrideWith((ref) async => activated),
        ],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Row(
                children: [
                  SettingsNavRail(
                    items: items,
                    selectedId: selectedId,
                    onSelect: (id) => tapped = id,
                    search: const TextField(
                      decoration:
                          InputDecoration(hintText: 'بحث في الإعدادات…'),
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return tapped;
  }

  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    testWidgets('يُبنى بلا استثناءِ تخطيطٍ عند عرض $w', (tester) async {
      await pump(tester, width);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ويعرض كلَّ قسمٍ ووصفَه عند عرض $w', (tester) async {
      await pump(tester, width);
      for (final item in _items) {
        expect(find.text(item.title), findsOneWidget,
            reason: 'القسمُ ${item.title} غائبٌ عن العمود عند $w');
        expect(find.text(item.desc), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('والمجموعاتُ الخمسُ عناوينُها ظاهرةٌ عند عرض $w',
        (tester) async {
      await pump(tester, width);
      for (final group in kSettingsGroupOrder) {
        expect(find.text(group), findsOneWidget);
      }
    });
  }

  testWidgets('عرضُ العمود ٣٢٦ كما في التصميم', (tester) async {
    await pump(tester, 1920);
    final box = tester.getSize(find.byType(SettingsNavRail));
    expect(box.width, 326);
  });

  testWidgets('المجموعاتُ بترتيب التصميم لا بترتيب الأقسام', (tester) async {
    await pump(tester, 1920);
    double yOf(String label) => tester.getTopLeft(find.text(label)).dy;

    expect(yOf('التشغيل'), lessThan(yOf('الأمان')));
    expect(yOf('الأمان'), lessThan(yOf('الربط')));
    expect(yOf('الربط'), lessThan(yOf('المال والبيانات')));
    expect(yOf('المال والبيانات'), lessThan(yOf('الامتدادات')));
  });

  testWidgets('مجموعةٌ خارجَ قائمة الترتيب لا تُسقِط قسمَها', (tester) async {
    // ⚠️ الحارسُ الذي يمنع اختفاءَ قسمٍ بصمتٍ لو أُضيفت له مجموعةٌ جديدة.
    await pump(
      tester,
      1920,
      items: const [
        ..._items,
        SettingsNavRailItem(
            id: 'lab',
            title: 'قسمٌ مستجدّ',
            icon: PhosphorIconsBold.flask,
            group: 'مجموعةٌ لم تُذكر',
            desc: 'وصفٌ ما'),
      ],
    );

    expect(find.text('قسمٌ مستجدّ'), findsOneWidget);
    expect(find.text('مجموعةٌ لم تُذكر'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('النقرُ يبلّغ معرِّفَ القسم', (tester) async {
    late String? tapped;
    tester.view.physicalSize = const Size(1920, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activationStatusProvider.overrideWith((ref) async => true),
        ],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SettingsNavRail(
                items: _items,
                selectedId: 'system',
                onSelect: (id) => tapped = id,
                search: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('إدارة البيانات'));
    expect(tapped, 'data');
  });

  group('تذييلُ العمود', () {
    testWidgets('يعرض «مرخّصة» حين التفعيلُ قائم', (tester) async {
      await pump(tester, 1920, activated: true);
      expect(find.text('مرخّصة'), findsOneWidget);
      expect(find.text('غير مفعّلة'), findsNothing);
    });

    testWidgets('و«غير مفعّلة» حين لا تفعيل — لا يُطمئن كذباً',
        (tester) async {
      await pump(tester, 1920, activated: false);
      expect(find.text('غير مفعّلة'), findsOneWidget);
      expect(find.text('مرخّصة'), findsNothing);
    });

    testWidgets('ورقمُ النسخة يتبع [AppConstants.appVersion] لا نصّاً ثابتاً',
        (tester) async {
      // ⚠️ بلاغُ المالك 2026-08-22: «رقمُ الإصدار لا يظهر تحديثُه». والقيمةُ
      //    ساكنةٌ متغيّرةٌ يملؤها `AppVersionService` عند الإقلاع، فتبقى في
      //    الاختبارات على افتراضها. فالقياسُ الصادقُ أن **نحرّكها** ونرى
      //    الواجهةَ تتبعها — نصٌّ مكتوبٌ بيدٍ لا يتحرّك.
      final original = AppConstants.appVersion;
      addTearDown(() => AppConstants.appVersion = original);

      AppConstants.appVersion = '9.9.9-test';
      await pump(tester, 1920);

      expect(find.text('النسخة 9.9.9-test'), findsOneWidget);
      expect(find.text('النسخة $original'), findsNothing);
    });
  });
}
