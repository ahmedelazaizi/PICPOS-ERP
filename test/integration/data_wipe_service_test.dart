// ═══════════════════════════════════════════════════════════════════════════
// أدوات تصفير البيانات — التحقق من الحُرّاس والعدّادات والتراجع
// ═══════════════════════════════════════════════════════════════════════════
//
// `DataWipeService` عمليات **بلا رجعة** على قاعدة البيانات، فالتحقق منها على
// قاعدة حقيقية مكلّف ومخيف. الاختبارات دي بتغطي المنطق كله على قاعدة في
// الذاكرة: الحُرّاس بترفض فعلاً، والرفض **مبيحذفش ولا صف**، والعدّادات بترجع
// الأرقام الصح، والتصفير الكامل بيسيب التركيب شغّال.
//
// ── ليه فيه PathProvider وهمي ─────────────────────────────────────────────
// كل عملية بتاخد نسخة احتياطية إجبارية قبل أول حذف، و`createDatabaseBackup`
// بيقرا `getApplicationDocumentsDirectory()`. على ويندوز التنفيذ ده Dart خالص
// (win32) مش method channel، فمينفعش يتعمله mock بـ `setMockMethodCallHandler`
// — لازم استبدال `PathProviderPlatform.instance` نفسه.
//
// وde بيدّي فايدة تانية: الاختبار بيقدر **يفشّل النسخة الاحتياطية عمداً**
// (بمجلد مالوش ملف داتابيز) ويتأكد إن الحذف اتلغى — وهي الحماية التالتة من
// الأربعة، وهي اللي صعب التأكد منها بأي طريقة تانية.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:ural_erp/data/database/connection_io.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';
import 'package:ural_erp/data/database/wal_checkpoint.dart';
import 'package:ural_erp/services/admin/data_wipe_service.dart';

/// PathProvider وهمي بيوجّه مجلد المستندات لمجلد مؤقت يتحكم فيه الاختبار.
///
/// `extends` مش `implements`: الـ setter بتاع `PathProviderPlatform.instance`
/// بيتحقق من توكن المنصّة، والوراثة بتمرّره — فمفيش داعي لـ
/// `MockPlatformInterfaceMixin` ولا لاعتماد `plugin_platform_interface`.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.docsPath);

  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

/// أقل فيك ممكن لقلب `SyncInterceptor.isClientMode` — نفس نمط
/// `je_deterministic_balancing_test`.
class _ClientModeInterceptor implements SyncInterceptor {
  @override
  bool get isClientModeImpl => true;
  @override
  bool get isMirrorModeImpl => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DataWipeService svc;
  late Directory docsDir;
  // مع تشغيل قيود الـ FK، أي صف بيشاور على مستودع أو مستخدم لازم يشاور على
  // واحد **موجود فعلاً** — مينفعش نكتب 1 ونمشي.
  late int whId;
  late int userId;

  /// بيحطّ ملف داتابيز صوري في مجلد المستندات الوهمي عشان
  /// `createDatabaseBackup` يلاقي حاجة ينسخها (بيرجع null لو الملف مش موجود).
  void plantDatabaseFile() {
    File('${docsDir.path}${Platform.pathSeparator}${getDatabaseFileName()}')
        .writeAsStringSync('fake sqlite payload');
  }

  setUp(() async {
    docsDir = Directory.systemTemp.createTempSync('picpos_wipe_test_');
    PathProviderPlatform.instance = _FakePathProvider(docsDir.path);
    plantDatabaseFile();

    db = AppDatabase.forTesting();

    // ⚠️ `AppDatabase.forTesting()` بيسيب `PRAGMA foreign_keys` **مطفي**،
    // والتطبيق الحقيقي بيشغّله (`connection_io.openConnection`). الفرق ده
    // خلّى فئة كاملة من الباجات غير مرئية للاختبارات: الحذف كان بينجح هنا
    // ويفشل عند العميل بـ `SqliteException(787): FOREIGN KEY constraint
    // failed`. الملف ده بيشغّله عشان يختبر تحت نفس قيود الإنتاج.
    await db.customStatement('PRAGMA foreign_keys = ON');

    whId = (await db.customSelect('SELECT id FROM warehouses LIMIT 1')
            .getSingle())
        .data['id'] as int;
    userId =
        (await db.customSelect('SELECT id FROM users LIMIT 1').getSingle())
            .data['id'] as int;

    svc = DataWipeService(db);
  });

