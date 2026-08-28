// تركيبُ شاشة مكتبة النماذج — على عرضَين، لا على «لم تنهر».
//
// ── لماذا عرضان ──────────────────────────────────────────────────────────
// الشاشةُ تطوي لوحةَ التفاصيل تحتَ ٩٠٠ بكسل. واختبارٌ على عرضٍ واحدٍ يقيس
// نصفَ التصميم: إمّا يفوته الطيُّ فتفيض اللوحةُ على الشاشات الضيّقة، وإمّا
// يفوته العرضُ الكامل فلا يُقاس المسارُ الذي يراه المالكُ فعلاً.
//
// ومقيسٌ في هذا المستودع أنّ اختبارَ التركيب يمسك ما تفوته اختباراتُ القطع —
// خمسةُ أعطابِ تخطيطٍ في جلسةٍ واحدة.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/data/providers/template_library_providers.dart';
import 'package:ural_erp/domain/models/picpos_template_card.dart';
import 'package:ural_erp/presentation/template_library_picpos/screens/template_library_picpos_screen.dart';
import 'package:ural_erp/presentation/template_library_picpos/widgets/template_detail_panel.dart';
import 'package:ural_erp/presentation/template_library_picpos/widgets/template_gallery_card.dart';

/// بطاقاتٌ مصنوعةٌ — التركيبُ يُقاس بلا قاعدةٍ مفتوحة.
List<TemplateCard> _cards(int n) => [
      for (var i = 0; i < n; i++)
        TemplateCard(
          id: i + 1,
          name: 'قالبُ اختبارٍ رقم ${i + 1} باسمٍ طويلٍ يلتفّ على سطرين',
          type: i.isEven ? 'a4' : 'thermal',
          category: 'invoice',
          paperWidthMm: i.isEven ? 210 : 80,
          paperHeightMm: i.isEven ? 297 : null,
          paperLabel: i.isEven ? 'A4' : '80mm',
          elementCount: 20 + i,
          columnCount: 5,
          layoutVersion: i.isEven ? 1 : 2,
          isDefault: i == 0,
          bindings: i == 1
              ? const [
                  TemplateBindingView(
                    documentLabel: 'فاتورة مبيعات',
                    documentType: 'sales_invoice',
                    scope: 'كل الفروع · عربي',
                  ),
                ]
              : const [],
        ),
    ];

Future<void> _pump(WidgetTester tester, double width,
    {int count = 6}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        templateCardsProvider.overrideWith((ref) async => _cards(count)),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        home: TemplateLibraryPicposScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('عرضُ سطح المكتب — ١٩٢٠', () {
    testWidgets('تُبنى بلا فيضٍ ولوحةُ التفاصيل ظاهرة', (tester) async {
      await _pump(tester, 1920);

      expect(tester.takeException(), isNull);
      expect(find.byType(TemplateGalleryCard), findsWidgets);
      expect(find.byType(TemplateDetailPanel), findsOneWidget,
          reason: 'اللوحةُ غابت عن عرضٍ يسعها');
    });
  });

  group('عرضُ اللابتوب — ١٢٨٠', () {
    testWidgets('تُبنى بلا فيضٍ واللوحةُ باقية', (tester) async {
      await _pump(tester, 1280);

      expect(tester.takeException(), isNull);
      expect(find.byType(TemplateGalleryCard), findsWidgets);
      expect(find.byType(TemplateDetailPanel), findsOneWidget);
    });
  });

  group('العرضُ الضيّق — ٧٢٠', () {
    testWidgets('تُطوى اللوحةُ ولا تفيض الشبكة', (tester) async {
      await _pump(tester, 720);

      expect(tester.takeException(), isNull,
          reason: 'الشبكةُ فاضت حين طُويت اللوحة');
      expect(find.byType(TemplateGalleryCard), findsWidgets);
      expect(find.byType(TemplateDetailPanel), findsNothing,
          reason: 'اللوحةُ بقيت على عرضٍ لا يسعها — وهو الفيضُ بعينه');
    });
  });

  testWidgets('ضابط: مكتبةٌ فارغةٌ تقول ذلك ولا تنهار', (tester) async {
    await _pump(tester, 1280, count: 0);

    expect(tester.takeException(), isNull);
    expect(find.byType(TemplateGalleryCard), findsNothing);
    expect(find.textContaining('لا قالبَ'), findsOneWidget,
        reason: 'شاشةٌ بيضاءُ بلا سببٍ مكتوب');
  });

  testWidgets('ضابط: الاختبارُ يبني بطاقاتٍ فعلاً لا شاشةً فارغة',
      (tester) async {
    // بلا هذا يمرّ كلُّ ما فوقه على شبكةٍ بلا عنصرٍ واحد.
    await _pump(tester, 1920);
    expect(tester.widgetList(find.byType(TemplateGalleryCard)).length,
        greaterThanOrEqualTo(3),
        reason: 'عددُ البطاقات المبنيّة أقلُّ ممّا أُعطي — التركيبُ يُقاس على '
            'شبكةٍ شبه فارغة');
  });
}
