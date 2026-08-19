import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/table_status.dart';
import 'package:ural_erp/presentation/tables_picpos/widgets/tables_status_rail.dart';

void main() {
  test('العدُّ يشمل كلَّ حالةٍ ولو كانت صفراً', () {
    final counts = countByStatus([
      TableStatus.available,
      TableStatus.available,
      TableStatus.occupied,
    ]);
    expect(counts[TableStatus.available], 2);
    expect(counts[TableStatus.occupied], 1);
    expect(counts[TableStatus.outOfService], 0,
        reason: 'الصفرُ يُعرَض ولا يُخفى — صورةُ المالك تعرض «غير متاحة ٠»');
    expect(counts.keys.toSet(), TableStatus.all.toSet());
  });

  testWidgets('الضغطُ على حالةٍ يبلّغ باختيارها، وإعادةُ الضغط تُلغيه',
      (tester) async {
    String? picked = 'sentinel';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TablesStatusRail(
            counts: countByStatus([TableStatus.available]),
            selected: null,
            onSelect: (s) => picked = s,
          ),
        ),
      ),
    );
    await tester.tap(find.text('متاحة'));
    expect(picked, TableStatus.available);
  });
}
