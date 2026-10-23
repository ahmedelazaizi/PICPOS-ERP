// جدولُ سجل العمليات على التصميم.
//
// ما يُقاس:
//  ‏١) الخلايا الستُّ تعرض ما أُعطيت، والسطرُ الفرعيُّ **يختفي** حين يغيب
//     مصدرُه بدل أن يترك فراغاً يوحي بقيمةٍ محذوفة.
//  ‏٢) النقرُ يُبلِّغ **بالصفِّ المنقور بمعرّفه** لا بفهرسه.
//  ‏٣) لا فيضانَ عند الضيق ولا مع نصوصٍ طويلة.
//  ‏٤) الفراغُ يعرض حالتَه.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/domain/models/picpos_activity_view.dart';
import 'package:picpos_erp/presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart';

PicPosActivityRow _row({
  int id = 1,
  String actionLabel = 'بيع',
  String entityLabel = 'فاتورة',
  String detail = 'فاتورة نقدية',
  String userName = 'أحمد',
  DateTime? time,
  String? branchName,
  String? roleName,
  int? entityId,
  double? amount,
}) =>
    PicPosActivityRow(
      id: id,
      actionLabel: actionLabel,
      entityLabel: entityLabel,
      detail: detail,
      userName: userName,
      time: time ?? DateTime(2026, 8, 21, 14, 5),
      branchName: branchName,
      roleName: roleName,
      entityId: entityId,
      amount: amount,
    );

({IconData icon, Color color}) _visual(PicPosActivityRow _) =>
    (icon: PhosphorIconsBold.shoppingCart, color: AppColors.success);

