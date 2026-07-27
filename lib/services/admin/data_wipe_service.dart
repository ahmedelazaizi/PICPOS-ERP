// ═══════════════════════════════════════════════════════════════════════════
// أدوات تصفير البيانات — للمطوّر فقط
// ═══════════════════════════════════════════════════════════════════════════
//
// عمليات حذف جماعي على قاعدة البيانات مباشرة. الملف ده **بلا رجعة**: مفيش
// «إلغاء» بعد التنفيذ، والنسخة الاحتياطية هي طريق الرجوع الوحيد — عشان كده
// كل عملية بتاخد نسخة قبل أول حذف، وبترفض التنفيذ لو النسخة فشلت.
//
// ── ليه الترتيب هو أهم حاجة هنا ──────────────────────────────────────────
// حذف فاتورة مبيعات ويسيب قيدها في اليومية = دفتر أستاذ مش متوازن: الحسابات
// فيها مدين ودائن لعملية مالها مستند. وحذفها ويسيب حركة المخزون = كميات
// وتكلفة لأصناف مالهاش مصدر. فكل عملية مالية هنا بتحذف **الوثيقة وقيدها
// وحركتها المخزنية** في معاملة واحدة، أو متحذفش حاجة.
//
// وحذف الأب قبل الأبناء بيسيب صفوف يتيمة بتظهر في التقارير كأرقام بلا سياق.
// فترتيب الحذف: الأبناء ← الأب. مكتوب صريح في كل عملية.
//
// ── حدود معروفة (اقرأها قبل ما تستخدم) ───────────────────────────────────
// 1. **وضع العميل/السيرفر:** الحذف ده محلي. في وضع العميل، المزامنة الجاية
//    ممكن ترجّع الصفوف من السيرفر؛ وفي وضع السيرفر، الأجهزة المقترنة مش
//    هتعرف إن الصفوف اتحذفت. الأدوات دي للبيئات التجريبية والتركيبات
//    المستقلة — الخدمة بترفض التنفيذ في وضع العميل.
// 2. **الفترات المقفولة:** الحذف بيتخطّى قفل الفترة المحاسبية عن قصد — ده
//    تصفير مش تعديل قيد. لو الفترة مقفولة ومحتاج تسيبها متوازنة، اعمل
//    قيود عكسية بدل التصفير.
// 3. الجداول المذكورة في كل عملية هي اللي اتراجعت فعلاً. أي جدول اتضاف
//    للسكيما بعد كتابة الملف ده مش مغطّى تلقائياً.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';

import '../../data/database/connection_io.dart' show createDatabaseBackup;
import '../../data/database/database.dart';
import '../../data/database/sync_interceptor.dart';
import '../../data/database/wal_checkpoint.dart';

/// نتيجة عملية تصفير.
@immutable
class WipeResult {
  final bool ok;

  /// عدد الصفوف المحذوفة لكل جدول — عشان الواجهة تقول اللي حصل بالظبط
  /// بدل «تم» عامة.
  final Map<String, int> deleted;

  /// مسار النسخة الاحتياطية اللي اتاخدت قبل الحذف.
  final String? backupPath;

  /// سبب الرفض أو الفشل بالعربي.
  final String? error;

  const WipeResult._({
    required this.ok,
    this.deleted = const {},
    this.backupPath,
    this.error,
  });

  factory WipeResult.success(Map<String, int> deleted, String? backupPath) =>
      WipeResult._(ok: true, deleted: deleted, backupPath: backupPath);

  factory WipeResult.failure(String error) =>
      WipeResult._(ok: false, error: error);

  int get totalRows => deleted.values.fold(0, (a, b) => a + b);
}

class DataWipeService {
  final AppDatabase db;

  DataWipeService(this.db);

  // ── الحُرّاس ──────────────────────────────────────────────────────────────

  /// بيرفض التنفيذ في وضع العميل: الحذف محلي، والمزامنة الجاية ترجّع الصفوف
  /// من السيرفر — فالمستخدم يشوف «تم الحذف» وبعد دقيقة البيانات رجعت.
  String? _rejectIfClient() {
    if (SyncInterceptor.isClientMode) {
      return 'غير متاح في وضع العميل: الحذف محلي، والمزامنة الجاية هترجّع '
          'الصفوف من السيرفر. نفّذ التصفير على السيرفر نفسه.';
    }
    return null;
  }

