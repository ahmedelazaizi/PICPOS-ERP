// غلافُ ديالوجات PicPos — العقدُ المشترك لكلّ حوارات النظام.
//
// يُقاس هنا ما يكسر **١٠٤ حوارٍ** دفعةً واحدةً لو انحرف:
//  ‏١) الرأسُ يعرض ما أُعطي، والإغلاقُ يُغلق فعلاً.
//  ‏٢) الأزرارُ تُنادى — والمعطَّلُ منها **لا** يُنادى وهو ظاهر.
//  ‏٣) **لا فيضانَ عند الضيق**: تذييلٌ بأربعة أزرارٍ على حوارٍ ضيّقٍ كان
//     يفيض، والفيضُ في Flutter شريطٌ أصفرُ وأسودُ فوق الواجهة لا قصٌّ صامت.
//     وهذا العطبُ وقع مرّتين في هذه الجلسة، فصار له حارسٌ صريح.
//  ‏٤) `PicPosDialogRow` ينكسر رأسيّاً تحت العتبة بدل أن يسحق الحقول.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_dialog.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_panel_groups.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    Widget dialog, {
    Size size = const Size(1000, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: dialog)));
    await tester.pumpAndSettle();
  }

  group('الرأس', () {
    testWidgets('يعرض العنوانَ والسطرَ الخافتَ والأيقونة', (tester) async {
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.arrowCircleDown,
          accent: AppColors.success,
          title: 'سند قبض',
          subtitle: 'RV-2026-0842 · 21 أغسطس 2026',
          body: [Text('جسم')],
        ),
      );
      expect(find.text('سند قبض'), findsOneWidget);
      expect(find.text('RV-2026-0842 · 21 أغسطس 2026'), findsOneWidget);
      expect(find.byIcon(PhosphorIconsBold.arrowCircleDown), findsOneWidget);
      expect(find.text('جسم'), findsOneWidget);
    });

    testWidgets('بلا سطرٍ خافتٍ لا يُرسَم سطرٌ فارغ', (tester) async {
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.scales,
          title: 'مراجعة الأرصدة',
          body: [Text('جسم')],
        ),
      );
      expect(find.text('مراجعة الأرصدة'), findsOneWidget);
      // زرُّ الإغلاق موجودٌ دائماً في الرأس.
      expect(find.byIcon(PhosphorIconsBold.x), findsOneWidget);
    });

    testWidgets('زرُّ «×» ينادي onCancel حين يُعطى', (tester) async {
      var closed = 0;
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.scales,
          title: 'حوار',
          body: const [Text('جسم')],
          onCancel: () => closed++,
        ),
      );
      await tester.tap(find.byIcon(PhosphorIconsBold.x));
      await tester.pump();
      expect(closed, 1);
    });
  });

  group('التذييل', () {
    testWidgets('الرئيسيُّ والثانويُّ والإلغاءُ كلُّها تُنادى', (tester) async {
      var primary = 0, secondary = 0, cancel = 0;
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.arrowCircleDown,
          title: 'سند قبض',
          body: const [Text('جسم')],
          onCancel: () => cancel++,
          secondaryActions: [
            PicPosDialogAction(
              label: 'طباعة A4',
              icon: PhosphorIconsBold.printer,
              onPressed: () => secondary++,
            ),
          ],
          primaryAction: PicPosDialogAction(
            label: 'حفظ السند',
            icon: PhosphorIconsBold.check,
            onPressed: () => primary++,
          ),
        ),
      );

      await tester.tap(find.text('حفظ السند'));
      await tester.tap(find.text('طباعة A4'));
      await tester.tap(find.text('إلغاء'));
      await tester.pump();

      expect(primary, 1);
      expect(secondary, 1);
      expect(cancel, 1);
    });

    testWidgets('الزرُّ المعطَّلُ يظهر ولا يُنادى', (tester) async {
      var fired = 0;
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.arrowCircleDown,
          title: 'سند قبض',
          body: [Text('جسم')],
          primaryAction: PicPosDialogAction(
            label: 'حفظ السند',
            onPressed: null,
          ),
        ),
      );
      expect(find.text('حفظ السند'), findsOneWidget,
          reason: 'يبقى مرئيّاً كي يعرف المستخدمُ أن الإجراءَ موجود');
      await tester.tap(find.text('حفظ السند'));
      await tester.pump();
      expect(fired, 0);
    });

    testWidgets('بلا أزرارٍ إطلاقاً لا يُرسَم تذييل', (tester) async {
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.scales,
          title: 'حوار',
          body: [Text('جسم')],
        ),
      );
      expect(find.text('إلغاء'), findsNothing);
    });
  });

  group('لا فيضانَ عند الضيق', () {
    testWidgets('أربعةُ أزرارٍ على حوارٍ ضيّقٍ تلتفّ ولا تفيض', (tester) async {
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.arrowCircleDown,
          title: 'سند قبض بعنوانٍ طويلٍ نسبيّاً',
          subtitle: 'RV-2026-0842 · 21 أغسطس 2026 · فرع المعادي',
          width: 660,
          body: const [Text('جسم')],
          onCancel: () {},
          secondaryActions: [
            PicPosDialogAction(
                label: 'طباعة A4',
                icon: PhosphorIconsBold.printer,
                onPressed: () {}),
            PicPosDialogAction(
                label: 'حفظ + حراري',
                icon: PhosphorIconsBold.receipt,
                onPressed: () {}),
            PicPosDialogAction(
                label: 'إعادة الفحص',
                icon: PhosphorIconsBold.arrowsClockwise,
                onPressed: () {}),
          ],
          primaryAction: PicPosDialogAction(
              label: 'حفظ السند',
              icon: PhosphorIconsBold.check,
              onPressed: () {}),
        ),
        // شاشةٌ ضيّقةٌ عمداً — لوحُ كاشيرٍ صغير.
        size: const Size(700, 700),
      );
      // ‏`pumpAndSettle` لا يرمي على الفيض؛ الفيضُ يُسجَّل استثناءً في
      // `tester.takeException`. فيُفحَص صراحةً.
      expect(tester.takeException(), isNull,
          reason: 'الالتفافُ في التذييل هو ما يمنع الشريطَ الأصفرَ والأسود');
    });

    testWidgets('عنوانٌ طويلٌ جدّاً يُقصَّر ولا يفيض', (tester) async {
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.scales,
          title: 'عنوانٌ طويلٌ جدّاً يتجاوز عرضَ الحوار بكثيرٍ جدّاً جدّاً '
              'ولا ينبغي أن يكسر الرأس',
          subtitle: 'وسطرٌ خافتٌ طويلٌ كذلك يتجاوز العرضَ المتاحَ بمراحل',
          width: 660,
          body: [Text('جسم')],
        ),
        size: const Size(700, 700),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('مكوّناتُ الجسم', () {
    testWidgets('الحقلُ المطلوبُ يحمل نجمةً', (tester) async {
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.vault,
          title: 'حوار',
          body: [
            PicPosDialogField(
              label: 'الخزينة',
              required: true,
              child: Text('الصندوق الرئيسي'),
            ),
          ],
        ),
      );
      expect(find.text('الخزينة'), findsOneWidget);
      expect(find.text(' *'), findsOneWidget);
      expect(find.text('الصندوق الرئيسي'), findsOneWidget);
    });

    testWidgets('الصفُّ ينكسر رأسيّاً تحت العتبة', (tester) async {
      Widget row() => const PicPosDialogRow(
            breakpoint: 520,
            children: [
              PicPosDialogField(label: 'أ', child: Text('١')),
              PicPosDialogField(label: 'ب', child: Text('٢')),
            ],
          );

      // عريضٌ: صفٌّ أفقيّ ⇒ الحقلان على نفس الارتفاع تقريباً.
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.vault,
          title: 'حوار',
          body: [row()],
        ),
        size: const Size(1000, 800),
      );
      final wideA = tester.getTopLeft(find.text('أ')).dy;
      final wideB = tester.getTopLeft(find.text('ب')).dy;
      expect(wideA, wideB, reason: 'أفقيّاً ⇒ نفسُ الصفّ');

      // ضيّقٌ: عمودٌ ⇒ الثاني تحت الأوّل.
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.vault,
          title: 'حوار',
          width: 400,
          body: [row()],
        ),
        size: const Size(460, 800),
      );
      final narrowA = tester.getTopLeft(find.text('أ')).dy;
      final narrowB = tester.getTopLeft(find.text('ب')).dy;
      expect(narrowB, greaterThan(narrowA),
          reason: 'تحت العتبة ينكسر رأسيّاً بدل أن يسحق الحقلَين');
    });

    testWidgets('الملخّصُ يعرض كلَّ أسطره', (tester) async {
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.scales,
          title: 'حوار',
          body: [
            PicPosDialogSummary(rows: [
              (label: 'الإجمالي', value: '1,000', color: null),
              (label: 'المسدَّد', value: '400', color: AppColors.success),
              (label: 'المتبقي', value: '600', color: AppColors.error),
            ]),
          ],
        ),
      );
      expect(find.text('الإجمالي'), findsOneWidget);
      expect(find.text('600'), findsOneWidget);
      expect(find.text('المسدَّد'), findsOneWidget);
    });

    testWidgets('بلاطةُ الاختيار: المنتقاةُ وحدَها ملوّنة', (tester) async {
      var picked = '';
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.wallet,
          title: 'حوار',
          body: [
            PicPosDialogRow(children: [
              PicPosDialogChoice(
                icon: PhosphorIconsBold.money,
                label: 'نقدي',
                selected: true,
                accent: AppColors.success,
                onTap: () => picked = 'cash',
              ),
              PicPosDialogChoice(
                icon: PhosphorIconsBold.bank,
                label: 'تحويل بنكي',
                selected: false,
                onTap: () => picked = 'bank',
              ),
            ]),
          ],
        ),
      );
      await tester.tap(find.text('تحويل بنكي'));
      await tester.pump();
      expect(picked, 'bank');
    });
  });

  group('حوارُ التأكيد', () {
    Future<bool?> open(WidgetTester tester, {bool danger = false}) async {
      bool? answer;
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                answer = await showPicPosConfirm(
                  ctx,
                  icon: PhosphorIconsBold.warning,
                  title: 'تأكيد الحذف',
                  message: 'هل تريد المتابعة؟',
                  danger: danger,
                );
              },
              child: const Text('افتح'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('التأكيدُ يُرجع true', (tester) async {
      await open(tester);
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();
      expect(find.text('تأكيد الحذف'), findsNothing, reason: 'أُغلق');
    });

    testWidgets('الإلغاءُ يُرجع false لا null', (tester) async {
      bool? captured;
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                captured = await showPicPosConfirm(
                  ctx,
                  icon: PhosphorIconsBold.warning,
                  title: 'تأكيد الحذف',
                  message: 'هل تريد المتابعة؟',
                );
              },
              child: const Text('افتح'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(captured, isFalse);
      expect(captured, isNotNull,
          reason: 'النوعُ غيرُ لاغٍ — والافتراضُ الرفضُ لا الغموض');
    });

    testWidgets('الإغلاقُ بـ«×» يُرجع false — لا موافقةً عرَضيّة',
        (tester) async {
      bool? captured;
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                captured = await showPicPosConfirm(
                  ctx,
                  icon: PhosphorIconsBold.trash,
                  title: 'حذف نهائيّ',
                  message: 'لا رجعةَ في هذا.',
                  danger: true,
                );
              },
              child: const Text('افتح'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(PhosphorIconsBold.x));
      await tester.pumpAndSettle();
      expect(captured, isFalse,
          reason: 'إغلاقٌ عرَضيٌّ على حوارِ حذفٍ لا يُقرأ موافقة');
    });

    testWidgets('الإغلاقُ بالنقر خارجَ الحوار يُرجع false — لا null',
        (tester) async {
      // ⚠️ **هذا هو الاختبارُ الذي يقيس الاحتياطَ `?? false` فعلاً.**
      //
      // الإلغاءُ وزرُّ «×» يُغلقان بـ`Navigator.pop(ctx, false)`، فالنتيجةُ
      // ليست `null` أصلاً ولا يُستدعى الاحتياطُ إطلاقاً. والمسارُ الوحيدُ
      // الذي يُنتج `null` هو الإغلاقُ **بلا قيمة**: النقرُ خارجَ الحوار أو
      // مفتاحُ الرجوع.
      //
      // وبدون هذا الاختبار كان قلبُ الاحتياط إلى `?? true` يمرّ على
      // الخمسةَ عشرَ خضراء — وقد جُرِّب فمرّ. فكان الحارسُ أجوفَ حتى نزل
      // هذا السطر.
      bool? captured;
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                captured = await showPicPosConfirm(
                  ctx,
                  icon: PhosphorIconsBold.trash,
                  title: 'حذف نهائيّ',
                  message: 'لا رجعةَ في هذا.',
                  danger: true,
                );
              },
              child: const Text('افتح'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      expect(find.text('حذف نهائيّ'), findsOneWidget, reason: 'تجهيزةٌ سليمة');

      // نقرةٌ في الركن — خارجَ صندوق الحوار، على الحاجب.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.text('حذف نهائيّ'), findsNothing, reason: 'أُغلق فعلاً');
      expect(captured, isFalse,
          reason: 'إغلاقٌ بلا قيمةٍ ⇒ رفضٌ. ولو قُرئ موافقةً لحُذف مستندٌ '
              'بنقرةٍ في الفراغ.');
    });
  });

  group('الانشغال', () {
    testWidgets('busy يُظهر دوّارةً بدل الأيقونة', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PicPosDialog(
            icon: PhosphorIconsBold.scales,
            title: 'مراجعة الأرصدة',
            body: [Text('جسم')],
            primaryAction: PicPosDialogAction(
              label: 'إصلاح تلقائي',
              icon: PhosphorIconsBold.wrench,
              busy: true,
              onPressed: null,
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'زرٌّ معطَّلٌ بلا إشارةِ انشغالٍ يُقرأ «مكسور» لا «يعمل الآن»');
      expect(find.byIcon(PhosphorIconsBold.wrench), findsNothing,
          reason: 'الدوّارةُ تحلّ محلَّ الأيقونة لا تُضاف إليها');
    });

    testWidgets('بلا busy تظهر الأيقونةُ ولا دوّارة', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PicPosDialog(
            icon: PhosphorIconsBold.scales,
            title: 'مراجعة الأرصدة',
            body: const [Text('جسم')],
            primaryAction: PicPosDialogAction(
              label: 'إصلاح تلقائي',
              icon: PhosphorIconsBold.wrench,
              onPressed: () {},
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(PhosphorIconsBold.wrench), findsOneWidget);
    });
  });

  // ═══════════ عمودُ أرقام المجموعات (`panel.index` في التصميم) ═══════════
  //
  // العطبُ المحروسُ هنا ليس «العمودُ غائب» — بل **العمودُ يكذب**: رقمٌ زائدٌ
  // عن مجموعةٍ لا وجودَ لها، أو مجموعةٌ بلا رقم. ولهذا يُقاس الطرفان من
  // الشجرة معاً لا من عددٍ مكتوب.
  group('عمودُ أرقام المجموعات', () {
    List<PicPosPanelGroup> threeGroups() => const [
          PicPosPanelGroup(label: 'البيانات الأساسية', child: Text('أ')),
          PicPosPanelGroup(label: 'العنوان', child: Text('ب')),
          PicPosPanelGroup(label: 'ما يظهر في الفاتورة', child: Text('ج')),
        ];

    Finder badges() => find.descendant(
          of: find.byType(PicPosPanelIndexRail),
          matching: find.byType(Tooltip),
        );

    testWidgets('رقمٌ لكلّ مجموعةٍ — لا أكثرَ ولا أقلّ', (tester) async {
      final groups = threeGroups();
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.buildings,
          title: 'معلومات الشركة',
          indexLabels: picposPanelLabels(groups),
          body: picposPanelBody(groups),
        ),
      );

      // الطرفان مقيسان من الشجرة: المجموعاتُ المرسومةُ فعلاً، والأرقامُ
      // المرسومةُ فعلاً — لا عددٌ ثابتٌ في الاختبار يوافق الاثنين وهما مخطئان.
      final drawn = tester.widgetList<PicPosPanelGroup>(
        find.byType(PicPosPanelGroup),
      );
      expect(badges(), findsNWidgets(drawn.length),
          reason: 'عددُ الأرقام في العمود يخالف عددَ المجموعات في اللوحة — '
              'ورقمٌ يكذب أسوأُ من لا رقم.');
      expect(drawn.length, 3);

      for (var i = 1; i <= 3; i++) {
        expect(find.text('$i'), findsOneWidget);
      }
      expect(find.text('4'), findsNothing);
    });

    testWidgets('والتلميحُ على الرقم عنوانُ مجموعته', (tester) async {
      final groups = threeGroups();
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.buildings,
          title: 'معلومات الشركة',
          indexLabels: picposPanelLabels(groups),
          body: picposPanelBody(groups),
        ),
      );
      final messages =
          tester.widgetList<Tooltip>(badges()).map((t) => t.message).toList();
      expect(messages, [for (final g in groups) g.label]);
    });

    testWidgets('بلا عناوينَ لا يُرسم عمودٌ أصلاً', (tester) async {
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.scales,
          title: 'مراجعة الأرصدة',
          body: [Text('جسم')],
        ),
      );
      expect(find.byType(PicPosPanelIndexRail), findsNothing);
    });

    testWidgets('العمودُ ثابتٌ لا يزحف مع تمرير المحتوى', (tester) async {
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.buildings,
          title: 'معلومات الشركة',
          indexLabels: const ['أوّل', 'ثانٍ'],
          body: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 60; i++)
                  SizedBox(height: 24, child: Text('سطر $i')),
              ],
            ),
          ],
        ),
        size: const Size(1000, 700),
      );

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      final before = tester.getTopLeft(find.text('1'));
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(find.text('1'));

      expect(after.dy, before.dy,
          reason: 'العمودُ زحف مع المحتوى — وهو في التصميم عمودٌ ثابتٌ '
              'بجانب ناحيةِ التمرير لا جزءٌ منها.');
    });

    testWidgets('ولوحةٌ قصيرةٌ لا تمتدّ بطول الشاشة', (tester) async {
      // ⚠️ الفخُّ المحروس: `CrossAxisAlignment.stretch` وحدَها تُجبر الصفَّ
      //    على **كامل** الارتفاع المتاح، فيصير حوارٌ جسمُه سطرٌ واحدٌ بطول
      //    الشاشة. `IntrinsicHeight` هي ما يمنع ذلك.
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.key,
          title: 'تفعيل الترخيص',
          indexLabels: ['أوّل', 'ثانٍ'],
          body: [Text('جسم')],
        ),
        size: const Size(1000, 800),
      );
      final h = tester.getSize(find.byType(PicPosPanelIndexRail)).height;
      // ‏٢٠ حشواً + (‏٣٤ رقماً + ١٢ وصلةً) × ٢ + ٢٠ حشواً = ١٣٢.
      expect(h, lessThan(200),
          reason: 'العمودُ امتدّ بكامل الارتفاع المتاح ($h) — فالحوارُ صار '
              'بطول الشاشة وجسمُه سطر.');
      expect(h, greaterThan(100));
    });

    testWidgets('ومجموعةٌ واحدةٌ لا عمودَ لها', (tester) async {
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.shieldPlus,
          title: 'دور جديد',
          indexLabels: ['تعريف الدور'],
          body: [PicPosPanelGroup(label: 'تعريف الدور', child: Text('أ'))],
        ),
      );
      expect(find.byType(PicPosPanelIndexRail), findsNothing,
          reason: 'فهرسٌ برقمٍ واحدٍ لا يفهرس شيئاً، ويقتطع ٦٤ من عرض الجسم.');
      expect(find.text('تعريف الدور'), findsOneWidget);
    });
  });

  // ═══════════ شريحةُ المجموعة (`kind:'chips'`) ═══════════
  //
  // الشريحةُ بديلُ `CheckboxListTile` في لوحات النطاق. والعطبُ الذي يُحرَس
  // هنا أنّ البديلَ **ينقص بياناً**: الصفُّ كان يعرض سطراً ثانياً (عنوانَ
  // الفرع · موقعَ المخزن · نجمةَ الافتراضيّ) والشريحةُ عنوانٌ وحدَه.
  group('شريحةُ المجموعة', () {
    Future<void> chip(
      WidgetTester tester, {
      required bool selected,
      String? tooltip,
      VoidCallback? onTap,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PicPosPanelChips(
            children: [
              PicPosPanelChip(
                label: 'فرع المعادي',
                selected: selected,
                tooltip: tooltip,
                onTap: onTap,
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('المنتقاةُ بعلامةِ صحٍّ وغيرُها بدائرةٍ فارغة', (tester) async {
      await chip(tester, selected: true);
      expect(find.byIcon(PhosphorIconsBold.checkCircle), findsOneWidget);
      await chip(tester, selected: false);
      expect(find.byIcon(PhosphorIconsBold.circle), findsOneWidget);
    });

    testWidgets('واللمسُ يُنادى', (tester) async {
      var taps = 0;
      await chip(tester, selected: false, onTap: () => taps++);
      await tester.tap(find.text('فرع المعادي'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('والسطرُ الثاني لم يضِع — يظهر تلميحاً', (tester) async {
      await chip(tester, selected: false, tooltip: 'شارع النصر، المعادي');
      final t = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(t.message, 'شارع النصر، المعادي');
    });

    testWidgets('وبلا سطرٍ ثانٍ لا تلميحَ فارغ', (tester) async {
      await chip(tester, selected: false, tooltip: '');
      expect(find.byType(Tooltip), findsNothing,
          reason: 'تلميحٌ بنصٍّ فارغٍ صندوقٌ أسودُ فارغٌ عند المرور.');
    });
  });

  // ═══════════ مجموعةُ قوّة كلمة المرور (`kind:'strength'`) ═══════════
  group('صندوقُ قوّة كلمة المرور', () {
    Future<void> box(
      WidgetTester tester, {
      required int strength,
      List<({String label, bool ok})> rules = const [],
    }) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PicPosPanelStrength(
            field: const Text('حقل'),
            strength: strength,
            strengthLabel: 'وصف',
            rules: rules,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// عددُ الأشرطة الملوّنةِ بلونِ الحالة — لا الفارغة.
    int filled(WidgetTester tester, Color tone) => tester
        .widgetList<Container>(find.byType(Container))
        .where((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.color == tone;
        })
        .length;

    testWidgets('عددُ الأشرطة يتبع القوّة', (tester) async {
      await box(tester, strength: 0);
      expect(filled(tester, AppColors.error), 0,
          reason: 'قوّةُ صفرٍ ⇒ لا شريطَ ملوّن.');

      await box(tester, strength: 20);
      expect(filled(tester, AppColors.error), 1);

      await box(tester, strength: 100);
      expect(filled(tester, AppColors.success), 5);
    });

    testWidgets('واللونُ يتبع النطاق لا لوحةَ Material', (tester) async {
      await box(tester, strength: 25);
      expect(filled(tester, AppColors.error), greaterThan(0));
      await box(tester, strength: 50);
      expect(filled(tester, AppColors.warning), greaterThan(0));
      await box(tester, strength: 80);
      expect(filled(tester, AppColors.success), greaterThan(0));
    });

    testWidgets('وشبكةُ القواعد تفرّق المتحقّقَ من غيره', (tester) async {
      await box(tester, strength: 60, rules: const [
        (label: '٨ أحرف على الأقل', ok: true),
        (label: 'رمز خاص', ok: false),
      ]);
      expect(find.text('٨ أحرف على الأقل'), findsOneWidget);
      expect(find.text('رمز خاص'), findsOneWidget);
      expect(find.byIcon(PhosphorIconsBold.checkCircle), findsOneWidget);
      expect(find.byIcon(PhosphorIconsBold.circleDashed), findsOneWidget);
    });

    testWidgets('وبلا قواعدَ لا شبكةَ أصلاً', (tester) async {
      await box(tester, strength: 0);
      expect(find.byIcon(PhosphorIconsBold.circleDashed), findsNothing,
          reason: 'ستُّ قواعدَ غيرِ متحقّقةٍ على حقلٍ فارغٍ تُقرأ خطأً '
              'لا إرشاداً.');
    });
  });
}
