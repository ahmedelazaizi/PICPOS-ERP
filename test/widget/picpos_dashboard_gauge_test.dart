// اختبار معزول لعناصر PicPos الجديدة فقط (PicPosGauge/PicPosDonut) — لا
// يبني الشاشة الكاملة dashboard_picpos_screen.dart (بتعتمد على providers
// حقيقية DB/riverpod بتعلّق الاختبار). العنصرين دول presentation بحتة:
// يستقبلوا قيمة جاهزة ويرسموها، فهما آمنين للـ pump المباشر.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/dashboard_picpos/widgets/picpos_gauge.dart';
import 'package:ural_erp/presentation/dashboard_picpos/widgets/picpos_donut.dart';

void main() {
  testWidgets('PicPosGauge builds and paints for a value in 0..1', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: PicPosGauge(value: 0.42, label: 'هامش الربح')),
    ));
    expect(find.byType(PicPosGauge), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    await t.pump(const Duration(milliseconds: 300)); // let the animation tick
    await t.pump(const Duration(milliseconds: 700)); // let it settle
    expect(find.text('هامش الربح'), findsOneWidget);
  });

  testWidgets('PicPosGauge clamps out-of-range values without throwing',
      (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PicPosGauge(value: -0.35, label: 'هامش سالب', valueLabel: '-35.0%'),
      ),
    ));
    expect(find.byType(PicPosGauge), findsOneWidget);
    expect(find.text('-35.0%'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('PicPosDonut builds with segments and reacts to tap', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PicPosDonut(segments: [
          PicPosDonutSegment(
              label: 'صافي الإيراد', value: 800, color: Color(0xFF10B981)),
          PicPosDonutSegment(
              label: 'ضريبة المخرجات', value: 120, color: Color(0xFF6366F1)),
        ]),
      ),
    ));
    expect(find.byType(PicPosDonut), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1000)); // let it settle

    await t.tap(find.byType(PicPosDonut));
    await t.pump();
    // لا نتحقق من شريحة بعينها (يعتمد على الإحداثيات الدقيقة) — فقط أن
    // النقر لا يرمي استثناء وأن الودجت لسه موجودة.
    expect(find.byType(PicPosDonut), findsOneWidget);
  });

  testWidgets('PicPosDonut shows placeholder for an empty segment list',
      (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: PicPosDonut(segments: [])),
    ));
    expect(find.byType(PicPosDonut), findsOneWidget);
    expect(find.text('لا بيانات'), findsOneWidget);
  });
}
