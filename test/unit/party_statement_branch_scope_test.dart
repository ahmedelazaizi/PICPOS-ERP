// ═══════════════════════════════════════════════════════════════════════════
// كشف الحساب كان بيعرض كل عملاء وموردي الشركة لمستخدم محصور بفرع.
// ═══════════════════════════════════════════════════════════════════════════
//
// `party_statement_screen.dart:83` كان بينده `watchAllParties()` غير المحصورة —
// مع إن `watchAllPartiesForBranches(allowedBranchIds)` **موجودة فعلاً** ومستعملة
// في `allPartiesProvider`. فالقائمة اللي المستخدم بيختار منها كانت بتعرض
// الأسماء، وأول اختيار بيعرض الرصيد وكل الحركات.
//
// الاختبار ده هو الشرط الموثَّق في خط أساس
// `report_screens_resolve_branch_scope_test` لإزالة الشاشة منه: إثبات سلوكي إن
// `{}` بتفشل **مقفولة**. لأن انقلاب fail-closed لـfail-open هو فئة العطل
// الحقيقية هنا — مش النسيان الكامل، اللي الحارس البنيوي بيمسكه لوحده.
//
// العقد المُختبَر (نفس عقد BranchScope في باقي المنظومة):
//   null  = وصول كامل — بلا حصر
//   {ids} = الفروع دي + الأطراف العامة (is_global)
//   {}    = لا شيء
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branchA;
  late int branchB;

  Future<void> party({
    required String name,
    bool isGlobal = false,
    List<int> branches = const [],
  }) =>
      db.into(db.parties).insert(PartiesCompanion.insert(
            name: name,
            isGlobal: Value(isGlobal),
            branchIds:
                Value(branches.isEmpty ? null : ',${branches.join(',')},'),
          ));

  setUp(() async {
    db = AppDatabase.forTesting();
    branchA = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع أ', globalId: const Value('gid-br-ps-a')));
    branchB = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع ب', globalId: const Value('gid-br-ps-b')));

    await party(name: 'عميل فرع أ', branches: [branchA]);
    await party(name: 'عميل فرع ب', branches: [branchB]);
    await party(name: 'عميل عام', isGlobal: true);
  });

  tearDown(() => db.close());

  // `forTesting()` بيزرع أطراف افتراضية، فالتأكيدات على الأسماء اللي الاختبار
  // ده أنشأها بنفسه — لا على أعداد مطلقة تتغيّر مع أي تعديل في البذر.
  Set<String> mine(List<Party> rows) => rows
      .map((p) => p.name)
      .where((n) => n.startsWith('عميل '))
      .toSet();

  test('null = وصول كامل — كل الأطراف', () async {
    final rows = await db.watchAllPartiesForBranches(null).first;
    expect(mine(rows),
        <String>{'عميل فرع أ', 'عميل فرع ب', 'عميل عام'});
  });

  test('{A} = فرع أ + العام، ومفيش تسريب من فرع ب', () async {
    final rows = await db.watchAllPartiesForBranches({branchA}).first;
    expect(mine(rows), <String>{'عميل فرع أ', 'عميل عام'},
        reason: 'ظهور «عميل فرع ب» معناه تسريب اسم ورصيد طرف من فرع تاني');
  });

  test('{} بتفشل مقفولة — مش «كل الأطراف»', () async {
    // ده الشرط اللي بيسمح بإزالة الشاشة من خط أساس الحارس البنيوي.
    // الانقلاب المعتاد: مستخدم بلا تخصيص بياخد {} فيتفرج على الشركة كلها.
    final rows = await db.watchAllPartiesForBranches(<int>{}).first;
    expect(rows, isEmpty);
  });

  test('{B} ضابط — بيرجّع فرع ب فعلاً مش قايمة فاضية', () async {
    // من غير ده، اختبار «{A} ما فيهاش فرع ب» ممكن يعدّي على بيانات فاضية.
    final rows = await db.watchAllPartiesForBranches({branchB}).first;
    expect(mine(rows), <String>{'عميل فرع ب', 'عميل عام'});
  });
}
