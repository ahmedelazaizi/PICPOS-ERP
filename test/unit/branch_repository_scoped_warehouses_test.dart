// ═══════════════════════════════════════════════════════════════════════════
// getScopedWarehouses — الحصرُ نزل إلى المستودع
// ═══════════════════════════════════════════════════════════════════════════
//
// الحارسُ النصّيُّ (`test/static/invoice_form_scope_parity_test.dart`) يقفل
// **التكافؤ**: أن كلَّ منتقي مخزنٍ يمرّ بهذه الدالّة. وهذا الملفّ يقفل
// **السلوك**: أن الدالّةَ نفسَها تحصر فعلاً.
//
// وضعُ الجهاز (`isClientMode`) يُقرأ من `NetworkService`، ووضعُه في اختبارٍ
// يعني حالةً عامّةً تتسرّب بين الملفّات. فالمقيسُ هنا هو الفرعُ الافتراضيّ —
// جهازٌ غيرُ عميل — وأن `getScopedWarehouses` لا تُنقص صفّاً حينئذ. أمّا قاعدةُ
// الحصر ذاتُها فمقيسةٌ بحالاتها الخمس في
// `test/unit/warehouse_branch_scope_test.dart` بلا حالةٍ عامّةٍ إطلاقاً.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/branch_repository_impl.dart';

void main() {
  late AppDatabase db;
  late BranchRepositoryImpl repo;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = BranchRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  test('جهازٌ غيرُ عميل ⇒ الحصرُ لا يُنقص صفّاً', () async {
    final branchId = await db
        .into(db.branches)
        .insert(BranchesCompanion.insert(name: 'فرعٌ ثانٍ'));
    await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'مخزن الفرع الثاني',
            branchId: Value(branchId),
          ),
        );

    final all = await repo.getWarehouses();
    final scoped = await repo.getScopedWarehouses();

    expect(all.length, greaterThanOrEqualTo(2),
        reason: 'المبذورُ + المزروع — وإلّا فالاختبارُ لا يقيس شيئاً');
    expect(scoped.map((w) => w.id).toList(), all.map((w) => w.id).toList());
  });

  test('الترتيبُ والهُويّاتُ تُنقَل كما هي', () async {
    final scoped = await repo.getScopedWarehouses();
    expect(scoped, isNotEmpty);
    expect(scoped.first.name, isNotEmpty);
  });
}
