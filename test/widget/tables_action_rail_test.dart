// Task 5 — شريطُ الأفعال العموديُّ الدائم لشاشة الطاولات بهويّة PicPos.
//
// ثمانيةُ أزرارٍ بترتيب صورة المالك، كلٌّ منها محروسٌ بصلاحيّةٍ من
// `permissionForAction`، ومعطَّلٌ (لا مختفٍ) إن لم يصلح لحالة الطاولة
// المختارة حسب `actionsForStatus` — نفسُ المصدر الذي يقود القائمة
// المنبثقة، لا نسخةٌ موازية منه.
//
// ── لماذا `ProviderScope` رغم أن القيدَ العامّ يقول «بلا ProviderScope» ──
// القيدُ يمنع فتحَ شاشةٍ كاملةٍ تبني `AppDatabase` حقيقيّةً (فتتعلّق على
// مؤقّت drift عند `db.close()`). لكنّ الودجت هنا تلفّ كلَّ زرٍّ بـ
// `PermissionGuard`، وهو `ConsumerWidget` يقرأ
// `ref.watch(currentUserPermissionsProvider)` — فبلا أيّ `ProviderScope`
// إطلاقاً يسقط الاختبارُ بخطأ "No ProviderScope found"، لا بنتيجةٍ صحيحة.
// الحلُّ المتّبَعُ فعلاً في هذا المستودع (انظر
// `test/widget/task_6b_tables_manage_permission_gate_test.dart`) هو تغليفٌ
// بـ`ProviderScope` مع **override** لـ`currentUserPermissionsProvider` نفسِه
// — فلا `AppDatabase` تُبنى إطلاقاً، ولا مؤقّتَ drift يظهر. هذا فرقٌ بين
// الموجزِ والواقع، والواقعُ هو الحَكَم.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/models/table_actions.dart';
import 'package:ural_erp/domain/models/table_status.dart';
import 'package:ural_erp/presentation/screens/tables/widgets/table_actions_menu.dart';
import 'package:ural_erp/presentation/tables_picpos/widgets/tables_action_rail.dart';

/// كلُّ الأكواد التي تحرس أفعال الشريط الثمانية — منح كاملٍ يجعل
/// `PermissionGuard` يمرّر الابنَ كما هو، فالتعطيلُ الظاهرُ في اختبارات
/// الحالة يرجع فعلاً لـ`actionsForStatus` لا لغياب صلاحيّة.
const _allRailPermissions = [
  PermissionCodes.tablesManage,
  PermissionCodes.tablesTransfer,
  PermissionCodes.tablesMerge,
  PermissionCodes.tablesSplitBill,
  PermissionCodes.tablesPrintBill,
  PermissionCodes.tablesReserve,
];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<String> perms = _allRailPermissions,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserPermissionsProvider.overrideWith((ref) async => perms),
      ],
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
  // مرّتان: مرّةٌ لبدء الـ FutureProvider ومرّةٌ لاستهلاك نتيجته — نفسُ
  // النمط المتّبَع في `task_6b_tables_manage_permission_gate_test.dart`.
  await tester.pump();
  await tester.pump();
}

