// test/widget/settings_unified_header_layout_test.dart
//
// تركيبُ الترويسة الموحّدة لشاشات الإعدادات الفرعيّة — بعرضَين.
//
// ⚠️ **العرضان ليسا احتياطاً**: `PicPosPageHeader` صفٌّ بلا تقييد، وحملُه
// الكاملُ (أيقونة + عنوان + مسار + بحث + زرُّ CTA) فاض ١٤٣px عند ١٢٨٠ ومرّ
// عند ١٩٢٠ في ربط الحسابات — موثَّقٌ في تعليقٍ داخلَ تلك الشاشة. وترويسةُ
// الطابعات والعطلات تحمل عينَ الحمل، فتُقاس عند العرضَين لا عند واحد.
//
// ولمَ اختبارُ تركيبٍ مع وجود الحارس البنيويّ: الحارسُ يقرأ سطرَ الدفع، وهذا
// يرسم الشاشةَ فعلاً — «لم ينهر» غيرُ كافٍ، فالمقياسُ أن يظهر العنوانُ
// والمسارُ وحقلُ البحث بلا فيضان.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_body_handle.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_screen_scaffold.dart';

Future<void> _pump(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pump();
}

/// ترويسةٌ بالحمل الكامل الذي يعطيه `HEADS` لشاشةٍ فرعيّة.
Widget _fullHeader({required String title, required String hint, String? cta}) {
  return PicPosScreenScaffold(
    title: title,
    subtitle: 'الإعدادات ← الأجهزة والطباعة',
    icon: PhosphorIconsBold.printer,
    headerSearch: TextField(
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
      ),
    ),
    headerActions: [
      if (cta != null)
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(PhosphorIconsBold.plus, size: 15),
          label: Text(cta),
        ),
    ],
    body: const SizedBox.shrink(),
  );
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    testWidgets('الترويسةُ بالحمل الكامل لا تفيض عند عرض $w', (tester) async {
      await _pump(
        tester,
        width,
        _fullHeader(
          title: 'إدارة الطابعات',
          hint: 'بحث باسم الطابعة...',
          cta: 'طابعة جديدة',
        ),
      );

      expect(tester.takeException(), isNull,
          reason: 'ترويسةُ الشاشة الفرعيّة فاضت عند $w — راجعْ حملَ الصفّ '
              '(أيقونة + عنوان + مسار + بحث + CTA).');

      expect(find.text('إدارة الطابعات'), findsOneWidget);
      expect(find.text('الإعدادات ← الأجهزة والطباعة'), findsOneWidget,
          reason: 'المسارُ (breadcrumb) لا يظهر — وهو نصفُ ما تعطيه '
              '`HEADS` لكلّ شاشةٍ فرعيّة.');
      expect(find.text('طابعة جديدة'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget,
          reason: 'حقلُ البحث لا يظهر في الترويسة.');
    });

    testWidgets('وأطولُ عنوانٍ ومسارٍ في HEADS لا يفيضان عند عرض $w',
        (tester) async {
      // أطولُ ما في `HEADS`: عنوانُ `network` ومسارُ `backup`.
      await _pump(
        tester,
        width,
        PicPosScreenScaffold(
          title: 'الربط بين الفروع والسيرفر',
          subtitle: 'الإعدادات ← النسخ الاحتياطي وإدارة البيانات',
          icon: PhosphorIconsBold.network,
          headerSearch: const TextField(
            decoration: InputDecoration(
              isDense: true,
              hintText: 'بحث في الإعدادات...',
            ),
          ),
          headerActions: [
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 15),
              label: const Text('مزامنة الآن'),
            ),
          ],
          body: const SizedBox.shrink(),
        ),
      );

      expect(tester.takeException(), isNull,
          reason: 'أطولُ عنوانٍ ومسارٍ في `HEADS` أفاضا الترويسةَ عند $w.');
      expect(find.text('الربط بين الفروع والسيرفر'), findsOneWidget);
    });
  }

  group('PicPosBodyHandle — الوصلةُ بين الترويسة والجسم', () {
    test('تبدأ غيرَ جاهزةٍ ثمّ تصير جاهزةً بالتسجيل', () {
      final h = PicPosBodyHandle();
      addTearDown(h.dispose);

      // الترويسةُ تُبنى قبل أوّلِ `initState` للجسم — فلولا أنّ الجاهزيّةَ
      // مُستمَعٌ إليها لبقي الزرُّ ميّتاً حتّى أوّلِ إعادةِ بناءٍ عارضة.
      expect(h.isReady.value, isFalse);

      var fired = 0;
      h.register(() => fired++);
      expect(h.isReady.value, isTrue);

      h.invoke();
      expect(fired, 1);
    });

    test('وفكُّ التسجيل يعيدها غيرَ جاهزةٍ ولا يستدعي شيئاً', () {
      final h = PicPosBodyHandle();
      addTearDown(h.dispose);

      var fired = 0;
      h.register(() => fired++);
      h.register(null);

      expect(h.isReady.value, isFalse);
      h.invoke(); // آمنٌ بعد فكِّ الربط — الجسمُ قد يكون تفكّك
      expect(fired, 0,
          reason: 'الوصلةُ استدعت إجراءً بعد فكِّ تسجيله — وذلك يعني '
              'استدعاءً على حالةٍ مُتفكّكة.');
    });

    test('والاستدعاءُ قبل أيّ تسجيلٍ لا ينهار', () {
      final h = PicPosBodyHandle();
      addTearDown(h.dispose);
      expect(h.invoke, returnsNormally);
    });
  });
}
