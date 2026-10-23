// المرحلة ١ / §٣-٥ — آلية تنظيف البيانات المتسرّبة كانت مرتدّة دائماً.
//
// `_scopedTables` أعلن أنه يطابق `_syncPullBranchColumn` وفيه ١٠ جداول
// مقابل ٥؛ الخمسة الزائدة بلا عمود `branch_id` في drift. الاستعلام عليها
// يرمي، و`wipeForeignBranchData` يعمل rethrow داخل transaction ⇒ الزر في
// شاشة الإعدادات لم يحذف صفاً قط.

import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/extensions/branch_scope_cleanup_extension.dart';
import 'package:picpos_erp/data/providers/branch_scope_provider.dart';
import 'package:picpos_erp/services/network_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // لقناة SharedPreferences

  late AppDatabase db;
  late int warehouseId;
  late int userId;

  setUp(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    SharedPreferences.setMockInitialValues(const {});
    db = AppDatabase.forTesting();
    // فرعان + مخزن + مستخدم: `SalesInvoices.warehouseId` و`.userId`
    // **مطلوبان وغير nullable** (sales_purchase_tables.dart:181,186)،
    // فبدونهما لا يتصرّف الإدخال أصلاً.
    //
    // ⚠️ `forTesting()` بيشغّل الـ seeding الكامل في `beforeOpen` (فرع
    // افتراضي id=1 + مخزن + مستخدم admin)، فأي إدخال بـid ثابت هنا
    // بيرمي UNIQUE constraint. عشان كده الفرع الثاني بـ`OR IGNORE`
    // والمخزن/المستخدم بنعيد استخدام المزروع بدل ما نصادمه.
    await db.customStatement(
      "INSERT OR IGNORE INTO branches (id, name) VALUES (1,'فرع أ'),(2,'فرع ب')",
    );
    final warehouses = await db.select(db.warehouses).get();
    warehouseId = warehouses.isNotEmpty
        ? warehouses.first.id
        : await db.into(db.warehouses).insert(
              WarehousesCompanion.insert(name: 'مخزن الاختبار')
                  .copyWith(branchId: const d.Value(1)),
            );
    final users = await db.select(db.users).get();
    userId = users.isNotEmpty
        ? users.first.id
        : await db.into(db.users).insert(
              UsersCompanion.insert(
                username: 'u1',
                passwordHash: 'h',
                displayName: 'u1',
              ),
            );
  });

  tearDown(() async => db.close());

  /// فاتورة مبيعات على [branchId] — `sales_invoices` أول مدخل في الخريطة
  /// ولها عمود `branch_id` فعلاً، فهي المسار السليم الذي يثبت أن الحذف
  /// يعمل حين لا يرتدّ.
  ///
  /// ⚠️ الحقول المطلوبة أربعة: `invoiceNumber` · `warehouseId` · `userId` ·
  /// `invoiceDate`. **لا يوجد عمود `totalAmount`** — الاسم `total` وله
  /// قيمة افتراضية، فلا يُمرَّر في `insert`.
  Future<void> seedInvoice(int id, int branchId) async {
    await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'INV-$id',
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: DateTime(2026, 8, 4),
          ).copyWith(id: d.Value(id), branchId: d.Value(branchId)),
        );
  }

  test('wipeForeignBranchData يحذف فعلاً صفوف الفروع الأخرى', () async {
    await seedInvoice(1, 1);
    await seedInvoice(2, 2);

    final deleted = await db.wipeForeignBranchData({1});

    expect(
      deleted['sales_invoices'],
      1,
      reason: 'الترانزاكشن ارتدّت — sales_orders بلا عمود branch_id يرمي '
          'داخلها فيُلغى الحذف كله',
    );

    final remaining = await db.select(db.salesInvoices).get();
    expect(remaining.map((r) => r.id), [1]);
  });

  test('dryRunForeignBranchCounts لا يبلع فشل جدول', () async {
    await seedInvoice(1, 1);
    await seedInvoice(2, 2);

    final counts = await db.dryRunForeignBranchCounts({1});

    expect(counts['sales_invoices'], 1);
    expect(
      counts.keys,
      everyElement(isNot(anyOf(
        'sales_orders',
        'purchase_orders',
        'held_orders',
        'quotations',
        'commercial_papers',
      ))),
      reason: 'جدول بلا عمود branch_id ما زال في القائمة',
    );

    // وفشل جدول لازم يوصل للمستدعي بدل ما يتبلع: العدّ ده بيسبق **حذفاً**
    // بيوافق عليه المستخدم بناءً عليه، فرقم ناقص أخطر من استثناء ظاهر.
    // بنكسر جدول مقصود (إعادة تسمية) عشان نتحقّق إنها بترمي فعلاً.
    await db.customStatement(
      'ALTER TABLE sales_invoices RENAME TO sales_invoices_gone',
    );
    await expectLater(
      db.dryRunForeignBranchCounts({1}),
      throwsA(isA<Exception>()),
      reason: 'الدراي-رن بلع فشل الجدول ورجّع عدّاً ناقصاً',
    );
  });

  // ── المراجعة النهائية / FR-2 ────────────────────────────────────────────
  // الأداة كانت تُبلّغ «لا توجد صفوف» على الجهاز المليء بصفوف فروع أخرى.
  // مدير النظام على جهاز عميل مربوط يكون `isCrossBranchElevated` ⇒
  // `hasFullAccess` ⇒ الواجهة كانت تمرّر `<int>{}` ⇒ الحارس يرجّع `{}`.
  // «الصف الغريب» على جهاز عميل يحدّده **ربط الجهاز** (`client_branch_id`)
  // لا نطاق صلاحية المستخدم — وهذا ما يقيسه هذا الفوج.
  group('FR-2 — نطاق التنظيف على جهاز مربوط', () {
    test('جهاز عميل + صلاحية كاملة ⇒ ربط الجهاز هو الحدّ', () async {
      NetworkService.instance.debugSetModeForTests(NetworkMode.client);
      SharedPreferences.setMockInitialValues({'client_branch_id': 1});
      await seedInvoice(1, 1);
      await seedInvoice(2, 2);

      final allowed =
          await resolveForeignRowScope(const BranchScope.fullAccess());
      expect(allowed, {1});

      final counts = await db.dryRunForeignBranchCounts(allowed);
      expect(
        counts['sales_invoices'],
        1,
        reason: 'الفحص قال «لا توجد صفوف» على جهاز مليء بصفوف الفرع ٢ — '
            'الأداة عديمة الأثر للمشغّل الذي تخاطبه ملاحظات الإصدار',
      );
    });

    test('التنظيف يحذف فعلاً على جهاز عميل بصلاحية كاملة', () async {
      NetworkService.instance.debugSetModeForTests(NetworkMode.client);
      SharedPreferences.setMockInitialValues({'client_branch_id': 1});
      await seedInvoice(1, 1);
      await seedInvoice(2, 2);

      final allowed =
          await resolveForeignRowScope(const BranchScope.fullAccess());
      final deleted = await db.wipeForeignBranchData(allowed);

      expect(deleted['sales_invoices'], 1);
      final remaining = await db.select(db.salesInvoices).get();
      expect(remaining.map((r) => r.id), [1]);
    });

    test('سيرفر/مستقل + صلاحية كاملة ⇒ مجموعة فارغة (الحارس يبقى معنياً)',
        () async {
      NetworkService.instance.debugSetModeForTests(NetworkMode.server);
      SharedPreferences.setMockInitialValues({'client_branch_id': 1});
      await seedInvoice(1, 1);
      await seedInvoice(2, 2);

      final allowed =
          await resolveForeignRowScope(const BranchScope.fullAccess());

      expect(
        allowed,
        isEmpty,
        reason: 'سياق غير محصور فعلاً — لا يوجد «فرع للجهاز» يُقاس عليه، '
            'وحذف صفوف من قاعدة السيرفر الأصلية كارثة',
      );
      expect(await db.dryRunForeignBranchCounts(allowed), isEmpty);
    });

    test('جهاز عميل غير مربوط ⇒ مجموعة فارغة، لا حذف أعمى', () async {
      NetworkService.instance.debugSetModeForTests(NetworkMode.client);
      SharedPreferences.setMockInitialValues(const {}); // بلا client_branch_id
      await seedInvoice(1, 1);
      await seedInvoice(2, 2);

      final allowed =
          await resolveForeignRowScope(const BranchScope.fullAccess());

      expect(allowed, isEmpty);
    });

    test('مستخدم محصور: نطاقه هو الحدّ ولو كان الجهاز مربوطاً بغيره', () async {
      NetworkService.instance.debugSetModeForTests(NetworkMode.client);
      SharedPreferences.setMockInitialValues({'client_branch_id': 1});

      final allowed = await resolveForeignRowScope(
        const BranchScope(allowedBranchIds: {2}, primaryBranchId: 2),
      );

      expect(
        allowed,
        {2},
        reason: 'نطاق المستخدم المحصور لا يُستبدَل بربط الجهاز',
      );
    });
  });
}
