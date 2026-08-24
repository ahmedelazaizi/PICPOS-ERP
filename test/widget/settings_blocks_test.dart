// test/widget/settings_blocks_test.dart
//
// اختبارُ بلوكات الإعدادات بعرضَين.
//
// ⚠️ الشبكةُ اثنا عشرَ عموداً: بلوكُ `span 5` على شاشةٍ ضيّقةٍ يصير أضيقَ من
// محتواه فيفيض — وهو نفسُ العطب الذي أمسكه اختبارُ العرضَين في تبويبات
// الحسابات مرّتين (١٧٣px و١٤٣px). فالانهيارُ إلى عمودٍ واحدٍ مقيسٌ هنا.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/presentation/settings_picpos/widgets/settings_blocks.dart';

Future<void> _pump(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    testWidgets('الشبكةُ تُبنى بلا فيضانٍ عند عرض $w', (tester) async {
      await _pump(
        tester,
        width,
        SettingsBlockGrid(
          blocks: [
            SettingsBlockSpan(
              span: 7,
              child: SettingsBlock(
                title: 'هوية الشركة والتشغيل',
                subtitle: 'تظهر في الفواتير',
                child: SettingsRowsBody(
                  children: [
                    SettingsValueRow(
                      first: true,
                      icon: PhosphorIconsBold.buildings,
                      title: 'معلومات الشركة',
                      sub: 'الاسم، السجل التجاري، الرقم الضريبي، الشعار',
                      value: 'مكتملة',
                      onTap: () {},
                    ),
                    const SettingsValueRow(
                      icon: PhosphorIconsBold.storefront,
                      title: 'نوع النشاط',
                      sub: 'يحدد الشاشات والحسابات المتاحة',
                      value: 'تجزئة',
                    ),
                  ],
                ),
              ),
            ),
            SettingsBlockSpan(
              span: 5,
              child: SettingsBlock(
                title: 'سلوك التشغيل',
                child: SettingsRowsBody(
                  children: [
                    SettingsSwitchRow(
                      first: true,
                      icon: PhosphorIconsBold.handTap,
                      title: 'نمط الإدخال اللمسي',
                      sub: 'لوحة مفاتيح على الشاشة في حقول الأرقام',
                      value: true,
                      onChanged: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('هوية الشركة والتشغيل'), findsOneWidget);
      expect(find.text('سلوك التشغيل'), findsOneWidget);
      expect(find.text('مكتملة'), findsOneWidget);
      expect(find.text('تجزئة'), findsOneWidget);
    });

    testWidgets('والاختياراتُ الثلاثةُ تظهر عند عرض $w', (tester) async {
      var picked = 'dark';
      await _pump(
        tester,
        width,
        SettingsBlock(
          title: 'مظهر البرنامج',
          child: SettingsChoiceBlock<String>(
            selected: picked,
            onSelect: (v) => picked = v,
            options: const [
              SettingsChoiceOption(
                  value: 'light', label: 'فاتح', sub: 'الأنسب للإضاءة القوية'),
              SettingsChoiceOption(
                  value: 'dark', label: 'غامق', sub: 'مريح في الورديات الليلية'),
              SettingsChoiceOption(
                  value: 'auto', label: 'تلقائي', sub: 'يتبع مظهر ويندوز'),
            ],
          ),
        ),
      );

      expect(find.text('فاتح'), findsOneWidget);
      expect(find.text('غامق'), findsOneWidget);
      expect(find.text('تلقائي'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('فاتح'));
      expect(picked, 'light');
    });

    testWidgets('والمربّعاتُ بحالتها عند عرض $w', (tester) async {
      await _pump(
        tester,
        width,
        SettingsBlock(
          title: 'الشاشات المتقدمة',
          child: SettingsTilesBlock(
            tiles: [
              SettingsTile(
                icon: PhosphorIconsBold.database,
                title: 'قاعدة البيانات',
                sub: 'نوع القاعدة ومسارها',
                meta: 'إعدادات الاتصال',
                dot: Colors.green,
                onTap: () {},
              ),
              SettingsTile(
                icon: PhosphorIconsBold.wifiHigh,
                title: 'الربط بين الفروع والسيرفر',
                sub: 'وضع الشبكة والمزامنة',
                meta: 'سيرفر رئيسي',
                dot: Colors.blue,
                onTap: () {},
              ),
            ],
          ),
        ),
      );

      expect(find.text('قاعدة البيانات'), findsOneWidget);
      expect(find.text('سيرفر رئيسي'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('الشبكةُ تنهار إلى عمودٍ واحدٍ على العرض الضيّق', (tester) async {
    // ⚠️ الحارسُ الذي يمنع أن يصير `span 5` أضيقَ من محتواه.
    await _pump(
      tester,
      700,
      const SettingsBlockGrid(
        blocks: [
          SettingsBlockSpan(
            span: 7,
            child: SettingsBlock(title: 'أ', child: SizedBox(height: 40)),
          ),
          SettingsBlockSpan(
            span: 5,
            child: SettingsBlock(title: 'ب', child: SizedBox(height: 40)),
          ),
        ],
      ),
    );

    final a = tester.getTopLeft(find.text('أ'));
    final b = tester.getTopLeft(find.text('ب'));
    expect(b.dy, greaterThan(a.dy),
        reason: 'على العرض الضيّق يقع البلوكان فوق بعضهما لا جنباً إلى جنب');
    expect(tester.takeException(), isNull);
  });

  testWidgets('وصفٌّ بلا قيمةٍ لا يرسم شريحةً فارغة', (tester) async {
    await _pump(
      tester,
      1920,
      const SettingsBlock(
        title: 'بلا قيمة',
        child: SettingsRowsBody(
          children: [
            SettingsValueRow(
              first: true,
              icon: PhosphorIconsBold.buildings,
              title: 'صفٌّ بلا قيمة',
            ),
          ],
        ),
      ),
    );

    expect(find.text('صفٌّ بلا قيمة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