  tearDown(() async {
    await db.close();
    SyncInterceptor.instance = null;
    if (docsDir.existsSync()) docsDir.deleteSync(recursive: true);
  });

  // ── مساعدات الزرع ────────────────────────────────────────────────────────

  var codeSeq = 0;

  Future<int> seedProduct(String name) => db.into(db.products).insert(
        ProductsCompanion.insert(code: 'P${++codeSeq}', name: name),
      );

  Future<int> seedParty(
    String name, {
    bool customer = false,
    bool supplier = false,
  }) =>
      db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: name,
              isCustomer: Value(customer),
              isSupplier: Value(supplier),
            ),
          );

  Future<int> seedAccount(String code, String name) =>
      db.into(db.accounts).insert(
            AccountsCompanion.insert(
              code: code,
              name: name,
              accountType: 'asset',
            ),
          );

  Future<int> seedSalesInvoice(String number, {double total = 100}) =>
      db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: number,
              warehouseId: whId,
              userId: userId,
              invoiceDate: DateTime(2026, 7, 27),
              total: Value(total),
            ),
          );

  Future<int> seedPurchaseInvoice(String number, {double total = 50}) async =>
      db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: number,
              supplierId: await seedParty('مورد الفاتورة', supplier: true),
              warehouseId: whId,
              invoiceDate: DateTime(2026, 7, 27),
              total: Value(total),
            ),
          );

  Future<int> seedJournalEntry(String number) =>
      db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              entryNumber: number,
              entryDate: DateTime(2026, 7, 27),
              description: const Value('قيد اختبار'),
            ),
          );

  Future<int> countOf(String table) async {
    final r =
        await db.customSelect('SELECT COUNT(*) c FROM $table').getSingle();
    return r.data['c'] as int;
  }

  /// `AppDatabase.forTesting()` بيزرع دليل حسابات كامل وأطراف افتراضية، فأي
  /// تأكيد بعدد مطلق بيبقى غلط. التأكيدات هنا نسبية للأساس ده.
  Future<Map<String, int>> baselineOf(List<String> tables) async {
    final m = <String, int>{};
    for (final t in tables) {
      m[t] = await countOf(t);
    }
    return m;
  }

  Future<void> expectUnchanged(Map<String, int> baseline) async {
    for (final e in baseline.entries) {
      expect(await countOf(e.key), e.value,
          reason: 'جدول ${e.key} اتغيّر رغم إن العملية اترفضت');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ١) الحُرّاس بترفض — والرفض مبيحذفش ولا صف
  // ═══════════════════════════════════════════════════════════════════════

  group('الحُرّاس', () {
    test('حذف الأصناف يُرفض لما يكون فيه بنود فواتير مبيعات', () async {
      final pid = await seedProduct('صنف مرتبط');
      final invId = await seedSalesInvoice('S-G1');
      await db.into(db.salesInvoiceItems).insert(
            SalesInvoiceItemsCompanion.insert(
              invoiceId: invId,
              productId: pid,
              quantity: 1,
              unitPrice: 10,
              total: 10,
            ),
          );

      final res = await svc.wipeProducts();

      expect(res.ok, isFalse);
      expect(res.error, contains('بند فاتورة'));
      // الأهم: الرفض حصل **قبل** أي حذف.
      expect(await countOf('products'), 1);
      expect(await countOf('sales_invoice_items'), 1);
    });

    test('حذف الأصناف يُرفض لما يكون فيه بنود فواتير مشتريات', () async {
      final pid = await seedProduct('صنف مشتريات');
      final invId = await seedPurchaseInvoice('P-G1');
      await db.into(db.purchaseInvoiceItems).insert(
            PurchaseInvoiceItemsCompanion.insert(
              invoiceId: invId,
              productId: pid,
              quantity: 1,
              unitCost: 5,
              total: 5,
            ),
          );

      final res = await svc.wipeProducts();

      expect(res.ok, isFalse);
      expect(await countOf('products'), 1);
    });

    test('حذف العملاء يُرفض لما يكون فيه فواتير مبيعات', () async {
      await seedParty('عميل', customer: true);
      await seedSalesInvoice('S-1');
      final before = await baselineOf(['parties', 'sales_invoices']);

      final res = await svc.wipeParties(customers: true);

      expect(res.ok, isFalse);
      expect(res.error, contains('العملاء'));
      await expectUnchanged(before);
    });

    test('حذف الموردين يُرفض لما يكون فيه فواتير مشتريات', () async {
      await seedParty('مورد', supplier: true);
      await seedPurchaseInvoice('P-1');
      final before = await baselineOf(['parties', 'purchase_invoices']);

      final res = await svc.wipeParties(customers: false);

      expect(res.ok, isFalse);
      expect(res.error, contains('الموردين'));
      await expectUnchanged(before);
    });

    test('حذف الحسابات يُرفض لما يكون فيه بنود يومية', () async {
      final aid = await seedAccount('1010', 'الصندوق');
      final jeId = await seedJournalEntry('JE-1');
      await db.into(db.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
              entryId: jeId,
              accountId: aid,
              debit: const Value(100),
              credit: const Value(0),
            ),
          );

      final before =
          await baselineOf(['accounts', 'journal_entry_lines', 'journal_entries']);

      final res = await svc.wipeChartOfAccounts();

      expect(res.ok, isFalse);
      expect(res.error, contains('بند يومية'));
      await expectUnchanged(before);
    });

    test('وضع العميل يرفض العمليات السبعة كلها', () async {
      SyncInterceptor.instance = _ClientModeInterceptor();
      await seedProduct('صنف');
      await seedParty('طرف', customer: true, supplier: true);
      await seedAccount('1020', 'البنك');
      final before = await baselineOf(['products', 'parties', 'accounts']);

      final results = <WipeResult>[
        await svc.wipeSalesInvoices(),
        await svc.wipePurchaseInvoices(),
        await svc.wipeProducts(),
        await svc.wipeParties(customers: true),
        await svc.wipeParties(customers: false),
        await svc.wipeChartOfAccounts(),
        await svc.wipeAllTransactionalData(),
      ];

      for (final r in results) {
        expect(r.ok, isFalse);
        expect(r.error, contains('وضع العميل'));
      }
      // ولا صف اتلمس.
      await expectUnchanged(before);
    });

    test('فشل النسخة الاحتياطية يلغي العملية ومبيحذفش حاجة', () async {
      // من غير ملف داتابيز في مجلد المستندات، `createDatabaseBackup` بيرجع
      // null — وهي الحالة اللي المفروض توقف الحذف.
      File('${docsDir.path}${Platform.pathSeparator}${getDatabaseFileName()}')
          .deleteSync();
      await seedProduct('صنف محمي');

      final res = await svc.wipeProducts();

      expect(res.ok, isFalse);
      expect(res.error, contains('نسخة احتياطية'));
      expect(await countOf('products'), 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ٢) المسارات الناجحة — الحذف بيوصل للأبناء والعدّاد صح
  // ═══════════════════════════════════════════════════════════════════════

  group('المسارات الناجحة', () {
    test('حذف فواتير المبيعات بيشيل القيود وحركات المخزون معاها', () async {
      final pid = await seedProduct('صنف');
      final invId = await seedSalesInvoice('S-9', total: 200);
      await db.into(db.salesInvoiceItems).insert(
            SalesInvoiceItemsCompanion.insert(
              invoiceId: invId,
              productId: pid,
              quantity: 2,
              unitPrice: 100,
              total: 200,
            ),
          );
      final jeId = await seedJournalEntry('JE-9');
      final aid = await seedAccount('4010', 'المبيعات');
      await db.into(db.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
              entryId: jeId,
              accountId: aid,
              debit: const Value(0),
              credit: const Value(200),
            ),
          );
      await db.into(db.stockMovements).insert(
            StockMovementsCompanion.insert(
              productId: pid,
              warehouseId: whId,
              movementType: 'sale',
              quantity: -2,
              balanceAfter: 0,
            ),
          );

      final res = await svc.wipeSalesInvoices();

      expect(res.ok, isTrue, reason: res.error);
      expect(await countOf('sales_invoices'), 0);
      expect(await countOf('sales_invoice_items'), 0);
      expect(await countOf('journal_entries'), 0);
      expect(await countOf('journal_entry_lines'), 0);
      expect(await countOf('stock_movements'), 0);
      // الصنف نفسه مش من شغل العملية دي.
      expect(await countOf('products'), 1);

      // العدّاد لكل جدول هو اللي الواجهة بتعرضه — لازم يطابق الواقع.
      expect(res.deleted['الفواتير'], 1);
      expect(res.deleted['بنود الفواتير'], 1);
      expect(res.deleted['قيود اليومية'], 1);
      expect(res.deleted['بنود اليومية'], 1);
      expect(res.deleted['حركات المخزون'], 1);
      expect(res.backupPath, isNotNull);
      expect(File(res.backupPath!).existsSync(), isTrue);
    });

    test('حذف الأصناف بيوصل للباركودات والوحدات والأرصدة', () async {
      final pid = await seedProduct('صنف بأبناء');
      await db.into(db.productBarcodes).insert(
            ProductBarcodesCompanion.insert(productId: pid, barcode: '123456'),
          );
      await db.into(db.inventoryBalances).insert(
            InventoryBalancesCompanion.insert(
              productId: pid,
              warehouseId: whId,
              quantity: const Value(5),
            ),
          );

      final res = await svc.wipeProducts();

      expect(res.ok, isTrue, reason: res.error);
      expect(await countOf('products'), 0);
      expect(await countOf('product_barcodes'), 0);
      expect(await countOf('inventory_balances'), 0);
      expect(res.deleted['الأصناف'], 1);
      expect(res.deleted['باركودات الأصناف'], 1);
      expect(res.deleted['أرصدة المخزون'], 1);
    });

    test('الطرف المزدوج تُلغى صفته ولا يُحذف', () async {
      final both = await seedParty('طرف مزدوج', customer: true, supplier: true);
      await seedParty('عميل خالص', customer: true);
      await seedParty('مورد خالص', supplier: true);

      final res = await svc.wipeParties(customers: true);

      expect(res.ok, isTrue, reason: res.error);
      // المزدوج لسه موجود، بس بقى مورد بس.
      final survivor = await (db.select(db.parties)
            ..where((p) => p.id.equals(both)))
          .getSingle();
      expect(survivor.isCustomer, isFalse);
      expect(survivor.isSupplier, isTrue);

      // العميل الخالص اتحذف، والمورد الخالص ما اتلمسش.
      final rest = await db.select(db.parties).get();
      expect(rest.map((p) => p.name), containsAll(['طرف مزدوج', 'مورد خالص']));
      expect(rest.map((p) => p.name), isNot(contains('عميل خالص')));

      // العدد المطلق بيختلف حسب الأطراف الافتراضية المزروعة، فالمهم إن
      // العمليتين حصلوا: إلغاء صفة + حذف.
      expect(res.deleted['أطراف مزدوجة (أُلغيت الصفة فقط)'], greaterThan(0));
      expect(res.deleted['العملاء'], greaterThan(0));
    });

    test('التصفير الكامل بيسيب المستخدمين والفروع والمستودعات والإعدادات',
        () async {
      final roleId = await db.into(db.roles).insert(
            RolesCompanion.insert(name: 'مدير', isSystemRole: const Value(true)),
          );
      await db.createUser(
        username: 'admin_test',
        password: 'pass1234',
        displayName: 'مدير الاختبار',
        roleId: roleId,
      );
      await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(name: 'المستودع الرئيسي'),
          );
      await seedProduct('صنف للتصفير');
      await seedParty('طرف للتصفير', customer: true);
      await seedSalesInvoice('S-Z', total: 1);

      final usersBefore = await countOf('users');
      final warehousesBefore = await countOf('warehouses');
      final rolesBefore = await countOf('roles');

      final res = await svc.wipeAllTransactionalData();

      expect(res.ok, isTrue, reason: res.error);
      // البيانات الحركية راحت.
      expect(await countOf('sales_invoices'), 0);
      expect(await countOf('products'), 0);
      expect(await countOf('parties'), 0);
      // والتركيب فضل شغّال — تركيب بلا مستخدمين مش «مصفّر»، ده مكسور.
      expect(await countOf('users'), usersBefore);
      expect(await countOf('warehouses'), warehousesBefore);
      expect(await countOf('roles'), rolesBefore);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ٣) قيود المفاتيح الأجنبية — الباج اللي ضرب على أول قاعدة حقيقية
  // ═══════════════════════════════════════════════════════════════════════
  //
  // النسخة الأولى كانت بتعدّد جداول الأبناء بالإيد، فأول فاتورة مبيعات
  // حقيقية طلّعت:
  //
  //   SqliteException(787): FOREIGN KEY constraint failed
  //   Causing statement: DELETE FROM "sales_invoices"
  //
  // الاختبارات دي بتزرع صف في **كل** جدول تابع بيقدر يوقّع الحذف، وبتتأكد
  // إن العملية بتخلص. ولإن التنظيف مولَّد من `PRAGMA foreign_key_list`، أي
  // جدول جديد في السكيما بيتغطّى من غير تعديل هنا.

  group('قيود المفاتيح الأجنبية', () {
    /// كل الأعمدة اللي بتشاور على [target] — نفس استعلام الخدمة.
    Future<List<({String table, String column, bool nullable})>> dependentsOf(
      String target,
    ) async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();

      final out = <({String table, String column, bool nullable})>[];
      for (final row in tables) {
        final name = row.data['name'] as String;
        if (name == target) continue;
        final fks =
            await db.customSelect('PRAGMA foreign_key_list("$name")').get();
        for (final fk in fks) {
          if (fk.data['table'] != target) continue;
          final column = fk.data['from'] as String;
          final cols =
              await db.customSelect('PRAGMA table_info("$name")').get();
          final col = cols.where((c) => c.data['name'] == column).firstOrNull;
          out.add((
            table: name,
            column: column,
            nullable: (col?.data['notnull'] as int? ?? 0) == 0,
          ));
        }
      }
      return out;
    }

    test('السكيما فعلاً فيها تبعيات على كل هدف — الاختبار مش فاضي', () async {
      // لو ده فشل يبقى الاستعلام اتكسر، والاختبارات اللي تحت بتعدّي
      // على الفاضي وهي مش بتختبر حاجة.
      for (final target in [
        'sales_invoices',
        'purchase_invoices',
        'products',
        'parties',
        'accounts',
      ]) {
        expect(
          (await dependentsOf(target)).length,
          greaterThan(0),
          reason: 'مفيش تبعيات على $target — الاستعلام غلط',
        );
      }
    });

    test('قيود الـ FK مفعّلة في الاختبار زي التطبيق', () async {
      // من غير ده الاختبارات دي بتعدّي غلط: الحذف بينجح في الاختبار
      // وبيفشل عند العميل، وهي بالظبط الحالة اللي حصلت.
      final r = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(r.data.values.first, 1);
    });

    test('حذف فواتير المبيعات بينجح مع أمر تشغيل وفاتورة إلكترونية مرتبطين',
        () async {
      final invId = await seedSalesInvoice('S-FK', total: 10);

      // العمودان دول هما اللي وقّعوا العملية عند العميل: الأول اختياري
      // (يتفصل) والتاني إجباري (الصف يتحذف).
      await db.customUpdate(
        'INSERT INTO work_orders (order_number, invoice_id) '
        "VALUES ('WO-1', $invId)",
      );
      await db.customUpdate(
        'INSERT INTO e_invoice_submissions (sale_id, platform) '
        "VALUES ($invId, 'test')",
      );

      final res = await svc.wipeSalesInvoices();

      expect(res.ok, isTrue, reason: res.error);
      expect(await countOf('sales_invoices'), 0);
      // أمر التشغيل مستند مستقل — بيفضل موجود بلا ربط.
      expect(await countOf('work_orders'), 1);
      final wo = await db
          .customSelect('SELECT invoice_id FROM work_orders')
          .getSingle();
      expect(wo.data['invoice_id'], isNull);
      // الفاتورة الإلكترونية مالهاش معنى من غير فاتورتها.
      expect(await countOf('e_invoice_submissions'), 0);
    });

    test('حذف الأصناف بينجح مع بنود مستندات مرتبطة', () async {
      final pid = await seedProduct('صنف مرتبط بكل حاجة');

      await db.customUpdate('INSERT INTO stock_audits DEFAULT VALUES');
      final auditId = (await db
              .customSelect('SELECT id FROM stock_audits LIMIT 1')
              .getSingle())
          .data['id'] as int;
      await db.customUpdate(
        'INSERT INTO inventory_bonds (bond_number, warehouse_id) '
        "VALUES ('B-1', $whId)",
      );
      final bondId = (await db
              .customSelect('SELECT id FROM inventory_bonds LIMIT 1')
              .getSingle())
          .data['id'] as int;

      // بنود مستندات كانت **كلها** ناقصة من التعداد اليدوي.
      await db.customUpdate(
        'INSERT INTO stock_audit_items (audit_id, product_id, '
        'expected_quantity, actual_quantity, difference) '
        'VALUES ($auditId, $pid, 0, 0, 0)',
      );
      await db.customUpdate(
        'INSERT INTO inventory_bond_items (bond_id, product_id, quantity) '
        'VALUES ($bondId, $pid, 1)',
      );

      final res = await svc.wipeProducts();

      expect(res.ok, isTrue, reason: res.error);
      expect(await countOf('products'), 0);
      expect(await countOf('stock_audit_items'), 0);
      expect(await countOf('inventory_bond_items'), 0);
    });

    test('الروابط الاختيارية تتفصل ولا تُحذف مستنداتها', () async {
      // عرض سعر اتحوّل لفاتورة: حذف الفاتورة **مش** المفروض يمسح عرض
      // السعر — ده مستند تاني ما حدش طلب مسحه.
      final invId = await seedSalesInvoice('S-Q', total: 5);
      await db.customUpdate(
        'INSERT INTO quotations (quotation_number, warehouse_id, user_id, '
        'quotation_date, converted_to_invoice_id) '
        "VALUES ('Q-1', $whId, $userId, 0, $invId)",
      );

      final res = await svc.wipeSalesInvoices();

      expect(res.ok, isTrue, reason: res.error);
      expect(await countOf('quotations'), 1);
      final q = await db
          .customSelect('SELECT converted_to_invoice_id FROM quotations')
          .getSingle();
      expect(q.data['converted_to_invoice_id'], isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ٤) النسخة الاحتياطية — الحماية التالتة
  // ═══════════════════════════════════════════════════════════════════════

  group('النسخة الاحتياطية', () {
    test('بتتاخد قبل الحذف وبترجع مسار موجود فعلاً', () async {
      await seedProduct('صنف');

      final res = await svc.wipeProducts();

      expect(res.ok, isTrue, reason: res.error);
      expect(res.backupPath, isNotNull);
      final backup = File(res.backupPath!);
      expect(backup.existsSync(), isTrue);
      // اتاخدت من ملف الداتابيز مش من حتة تانية.
      expect(backup.readAsStringSync(), 'fake sqlite payload');
    });

    // ── تفريغ الـ WAL قبل النسخ ──────────────────────────────────────────
    //
    // نسخ ملف الـ `.db` لوحده بيعكس آخر تفريغ تلقائي مش الحالة دلوقتي، لأن
    // المعاملات بتقعد في `<db>-wal` لحد الـ checkpoint. أدوات التصفير
    // بتمرّر `requireCheckpoint: true` لأن نسخة ناقصة عندها معناها إن اللي
    // يرجع بعد الحذف أقل من اللي اتحذف.

    test('التفريغ بيتنفّذ قبل النسخ', () async {
      var called = false;
      final path = await createDatabaseBackup(checkpoint: () async {
        called = true;
        return true;
      });

      expect(called, isTrue);
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
    });

    test('requireCheckpoint: فشل التفريغ بيلغي النسخة كلها', () async {
      final path = await createDatabaseBackup(
        checkpoint: () async => false,
        requireCheckpoint: true,
      );

      expect(path, isNull);
    });

    test('من غير requireCheckpoint: النسخة بتتاخد رغم فشل التفريغ', () async {
      // نسخة ناقصة أحسن من ولا نسخة — ده اللي نسخة الإقلاع التلقائية
      // ونسخة زرار الإعدادات بيعملوه.
      final path = await createDatabaseBackup(checkpoint: () async => false);

      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
    });

    // ── الاستعادة المعلَّقة ────────────────────────────────────────────
    //
    // الاستعادة كانت بتحاول تكتب فوق ملف الداتابيز وهو مفتوح — بتفشل على
    // ويندوز. والكود الأقدم كان بيخبّي الفشل لأنه بيكتب على ملف مهجور،
    // فيقول «تمت الاستعادة بنجاح» وهو ما عملش حاجة.

    test('الاستعادة بتتجدول ومبتلمسش الداتابيز الحالية', () async {
      final source = File('${docsDir.path}${Platform.pathSeparator}src.db')
        ..writeAsStringSync('restored payload');
      final dbFile = File(
        '${docsDir.path}${Platform.pathSeparator}${getDatabaseFileName()}',
      );

      final ok = await restoreDatabaseBackup(source.path);

      expect(ok, isTrue);
      // الملف الحيّ زي ما هو — الاستعادة لسه ما اتطبّقتش.
      expect(dbFile.readAsStringSync(), 'fake sqlite payload');
      expect(await hasPendingRestore(), isTrue);
    });

    test('نسخة احتياطية مش موجودة → الجدولة تفشل ومفيش معلَّق', () async {
      final ok = await restoreDatabaseBackup(
        '${docsDir.path}${Platform.pathSeparator}لا-يوجد.db',
      );

      expect(ok, isFalse);
      expect(await hasPendingRestore(), isFalse);
    });

    test('walCheckpointTruncate بتنجح على قاعدة شغّالة', () async {
      // على قاعدة في الذاكرة الـ PRAGMA بيرجع (busy:0, log:-1,
      // checkpointed:-1) — الـ -1 معناها إن الـ WAL مش مستخدم أصلاً، و
      // `busy = 0` هي العلامة اللي بنقرا منها إن مفيش حاجة فاضلة تتفرّغ.
      expect(await walCheckpointTruncate(db), isTrue);
    });

    test('نسختان في نفس الثانية — التانية متفشّلش العملية', () async {
      // اسم النسخة بدقة ثانية، و`File.copy` على ويندوز بيرمي لو الهدف موجود.
      // من غير فض التصادم كانت أي عمليتين ورا بعض (أو عملية بعد نسخة الإقلاع
      // التلقائية) بتتلغي برسالة «تعذّر إنشاء نسخة احتياطية».
      await seedProduct('صنف أول');
      final first = await svc.wipeProducts();
      expect(first.ok, isTrue, reason: first.error);

      await seedProduct('صنف تاني');
      final second = await svc.wipeProducts();

      expect(second.ok, isTrue, reason: second.error);
      expect(second.backupPath, isNotNull);
      expect(second.backupPath, isNot(first.backupPath));
      expect(File(second.backupPath!).existsSync(), isTrue);
    });

    test('الاستبقاء بيفلتر باسم الداتابيز — نسخ منتج تاني ما تتمسحش',
        () async {
      final backupsDir = Directory(
        '${docsDir.path}${Platform.pathSeparator}backups',
      )..createSync(recursive: true);

      // ١٢ نسخة لمنتج تاني في نفس المجلد المشترك.
      for (var i = 0; i < 12; i++) {
        File('${backupsDir.path}${Platform.pathSeparator}'
                'other_brand_unified.db_backup_2026-07-0$i.db')
            .writeAsStringSync('other brand $i');
      }

      await seedProduct('صنف');
      final res = await svc.wipeProducts();
      expect(res.ok, isTrue, reason: res.error);

      final survivors = backupsDir
          .listSync()
          .map((f) => f.path.split(Platform.pathSeparator).last)
          .where((n) => n.startsWith('other_brand_'))
          .toList();
      // من غير الفلترة كان الاستبقاء (آخر ٧) هيمسح ٦ منهم.
      expect(survivors.length, 12);
    });
  });
}