void main() {
  Future<void> show(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('PicPosActivityTable — العرض', () {
    testWidgets('يعرض الرأسَ بأعمدته الستّة', (tester) async {
      await show(
        tester,
        PicPosActivityTable(
          rows: [_row()],
          visualFor: _visual,
          onRowTap: (_) {},
        ),
      );
      expect(find.text('الإجراء'), findsOneWidget);
      expect(find.text('المستند / النوع'), findsOneWidget);
      expect(find.text('التفاصيل'), findsOneWidget);
      expect(find.text('المستخدم'), findsOneWidget);
      expect(find.text('الوقت'), findsOneWidget);
    });

    testWidgets('يعرض خلايا الصفّ كلَّها', (tester) async {
      await show(
        tester,
        PicPosActivityTable(
          rows: [
            _row(
              actionLabel: 'بيع',
              branchName: 'فرع العقبة',
              entityLabel: 'فاتورة',
              entityId: 842,
              detail: 'فاتورة نقدية',
              userName: 'أحمد',
              roleName: 'كاشير',
            ),
          ],
          visualFor: _visual,
          onRowTap: (_) {},
        ),
      );
      expect(find.text('بيع'), findsOneWidget);
      expect(find.text('فرع العقبة'), findsOneWidget);
      expect(find.text('فاتورة'), findsOneWidget);
      expect(find.text('#842'), findsOneWidget);
      expect(find.text('فاتورة نقدية'), findsOneWidget);
      expect(find.text('أحمد'), findsOneWidget);
      expect(find.text('كاشير'), findsOneWidget);
      expect(find.text('14:05'), findsOneWidget);
      expect(find.text('21/8'), findsOneWidget);
    });

    // ⚠️ لا يُرسم سطرٌ فارغٌ ولا «غير معروف»: السجلّاتُ الأقدمُ من v138 بلا
    // فرعٍ مختوم، والمستخدمُ قد يكون بلا دور.
    testWidgets('السطرُ الفرعيُّ يختفي حين يغيب مصدرُه', (tester) async {
      await show(
        tester,
        PicPosActivityTable(
          rows: [_row(entityId: null)],
          visualFor: _visual,
          onRowTap: (_) {},
        ),
      );
      expect(find.text('غير معروف'), findsNothing);
      expect(find.textContaining('#null'), findsNothing);
    });

    testWidgets('المبلغُ يظهر مع الوصف في خليّة التفاصيل', (tester) async {
      await show(
        tester,
        PicPosActivityTable(
          rows: [_row(detail: 'خصم يدوي', amount: 25)],
          visualFor: _visual,
          onRowTap: (_) {},
        ),
      );
      expect(find.textContaining('خصم يدوي'), findsOneWidget);
      expect(find.textContaining('25.000'), findsOneWidget);
    });

    testWidgets('قائمةٌ فارغةٌ تعرض حالةَ الفراغ', (tester) async {
      await show(
        tester,
        PicPosActivityTable(
          rows: const [],
          visualFor: _visual,
          onRowTap: (_) {},
        ),
      );
      expect(find.text('لا توجد عمليات مسجلة'), findsOneWidget);
    });

    testWidgets('يعرض صفّاً لكلّ سجلّ', (tester) async {
      await show(
        tester,
        PicPosActivityTable(
          rows: [for (var i = 1; i <= 5; i++) _row(id: i, detail: 'سطر $i')],
          visualFor: _visual,
          onRowTap: (_) {},
        ),
      );
      expect(find.byType(PicPosActivityTableRow), findsNWidgets(5));
    });
  });

  group('PicPosActivityTable — التفاعل', () {
    // فهرسٌ بدل معرّفٍ كان سيفتح تفاصيلَ سجلٍّ غيرِ الذي نُقر متى رُشِّحت
    // القائمة — وهو عطبٌ صامت.
    testWidgets('النقرُ يُبلِّغ بالصفِّ المنقور لا بغيره', (tester) async {
      PicPosActivityRow? tapped;
      await show(
        tester,
        PicPosActivityTable(
          rows: [
            _row(id: 11, detail: 'أوّل'),
            _row(id: 22, detail: 'ثانٍ'),
            _row(id: 33, detail: 'ثالث'),
          ],
          visualFor: _visual,
          onRowTap: (r) => tapped = r,
        ),
      );
      await tester.tap(find.text('ثانٍ'));
      await tester.pumpAndSettle();
      expect(tapped?.id, 22);
    });
  });

  group('لا فيضانَ تخطيط', () {
    testWidgets('نصوصٌ طويلةٌ على عرضٍ كاملٍ لا تفيض', (tester) async {
      await show(
        tester,
        PicPosActivityTable(
          rows: [
            _row(
              actionLabel: 'تعديل صلاحيات دورٍ إداريٍّ كامل',
              branchName: 'فرع العقبة — المنطقة الحرّة — المستودع الرئيسي',
              entityLabel: 'قالب فاتورة حرارية مخصّص',
              entityId: 999999999,
              detail: 'تغيير قيمة الخصم من 5% إلى 15% على كامل الفاتورة '
                  'مع إعادة احتساب الضريبة والإجمالي',
              userName: 'عبد الرحمن محمد أحمد سولا',
              roleName: 'مدير النظام والصلاحيات',
              amount: 9876543.21,
            ),
          ],
          visualFor: _visual,
          onRowTap: (_) {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('عرضٌ ضيّقٌ (لوحُ كاشير) لا يفيض', (tester) async {
      await show(
        tester,
        PicPosActivityTable(
          rows: [
            for (var i = 1; i <= 3; i++)
              _row(
                id: i,
                actionLabel: 'تعديل صلاحيات',
                branchName: 'فرع العقبة',
                entityId: 999999,
                detail: 'تفاصيل طويلة جدّاً تتجاوز عرضَ العمود بكثير',
                userName: 'عبد الرحمن سولا',
                roleName: 'مدير النظام',
                amount: 9876543.21,
              ),
          ],
          visualFor: _visual,
          onRowTap: (_) {},
        ),
        size: const Size(760, 700),
      );
      expect(tester.takeException(), isNull,
          reason: 'الخلايا تقصُّ بالحذف لا تفيض بالشريط الأصفر');
    });
  });
}