  /// بياخد نسخة احتياطية. الفشل بيوقف العملية — النسخة هي طريق الرجوع
  /// الوحيد، والحذف من غيرها مقامرة مش عملية صيانة.
  ///
  /// و`requireCheckpoint: true` عشان نفس السبب: نسخ ملف الـ `.db` من غير
  /// تفريغ الـ WAL بيسيب المعاملات الأخيرة برّه النسخة، فاللي هيرجع بعد
  /// الحذف يبقى أقل من اللي اتحذف. نسخة ناقصة هنا أسوأ من إلغاء العملية.
  Future<(String?, String?)> _backupOrFail() async {
    try {
      final path = await createDatabaseBackup(
        checkpoint: () => walCheckpointTruncate(db),
        requireCheckpoint: true,
      );
      if (path == null || path.isEmpty) {
        return (
          null,
          'تعذّر إنشاء نسخة احتياطية كاملة — أُلغيت العملية.\n\n'
              'لو التطبيق مفتوح على أجهزة أو نوافذ تانية، اقفلها وحاول تاني.',
        );
      }
      return (path, null);
    } catch (e) {
      return (null, 'فشل إنشاء النسخة الاحتياطية: $e — أُلغيت العملية.');
    }
  }

  Future<int> _wipe(drift.TableInfo table) async {
    return db.delete(table).go();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // تنظيف التبعيات — مولَّد من السكيما مش مكتوب بالإيد
  // ═══════════════════════════════════════════════════════════════════════
  //
  // النسخة الأولى من الملف ده كانت بتعدّد جداول الأبناء **بالإيد**، والحد ده
  // كان مكتوب في رأس الملف كملاحظة. وهو اللي ضرب فعلاً على أول قاعدة حقيقية:
  //
  //   SqliteException(787): FOREIGN KEY constraint failed
  //   Causing statement: DELETE FROM "sales_invoices"
  //
  // لأن `work_orders` و`e_invoice_submissions` و`quotations` و`sales_orders`
  // كلهم بيشاوروا على `sales_invoices` وماكانوش في القايمة. والفحص على
  // السكيما طلّع نفس المشكلة في كل عملية تانية — `wipeProducts` لوحدها كانت
  // ناقصة **١٢ جدول**.
  //
  // فالمصدر بقى `PRAGMA foreign_key_list` نفسه: نسأل الداتابيز مين بيشاور
  // على الهدف، ونتصرّف حسب نوع العمود:
  //
  //   * العمود **بيقبل NULL** → نفصل الربط بس. عرض سعر اتحوّل لفاتورة
  //     والفاتورة اتحذفت لازم يفضل موجود — حذفه معناه إننا بنمسح مستند
  //     تاني ما حدش طلب مسحه. نفس منطق «الطرف المزدوج» الموجود تحت.
  //   * العمود **إجباري** → الصف مالوش معنى من غير أبوه، فيتحذف، ونكرّر
  //     العملية عليه هو كمان (بنته ممكن يكون ليها أبناء).
  //
  // وكده أي جدول جديد يتضاف للسكيما بيتغطّى لوحده.

  /// كل الأعمدة اللي بتشاور على [target]، مع هل العمود بيقبل NULL.
  Future<List<({String table, String column, bool nullable})>> _dependentsOf(
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
        // `notnull = 1` معناها العمود إجباري.
        final nullable = (col?.data['notnull'] as int? ?? 0) == 0;

        out.add((table: name, column: column, nullable: nullable));
      }
    }
    return out;
  }

  /// بيفضّي الطريق قدّام حذف [target]: يفصل الروابط الاختيارية ويحذف الصفوف
  /// اللي مالهاش معنى من غير أبوها — بالتكرار لحد ما التبعيات تخلص.
  ///
  /// [counts] بتتزوّد بالمحذوف والمفصول عشان الواجهة تعرض اللي حصل بالظبط.
  Future<void> _clearDependents(
    String target,
    Map<String, int> counts, {
    Set<String>? visited,
  }) async {
    final seen = visited ?? <String>{};
    if (!seen.add(target)) return; // دورة في السكيما — بنوقف

    for (final dep in await _dependentsOf(target)) {
      if (dep.table == target) continue;

      if (dep.nullable) {
        final n = await db.customUpdate(
          'UPDATE "${dep.table}" SET "${dep.column}" = NULL '
          'WHERE "${dep.column}" IS NOT NULL',
        );
        if (n > 0) counts['فصل ارتباط ${dep.table}'] = n;
      } else {
        // الأبناء الأول، وبعدين الصف نفسه.
        await _clearDependents(dep.table, counts, visited: seen);
        final n = await db.customUpdate('DELETE FROM "${dep.table}"');
        if (n > 0) {
          counts[dep.table] = (counts[dep.table] ?? 0) + n;
        }
      }
    }
  }

  /// القالب المشترك: حارس الوضع ← نسخة احتياطية ← معاملة واحدة.
  ///
  /// المعاملة مهمة: لو الحذف وقع في النص، الجزء اللي اتنفّذ يترجع. الحالة
  /// الوسيطة (فواتير محذوفة وقيودها موجودة) أسوأ من عدم التنفيذ.
  Future<WipeResult> _run(
    String label,
    Future<Map<String, int>> Function() body,
  ) async {
    final rejection = _rejectIfClient();
    if (rejection != null) return WipeResult.failure(rejection);

    final (backupPath, backupError) = await _backupOrFail();
    if (backupError != null) return WipeResult.failure(backupError);

    try {
      final counts = await db.transaction(body);
      debugPrint('[DATA-WIPE] $label → $counts');
      return WipeResult.success(counts, backupPath);
    } catch (e, st) {
      debugPrint('[DATA-WIPE] $label FAILED: $e\n$st');
      return WipeResult.failure('فشل التنفيذ وتم التراجع عن كل شيء: $e');
    }
  }

  // ── الأصناف ──────────────────────────────────────────────────────────────

  /// حذف كل الأصناف وكل ما يتعلق بيها.
  ///
  /// بيرفض لو فيه فواتير: بند فاتورة بيشاور على صنف محذوف بيخلّي الفاتورة
  /// تُطبع بسطر فاضي، والتقارير تحسب مبيعات لصنف مش موجود. صفّي الفواتير
  /// الأول لو ده اللي إنت قاصده.
  Future<WipeResult> wipeProducts() async {
    final salesItems =
        await db.customSelect('SELECT COUNT(*) c FROM sales_invoice_items')
            .getSingleOrNull();
    final purchItems =
        await db.customSelect('SELECT COUNT(*) c FROM purchase_invoice_items')
            .getSingleOrNull();
    final linked = ((salesItems?.data['c'] as int?) ?? 0) +
        ((purchItems?.data['c'] as int?) ?? 0);
    if (linked > 0) {
      return WipeResult.failure(
        'فيه $linked بند فاتورة بيشاور على أصناف. حذف الأصناف هيخلّي الفواتير '
        'دي بسطور بلا أصناف والتقارير تحسب مبيعات لأصناف مش موجودة.\n\n'
        'صفّي فواتير المبيعات والمشتريات الأول.',
      );
    }

    return _run('products', () async {
      final counts = <String, int>{};
      // الأبناء قبل الأب.
      counts['أرصدة المخزون'] = await _wipe(db.inventoryBalances);
      counts['حركات المخزون'] = await _wipe(db.stockMovements);
      counts['باركودات الأصناف'] = await _wipe(db.productBarcodes);
      counts['وحدات الأصناف'] = await _wipe(db.productUnits);
      counts['تشغيلات الأصناف'] = await _wipe(db.productBatches);
      counts['أسعار المستودعات'] = await _wipe(db.warehousePrices);
      counts['بنود قوائم الأسعار'] = await _wipe(db.priceListItems);
      counts['بنود العروض'] = await _wipe(db.offerItems);
      counts['مكوّنات قوائم التصنيع'] = await _wipe(db.bomComponents);
      counts['قوائم التصنيع'] = await _wipe(db.billOfMaterials);
      // الأصناف عندها أكتر من عشرين جدول تابع (فواتير معلقة، جرد، سندات،
      // أوامر شراء وبيع، عروض أسعار، تكاليف محمّلة…). التعداد اليدوي كان
      // ناقص ١٢ منهم.
      await _clearDependents('products', counts);
      counts['الأصناف'] = await _wipe(db.products);
      return counts;
    });
  }

  // ── فواتير المبيعات ──────────────────────────────────────────────────────

  /// حذف كل فواتير المبيعات — ومعاها قيودها وحركاتها المخزنية.
  ///
  /// القيود وحركة المخزون بتتحذف مع الفاتورة عن قصد: فاتورة محذوفة وقيدها
  /// موجود = دفتر أستاذ فيه مدين ودائن لمستند مش موجود.
  Future<WipeResult> wipeSalesInvoices() => _run('sales', () async {
        final counts = <String, int>{};
        counts['بنود الفواتير'] = await _wipe(db.salesInvoiceItems);
        counts['استهلاك التصنيع في البيع'] =
            await _wipe(db.saleBomConsumptions);
        counts['تخصيصات الدفعات'] = await _wipe(db.paymentAllocations);
        counts['الدفعات'] = await _wipe(db.payments);
        counts['حركات المخزون'] = await _wipe(db.stockMovements);
        counts['بنود اليومية'] = await _wipe(db.journalEntryLines);
        counts['قيود اليومية'] = await _wipe(db.journalEntries);
        counts['حركات الصناديق'] = await _wipe(db.safeTransactions);
        // أي تبعية باقية على الفاتورة (أوامر التشغيل، الفواتير الإلكترونية،
        // عروض الأسعار المتحوّلة، أوامر البيع) تتفصل أو تتحذف حسب نوع العمود.
        await _clearDependents('sales_invoices', counts);
        counts['الفواتير'] = await _wipe(db.salesInvoices);
        return counts;
      });

  // ── فواتير المشتريات ─────────────────────────────────────────────────────

  Future<WipeResult> wipePurchaseInvoices() => _run('purchases', () async {
        final counts = <String, int>{};
        counts['بنود الفواتير'] = await _wipe(db.purchaseInvoiceItems);
        counts['توزيعات التكاليف المحملة'] =
            await _wipe(db.landedCostAllocations);
        counts['بنود التكاليف المحملة'] = await _wipe(db.landedCostItems);
        counts['كشوف التكاليف المحملة'] = await _wipe(db.landedCostSheets);
        counts['حركات المخزون'] = await _wipe(db.stockMovements);
        counts['بنود اليومية'] = await _wipe(db.journalEntryLines);
        counts['قيود اليومية'] = await _wipe(db.journalEntries);
        await _clearDependents('purchase_invoices', counts);
        counts['الفواتير'] = await _wipe(db.purchaseInvoices);
        return counts;
      });

  // ── العملاء والموردين ────────────────────────────────────────────────────

  /// حذف الأطراف. `isCustomer` بتفرّق بين العملاء والموردين، والطرف اللي هو
  /// الاتنين مبيتحذفش إلا لو الطلبين اتنفّذوا — وإلا كنا بنحذف مورد وإحنا
  /// قاصدين عميل.
  Future<WipeResult> wipeParties({required bool customers}) async {
    final table = customers ? 'العملاء' : 'الموردين';
    final flagCol = customers ? 'is_customer' : 'is_supplier';
    final otherCol = customers ? 'is_supplier' : 'is_customer';

    final refs = await db
        .customSelect(
          'SELECT COUNT(*) c FROM ${customers ? 'sales_invoices' : 'purchase_invoices'}',
        )
        .getSingleOrNull();
    final linked = (refs?.data['c'] as int?) ?? 0;
    if (linked > 0) {
      return WipeResult.failure(
        'فيه $linked فاتورة مرتبطة بـ$table. حذفهم هيخلّي الفواتير بلا طرف '
        'وكشوف الحساب بلا صاحب.\n\nصفّي الفواتير الأول.',
      );
    }

    return _run('parties-$flagCol', () async {
      final counts = <String, int>{};
      // الطرف اللي هو عميل ومورد في نفس الوقت: نلغي الصفة المطلوبة بس،
      // وميتحذفش — حذفه كان معناه إننا نحذف مورد وإحنا قاصدين عميل.
      final demoted = await db.customUpdate(
        'UPDATE parties SET $flagCol = 0 WHERE $flagCol = 1 AND $otherCol = 1',
        updates: {db.parties},
      );
      counts['أطراف مزدوجة (أُلغيت الصفة فقط)'] = demoted;

      // الأطراف عندها ١٤ جدول تابع (دفعات، أوراق تجارية، نقاط ولاء، أوامر
      // بيع وشراء، فواتير معلقة…) — الحارس فوق بيغطي الفواتير بس.
      await _clearDependents('parties', counts);

      final removed = await db.customUpdate(
        'DELETE FROM parties WHERE $flagCol = 1 AND $otherCol = 0',
        updates: {db.parties},
      );
      counts[table] = removed;
      return counts;
    });
  }

  // ── دليل الحسابات ────────────────────────────────────────────────────────

  /// حذف الحسابات المُضافة. بيرفض لو فيه قيود: حساب محذوف وله بنود يومية
  /// معناه ميزان مراجعة بأرصدة بلا حسابات.
  Future<WipeResult> wipeChartOfAccounts() async {
    final lines = await db
        .customSelect('SELECT COUNT(*) c FROM journal_entry_lines')
        .getSingleOrNull();
    final linked = (lines?.data['c'] as int?) ?? 0;
    if (linked > 0) {
      return WipeResult.failure(
        'فيه $linked بند يومية بيشاور على حسابات. حذف الحسابات هيخلّي ميزان '
        'المراجعة بأرصدة بلا حسابات.\n\nصفّي فواتير المبيعات والمشتريات الأول '
        '(بتحذف قيودها معاها).',
      );
    }

    return _run('accounts', () async {
      final counts = <String, int>{};
      counts['ربط الحسابات'] = await _wipe(db.accountMappings);
      counts['بنود قوالب اليومية'] = await _wipe(db.journalEntryTemplateLines);
      counts['قوالب اليومية'] = await _wipe(db.journalEntryTemplates);
      // الحسابات مربوطة بالخزائن والأصول الثابتة والموازنات والتسويات
      // البنكية — وكلهم روابط اختيارية بتتفصل مش مستندات تتحذف.
      await _clearDependents('accounts', counts);
      counts['الحسابات'] = await _wipe(db.accounts);
      return counts;
    });
  }

  // ── التصفير الكامل ───────────────────────────────────────────────────────

  /// تصفير كل البيانات الحركية، مع الإبقاء على **الإعدادات والمستخدمين
  /// والصلاحيات والفروع والمستودعات وتعريفات الصناديق**.
  ///
  /// الاستثناءات دي مقصودة: تركيب بلا مستخدمين ولا فروع مش «مصفّر»، ده
  /// تركيب مكسور — البرنامج مش هيقدر يشتغل ولا حتى يفتح شاشة دخول صحيحة.
  /// اللي عايز يبدأ من الصفر تماماً يمسح ملف الداتابيز نفسه ويعيد الويزارد.
  Future<WipeResult> wipeAllTransactionalData() => _run('full', () async {
        final counts = <String, int>{};

        // مبيعات ومشتريات وما يتبعهم
        counts['بنود فواتير المبيعات'] = await _wipe(db.salesInvoiceItems);
        counts['فواتير المبيعات'] = await _wipe(db.salesInvoices);
        counts['بنود فواتير المشتريات'] = await _wipe(db.purchaseInvoiceItems);
        counts['فواتير المشتريات'] = await _wipe(db.purchaseInvoices);
        counts['بنود أوامر البيع'] = await _wipe(db.salesOrderItems);
        counts['أوامر البيع'] = await _wipe(db.salesOrders);
        counts['بنود أوامر الشراء'] = await _wipe(db.purchaseOrderItems);
        counts['أوامر الشراء'] = await _wipe(db.purchaseOrders);
        counts['بنود عروض الأسعار'] = await _wipe(db.quotationItems);
        counts['عروض الأسعار'] = await _wipe(db.quotations);

        // مخزون
        counts['حركات المخزون'] = await _wipe(db.stockMovements);
        counts['أرصدة المخزون'] = await _wipe(db.inventoryBalances);
        counts['بنود سندات المخزون'] = await _wipe(db.inventoryBondItems);
        counts['سندات المخزون'] = await _wipe(db.inventoryBonds);
        counts['بنود الجرد'] = await _wipe(db.stockAuditItems);
        counts['الجرد'] = await _wipe(db.stockAudits);

        // محاسبة
        counts['بنود اليومية'] = await _wipe(db.journalEntryLines);
        counts['قيود اليومية'] = await _wipe(db.journalEntries);
        counts['تخصيصات الدفعات'] = await _wipe(db.paymentAllocations);
        counts['الدفعات'] = await _wipe(db.payments);
        counts['حركات الصناديق'] = await _wipe(db.safeTransactions);

        // نقطة بيع
        counts['بنود الفواتير المعلقة'] = await _wipe(db.heldOrderItems);
        counts['الفواتير المعلقة'] = await _wipe(db.heldOrders);
        counts['الورديات'] = await _wipe(db.shifts);

        // أطراف وأصناف — دول أكتر جدولين عليهم تبعيات في السكيما كلها،
        // فالتنظيف المولَّد بيمسك اللي التعداد اليدوي فوق ما وصلوش.
        await _clearDependents('parties', counts);
        counts['الأطراف'] = await _wipe(db.parties);
        await _clearDependents('products', counts);
        counts['الأصناف'] = await _wipe(db.products);

        // سجلات
        counts['سجل العمليات'] = await _wipe(db.activityLogs);
        counts['التنبيهات'] = await _wipe(db.notifications);

        return counts;
      });
}
