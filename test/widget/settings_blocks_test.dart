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
import 'package:picpos_erp/presentation/settings_picpos/widgets/settings_blocks.dart';

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

  group('الوضعُ الغامقُ يتعمّم على البلوكات', () {
    // ⚠️ بلاغُ المالك: «الوضعُ الداكن مش بيتعمّم على النظام ككل». والسببُ أنّ
    //    `AppColors.card` و`.surface` و`.border` ثوابتُ **الوضع الفاتح
    //    وحدَه** — فأيُّ ودجتٍ تكتبها مباشرةً تبقى بيضاءَ والشريطُ الجانبيُّ
    //    وحدَه يتبع الثيم. والقياسُ هنا يقارن اللونَ في الوضعين: تساويهما
    //    يعني أنّ اللونَ عاد مثبَّتاً.
    Future<Color?> blockColor(WidgetTester tester, Brightness brightness) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SettingsBlock(
                key: Key('probe'),
                title: 'بلوك',
                child: SizedBox(height: 40),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // البطاقةُ الخارجيّةُ تُعرَف بنصفِ قطرها ١٨ — لا بترتيبها في الشجرة،
      // فترتيبٌ يتبدّل بإعادةِ تنسيقٍ يجعل الاختبارَ يقيس صندوقاً آخر.
      final containers = tester.widgetList<Container>(
        find.descendant(
          of: find.byKey(const Key('probe')),
          matching: find.byType(Container),
        ),
      );
      final outer = containers.firstWhere((c) {
        final d = c.decoration;
        return d is BoxDecoration &&
            d.borderRadius == BorderRadius.circular(18);
      });
      return (outer.decoration as BoxDecoration).color;
    }

    // ⚠️ وضعٌ واحدٌ لكلِّ اختبار. ضخُّ الوضعين في اختبارٍ واحدٍ لا يقيس شيئاً:
    //    البلوكُ `const` فيُعاد استعمالُ نفسِ النسخة، فلا يُعاد بناءُ العنصر
    //    ويُقرأ لونُ الضخّة الأولى مرّتين — وقد أعطى ذلك «أبيضَ في الغامق»
    //    وهو خطأُ قياسٍ لا عطبُ كود.
    testWidgets('الفاتحُ فاتحٌ فعلاً', (tester) async {
      final light = await blockColor(tester, Brightness.light);
      expect(light, isNotNull);
      // اللمعانُ مقياسٌ موضوعيٌّ لا يربط الاختبارَ بقيمةٍ بعينها.
      expect(light!.computeLuminance(), greaterThan(0.7));
    });

    testWidgets('والغامقُ داكنٌ فعلاً لا فاتحٌ باسمٍ آخر', (tester) async {
      final dark = await blockColor(tester, Brightness.dark);
      expect(dark, isNotNull);
      expect(dark!.computeLuminance(), lessThan(0.2),
          reason: 'بطاقةٌ فاتحةٌ في الوضع الغامق = لونٌ مثبَّتٌ لا يتبع الثيم');
    });
  });

  testWidgets('شريحةُ القيمة والسهمُ في **طرف** الصفّ لا في منتصفه',
      (tester) async {
    // ⚠️ بلاغُ المالك: «مكانُ أسهم التوجيه مش مظبوط». والسببُ كان `Flexible`
    //    حول الشريحة: حصّتُه `flex: 1` مثلُ `Expanded` فوقه فيقتسمان الفراغ،
    //    فتقع الشريحةُ والسهمُ في المنتصف. والقياسُ هنا على المسافة من طرف
    //    الصفّ لا على قيمةٍ مطلقة.
    await _pump(
      tester,
      1920,
      SettingsBlock(
        title: 'قياس',
        child: SettingsRowsBody(
          children: [
            SettingsValueRow(
              first: true,
              icon: PhosphorIconsBold.storefront,
              title: 'نوع النشاط',
              sub: 'يحدد الشاشات المتاحة',
              value: 'تجزئة',
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    // في RTL طرفُ الصفّ هو حافتُه اليسرى.
    final rowLeft = tester.getTopLeft(find.byType(SettingsRowsBody)).dx;
    final chipLeft = tester.getTopLeft(find.text('تجزئة')).dx;
    final gap = chipLeft - rowLeft;

    expect(gap, lessThan(120),
        reason: 'الشريحةُ بعيدةٌ عن طرف الصفّ بـ$gap — علامةُ أنّها تقتسم '
            'الفراغَ مع العنوان بدل أن تلتصق بالطرف');
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
