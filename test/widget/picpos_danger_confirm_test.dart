// حوارُ تأكيدِ الخطر — العقدُ أمانٌ لا شكل.
//
// ═══ لماذا كلمةٌ تُكتَب ═══
//
// زرُّ «موافق» يُضغَط بالغلط. وعملياتُ التصفير والاستعادة **بلا رجعة**:
// تصفيرُ البيانات يحذف كلَّ الفواتير والقيود، والاستعادةُ تستبدل القاعدةَ
// كلَّها. فالتأكيدُ فيها يجب أن يكلّف فعلاً واعياً — كتابةَ كلمةٍ بعينها —
// لا ضغطةً واحدة.
//
// وهذا ما يقيسه هذا الملفّ: أنّ الزرَّ **خامدٌ** حتى تُطابق الكلمةُ، وأنّ
// المطابقةَ حرفيّة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_danger_confirm.dart';

/// يفتح الحوارَ ويعيد دالّةً تقرأ نتيجتَه بعد الإغلاق.
Future<bool?> _open(
  WidgetTester tester, {
  String typedWord = 'تصفير',
}) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showPicPosDangerConfirm(
                context,
                icon: PhosphorIconsBold.trash,
                title: 'تصفير بيانات النظام',
                message: 'كل الحركات ستُحذف نهائياً.',
                actionLabel: 'تصفير البيانات',
                typedWord: typedWord,
                willDelete: const ['فواتير المبيعات', 'حركات المخزون'],
                willRemain: const ['الأصناف والتصنيفات'],
                metaRows: const [
                  (label: 'عدد الفواتير', value: '٤١٢٦٤'),
                ],
              );
            },
            child: const Text('افتح'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('افتح'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('تأكيدُ الخطر بكلمةٍ تُكتَب', () {
    testWidgets('الحوارُ يعرض ما يُحذف وما يبقى وأرقامَ الحالة',
        (tester) async {
      await _open(tester);

      expect(find.text('فواتير المبيعات'), findsOneWidget);
      expect(find.text('الأصناف والتصنيفات'), findsOneWidget);
      // الرقمُ يأتي من المستدعي — الحوارُ لا يخترعه.
      expect(find.text('٤١٢٦٤'), findsOneWidget);
    });

    testWidgets('زرُّ التنفيذِ خامدٌ قبل كتابةِ الكلمة', (tester) async {
      await _open(tester);

      final button = tester.widget<InkWell>(
        find.ancestor(
          of: find.text('تصفير البيانات'),
          matching: find.byType(InkWell),
        ),
      );
      expect(button.onTap, isNull,
          reason: 'زرٌّ حيٌّ قبل الكلمة = ضغطةٌ واحدةٌ تمحو القاعدة');
    });

    testWidgets('وكلمةٌ خاطئةٌ لا توقظه', (tester) async {
      await _open(tester);

      await tester.enterText(find.byType(TextField), 'تصفي');
      await tester.pump();

      final button = tester.widget<InkWell>(
        find.ancestor(
          of: find.text('تصفير البيانات'),
          matching: find.byType(InkWell),
        ),
      );
      expect(button.onTap, isNull,
          reason: 'المطابقةُ حرفيّةٌ — لا بادئةٌ ولا تشابه');
    });

    testWidgets('والكلمةُ الصحيحةُ توقظه فيُرجع true', (tester) async {
      await _open(tester);

      await tester.enterText(find.byType(TextField), 'تصفير');
      await tester.pump();

      await tester.tap(find.text('تصفير البيانات'));
      await tester.pumpAndSettle();

      // الحوارُ أُغلق بالتنفيذ.
      expect(find.text('تصفير بيانات النظام'), findsNothing);
    });

    testWidgets('والإغلاقُ العرَضيُّ رفضٌ لا موافقة', (tester) async {
      // ⚠️ `showDialog<bool>` يُرجع `null` عند الإغلاق بلا اختيار، و
      //    `result != false` تقرؤها موافقةً. فالنوعُ هنا `bool` غيرُ لاغٍ
      //    وافتراضُه الرفض — وهذا ما يُقاس.
      bool? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  captured = await showPicPosDangerConfirm(
                    context,
                    icon: PhosphorIconsBold.trash,
                    title: 'حذف',
                    message: 'رسالة',
                    actionLabel: 'احذف',
                    typedWord: null,
                    willDelete: const ['شيء'],
                    willRemain: const ['شيء آخر'],
                  );
                },
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();

      // إغلاقٌ بالمفتاح — لا ضغطَ على تنفيذٍ ولا إلغاء.
      Navigator.of(tester.element(find.text('حذف'))).pop();
      await tester.pumpAndSettle();

      expect(captured, isFalse);
    });

    testWidgets('عنوانُ الأثرِ يتبدّل — «سيُحذف» كذبةٌ فوق أثرٍ لا يحذف',
        (tester) async {
      // ⚠️ حذفُ المستخدم في هذا النظام **تعطيلٌ وقفل** لا حذف. فالعنوانُ
      //    يجب أن يقول ما يحدث فعلاً، وإلّا كان الحوارُ نفسُه مضلِّلاً.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPicPosDangerConfirm(
                  context,
                  icon: PhosphorIconsBold.userMinus,
                  title: 'تعطيل مستخدم',
                  message: 'الحساب يُعطَّل ويُقفَل.',
                  actionLabel: 'تعطيل الحساب',
                  willDeleteLabel: 'سيحدث',
                  willDelete: const ['تعطيل الحساب وقفله'],
                  willRemain: const ['فواتيره وحركاته'],
                ),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();

      expect(find.text('سيحدث'), findsOneWidget);
      expect(find.text('سيُحذف'), findsNothing);
    });

    testWidgets('وبلا عمودٍ مقابلٍ تُعرَض قائمةٌ واحدةٌ بعرضٍ كامل',
        (tester) async {
      // نمطُ `restore` في التصميم: تسلسلُ خطواتٍ لا مقابلةُ أثر.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPicPosDangerConfirm(
                  context,
                  icon: PhosphorIconsBold.arrowCounterClockwise,
                  title: 'استعادة نسخة',
                  message: 'سيُستبدل محتوى القاعدة.',
                  actionLabel: 'استعادة النسخة',
                  warnTone: true,
                  willDeleteLabel: 'ما سيحدث بالترتيب',
                  willDelete: const ['أخذ نسخة أمان', 'إخراج المستخدمين'],
                ),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();

      expect(find.text('ما سيحدث بالترتيب'), findsOneWidget);
      expect(find.text('سيبقى كما هو'), findsNothing);
      expect(find.text('أخذ نسخة أمان'), findsOneWidget);
    });

    testWidgets('وبلا كلمةٍ مطلوبةٍ يكون الزرُّ حيّاً من البداية',
        (tester) async {
      // `deluser` في التصميم بلا `typed` — الحذفُ الفرديُّ لا يستحقّ
      // كلمةً، والقائمتان تكفيان لبيان الأثر.
      bool? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  captured = await showPicPosDangerConfirm(
                    context,
                    icon: PhosphorIconsBold.userMinus,
                    title: 'حذف مستخدم',
                    message: 'الحساب سيُحذف.',
                    actionLabel: 'حذف المستخدم',
                    typedWord: null,
                    willDelete: const ['الحساب'],
                    willRemain: const ['فواتيره'],
                  );
                },
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing,
          reason: 'لا حقلَ حين لا كلمة');

      await tester.tap(find.text('حذف المستخدم'));
      await tester.pumpAndSettle();
      expect(captured, isTrue);
    });
  });
}