void main() {
  test('الشريطُ ثمانيةُ أفعالٍ بترتيب صورة المالك', () {
    expect(railActions, const [
      TableAction.open,
      TableAction.transfer,
      TableAction.merge,
      TableAction.splitBill,
      TableAction.printBill,
      TableAction.changeStatus,
      TableAction.reserve,
      TableAction.closeTable,
    ]);
  });

  test('كلُّ فعلٍ في الشريط محروسٌ بصلاحيّة', () {
    for (final a in railActions) {
      expect(permissionForAction(a), isNotNull, reason: '$a');
    }
  });

  testWidgets('الأزرارُ الثمانيةُ تظهر دائماً، وغيرُ الصالح لحالةٍ معطَّل',
      (tester) async {
    await _pump(
      tester,
      TablesActionRail(
        tableStatus: TableStatus.available,
        onAction: (_) {},
      ),
    );

    // ثمانيةٌ معروضةٌ دائماً — الصورةُ تعرضها كلَّها، ما صلح للحالة وما لم
    // يصلح.
    for (final a in railActions) {
      expect(find.text(tableActionLabels[a]!), findsOneWidget, reason: '$a');
    }

    final allowed = actionsForStatus(TableStatus.available);
    expect(allowed, isNot(contains(TableAction.splitBill)));

    // الصالحُ للحالة المتاحة (`open` مثلاً) قابلٌ للضغط فعلاً.
    final openButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text(tableActionLabels[TableAction.open]!),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(openButton.onPressed, isNotNull);

    // وغيرُ الصالح (`splitBill` لا يصلح لطاولةٍ متاحة) معطَّلٌ فعلاً —
    // لا مجرّد نصٍّ ظاهر.
    final splitButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text(tableActionLabels[TableAction.splitBill]!),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(splitButton.onPressed, isNull);
  });

  testWidgets('بلا طاولةٍ مختارة، كلُّ الأزرار معطَّلة', (tester) async {
    var fired = false;
    await _pump(
      tester,
      TablesActionRail(
        tableStatus: null,
        onAction: (_) => fired = true,
      ),
    );

    await tester.tap(find.text(tableActionLabels[TableAction.open]!),
        warnIfMissed: false);
    await tester.pump();
    expect(fired, isFalse, reason: 'فعلٌ بلا طاولةٍ لا معنى له');

    // وكلُّ الأزرار الثمانية تبقى ظاهرةً حتى بلا طاولةٍ مختارة.
    for (final a in railActions) {
      expect(find.text(tableActionLabels[a]!), findsOneWidget, reason: '$a');
    }
  });

  testWidgets('الضغطُ على فعلٍ صالحٍ للحالة يُبلّغ onAction بالفعل الصحيح',
      (tester) async {
    final tapped = <TableAction>[];
    await _pump(
      tester,
      TablesActionRail(
        tableStatus: TableStatus.occupied,
        onAction: tapped.add,
      ),
    );

    // `transfer` يصلح لـ occupied.
    await tester.tap(find.text(tableActionLabels[TableAction.transfer]!));
    await tester.pump();
    expect(tapped, [TableAction.transfer]);

    // `reserve` لا يصلح لـ occupied — الضغطُ لا يُبلّغ شيئاً.
    await tester.tap(find.text(tableActionLabels[TableAction.reserve]!),
        warnIfMissed: false);
    await tester.pump();
    expect(tapped, [TableAction.transfer]);
  });

  testWidgets(
      'صلاحيّةٌ غائبة تُعطِّل الزرَّ حتى لو صلح الفعلُ لحالة الطاولة',
      (tester) async {
    // منحٌ كاملٌ ما عدا tablesTransfer — والحالةُ occupied تُصلح transfer
    // حسب actionsForStatus. فلو مرّ التعطيلُ فقط عبر الحالة (بلا حراسة
    // صلاحيّةٍ فعليّة) لظلّ الزرُّ قابلاً للضغط خطأً.
    final permsWithoutTransfer = _allRailPermissions
        .where((p) => p != PermissionCodes.tablesTransfer)
        .toList();
    expect(actionsForStatus(TableStatus.occupied),
        contains(TableAction.transfer));

    var fired = false;
    await _pump(
      tester,
      TablesActionRail(
        tableStatus: TableStatus.occupied,
        onAction: (_) => fired = true,
      ),
      perms: permsWithoutTransfer,
    );

    // الزرُّ يبقى ظاهراً بنصّه (`showDisabled` لا يُخفي) — لكنّ الدليلَ
    // الحقيقيَّ على التعطيل هو الأثر لا الإعداد. لا نتحقّق من
    // `guard.showDisabled == true` (خصيصةُ تهيئةٍ لا تُثبت شيئاً عن
    // السلوك الفعليّ) ولا من `onPressed == null` على الـ OutlinedButton
    // الداخليّ مباشرةً — جرّبتُ الثانية أوّلاً فسقط الاختبار: الابنُ
    // الممرَّر لِـ`PermissionGuard` هنا هو `_RailButton` (ودجتٌ مركَّبةٌ)
    // لا `OutlinedButton` خامٌ، و`_buildDisabledChild()` يتعرّف فقط على
    // أنواع الأزرار الخام فيُصفِّر `onPressed` لها؛ لأيّ ودجتٍ آخر يسلك
    // المسارَ العامّ `IgnorePointer(Opacity(...))` — فالـ`OutlinedButton`
    // الداخليُّ يبقى `onPressed` غيرَ فارغٍ (محسوبٌ من الحالة وحدَها عبر
    // `_RailButton.enabled`)، والتعطيلُ الفعليُّ يقع عبر `IgnorePointer`
    // الذي يمتصّ اللمسةَ قبل أن تصل. فتحقّقُ `onPressed` هنا يثبت شيئاً
    // خاطئاً عن هذه البنية بالذات.
    //
    // الدليلُ الصحيحُ إذن: نقرةٌ فعليّةٌ ثم التأكّدُ أن الفعلَ لم يُبلَّغ —
    // نفسُ نمط الاختبار الثالث في هذا الملفّ لسيناريو الحالة، هنا لسيناريو
    // الصلاحيّة.
    expect(find.text(tableActionLabels[TableAction.transfer]!),
        findsOneWidget);
    await tester.tap(find.text(tableActionLabels[TableAction.transfer]!),
        warnIfMissed: false);
    await tester.pump();
    expect(fired, isFalse,
        reason: 'صلاحيّةٌ غائبةٌ يجب أن تمنع تنفيذ الفعل فعلاً');
  });
}
