// المهمّةُ ٣ (2026-08-16) — العطبُ المقيس: المرتجعُ كان يضرب
// `getDefaultSafeByType('cash')` — خزنةً عامّةً تتجاهل الفرع — بينما البيعُ
// والإقفالُ ينسبان للفرع. فمرتجعٌ في الفرع «ب» كان يُنقص خزنةَ الفرع «أ».
//
// الاختبارُ الأوّل يثبّت العقدَ على مستوى الـDAO مباشرةً: `resolveRefundSafe`
// تُرجع درجَ فرع الوردية المفتوحة لمستخدم المرتجع، لا الخزنةَ الافتراضيةَ
// العامّة.
//
// جولةُ مراجعةٍ ١ (2026-08-16): الاختبارُ الأوّل ينادي `db.resolveRefundSafe`
// مباشرةً ولا يمرّ بمسار الإنتاج الفعليّ (`ReturnsRepositoryImpl.
// processSalesReturn` / `ProcessSalesReturnUseCase`) — فلو رُدَّت مواضعُ
// النداء الثلاثة إلى `getDefaultSafeByType('cash')` لبقي هذا الاختبار
// أخضر. المجموعةُ الثانية أدناه تسدّ هذه الفجوة: تنادي `processSalesReturn`
// فعلياً وتفحص حركةَ الخزنة الناتجة.

import 'package:flutter_test/flutter_test.dart';
// hide isNull/isNotNull — تصادمُ الاسم مع matcher الخاصّ بـflutter_test.
// full import (لا `show Value` فقط) لازمٌ لعامل `&` على `Expression<bool>`
// في شرط `refundTxnFor` أدناه — مطابقةٌ لنمط
// `sales_return_wac_gl_drift_test.dart`.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/domain/models/shift_drawer_resolver.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/data/repositories/returns_repository_impl.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/domain/repositories/audit_repository_interface.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/services/accounting_service.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() async => db.close());

  test('المرتجعُ يُصرف من درج فرع الوردية لا من الخزنة العامّة', () async {
    // فرعان، ولكلٍّ خزنتُه النقدية.
    final branchA = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرع أ'),
        );
    final branchB = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرع ب'),
        );
    final safeA = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'درج أ',
            safeType: const Value('cash'),
            branchId: Value(branchA),
          ),
        );
    final safeB = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'درج ب',
            safeType: const Value('cash'),
            branchId: Value(branchB),
          ),
        );

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    // ملحوظة: `createUser` لا يقبل `branchId` — فرعُ الكاشير هنا يُحدَّد عبر
    // `shift.branchId` (مطابقةٌ لما يستهلكه `resolveRefundSafe` فعلياً)، لا
    // عبر جدول المستخدم.
    final userB = await db.createUser(
      username: 'cashier_b',
      password: 'x',
      displayName: 'كاشير ب',
      roleId: roleId,
    );

    await db.into(db.shifts).insert(
          ShiftsCompanion.insert(
            startTime: DateTime.now(),
            userId: userB,
            status: 'open',
            branchId: Value(branchB),
          ),
        );

    final resolved = await db.resolveRefundSafe(userId: userB);

    expect(resolved, isNotNull);
    expect(resolved!.id, safeB,
        reason: 'كاشيرُ الفرع ب يجب أن يصرف من درج فرعه لا من $safeA');
  });

  // جولةُ مراجعةٍ ٢ (2026-08-16) — فرقُ إصلاح جولة ١ نفسُه أدخل عطبَين
  // Important، كلاهما داخل بناء مرشَّحي `resolveRefundSafe`.

  test(
      'فرعٌ فيه درجٌ معطَّلٌ برقمٍ أصغرَ وآخرُ نشِط — الصرفُ على النشِطة لا '
      'الأقدم رقماً', () async {
    // عطبٌ جديد ١: إسقاطُ فلتر isActive (لمطابقة _settleShift) جعل
    // الخزائنَ المعطَّلةَ مرشَّحةً. المعطَّلةُ تُنشأ أوّلاً عمداً كي يحمل
    // رقمُها الأصغرَ — رتيبُ الصفّ الطبيعيّ (لا فلتر isActive) كان
    // سيختارها.
    final branch = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرع بدرجٍ معطَّل ودرجٍ نشِط'),
        );
    final inactiveSafe = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'درجٌ قديمٌ معطَّل',
            safeType: const Value('cash'),
            branchId: Value(branch),
            isActive: const Value(false),
          ),
        );
    final activeSafe = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'درجٌ نشِط',
            safeType: const Value('cash'),
            branchId: Value(branch),
          ),
        );
    expect(inactiveSafe, lessThan(activeSafe),
        reason: 'المعطَّلةُ لازمٌ رقمُها الأصغرَ كي يفحص الاختبارُ الترتيبَ '
            'الطبيعيّ لا ترتيبَ الاسم');

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'كاشير', isSystemRole: const Value(false)),
        );
    final userId = await db.createUser(
      username: 'active_pref_cashier',
      password: 'x',
      displayName: 'كاشير تفضيل النشِطة',
      roleId: roleId,
    );
    await db.into(db.shifts).insert(
          ShiftsCompanion.insert(
            startTime: DateTime.now(),
            userId: userId,
            status: 'open',
            branchId: Value(branch),
          ),
        );
    // بلا أيّ حركةٍ بعد — أوّلُ عمليةٍ في هذه الوردية، فالمرشَّحون يسقطون
    // إلى خزائن الفرع كاملةً.

    final resolved = await db.resolveRefundSafe(userId: userId);

    expect(resolved, isNotNull);
    expect(resolved!.id, activeSafe,
        reason:
            'قبل الإصلاح: المعطَّلةُ (رقمٌ أصغر) كانت تُختار، فيختفي المبلغُ '
            'المصروفُ من getTotalCashBalance/getSafesBalancesByType '
            '(تفلتران is_active=1) بينما الأستاذُ يسجّله — فجوةٌ صامتة.');
  });

  // جولةُ مراجعةٍ ٣ (2026-08-16) — Important: `activeIds` في resolveRefundSafe
  // كان تفضيلاً لا فلتراً — «يبقى المرشَّحون كلُّهم إن كانوا كلُّهم
  // معطَّلين». مقابلٌ عملي: خزنةٌ وحيدةٌ في فرعٍ تُعطَّل في منتصف وردية
  // **بعد** أن لمسَها الكاشير ⇒ drawerSafeIds={X} ثم activeIds={} ⇒ كلُّ
  // مرتجعات تلك الوردية تخرج من خزنةٍ معطَّلة صامتةً (المبلغُ يختفي من
  // getTotalCashBalance/getSafesBalancesByType، والأستاذُ يسجّله).
  test(
      'خزنةُ الفرع الوحيدةُ لُمِسَت ثم عُطِّلت في منتصف الوردية — السقوطُ '
      'إلى الخزنة الافتراضية العامّة لا الصرفُ من معطَّلة', () async {
    // خزنةٌ عامّةٌ نشِطةٌ مزروعةٌ سلفاً في `AppDatabase.forTesting()` (نفسُ
    // ما يعتمده اختبارُ «غيابُ ورديةٍ أصلاً» أدناه) — تلعب دورَ
    // `getDefaultSafeByType('cash')` خارجَ فرع الكاشير، فيكون السقوطُ
    // إليها مميَّزاً عن خزنة الفرع المعطَّلة.
    final expectedDefault = await db.getDefaultSafeByType('cash');
    expect(expectedDefault, isNotNull);

    final branch = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرعٌ بخزنةٍ وحيدةٍ ستُعطَّل'),
        );
    final branchSafe = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'درجُ الفرع الوحيد',
            safeType: const Value('cash'),
            branchId: Value(branch),
          ),
        );

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'كاشير', isSystemRole: const Value(false)),
        );
    final userId = await db.createUser(
      username: 'disabled_mid_shift_cashier',
      password: 'x',
      displayName: 'كاشيرُ تعطيلِ منتصف الوردية',
      roleId: roleId,
    );
    final shiftStart = DateTime.now();
    await db.into(db.shifts).insert(
          ShiftsCompanion.insert(
            startTime: shiftStart,
            userId: userId,
            status: 'open',
            branchId: Value(branch),
          ),
        );
    // الكاشيرُ لمسَ درجَ فرعه فعلياً (بيعةٌ سابقةٌ في نفس الوردية) —
    // drawerSafeIds تُبنى من هذه الحركة (مسارُ userTxs، لا مسارَ السقوط
    // لخزائن الفرع كاملةً).
    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: 'SALE-MID-SHIFT-DISABLE',
            safeId: branchSafe,
            transactionType: 'receipt',
            category: 'sales',
            amount: 50,
            balanceAfter: 50,
            userId: Value(userId),
            createdAt: Value(shiftStart.add(const Duration(minutes: 1))),
          ),
        );

    // ثم يُعطَّل درجُ الفرع الوحيدُ في منتصف الوردية — بعد أن صار
    // «الدرجَ الذي لمسَه الكاشير».
    await (db.update(db.safes)..where((s) => s.id.equals(branchSafe)))
        .write(const SafesCompanion(isActive: Value(false)));

    DiagnosticLogger.enableTestMode();
    final resolved = await db.resolveRefundSafe(userId: userId);

    expect(resolved, isNotNull);
    expect(resolved!.id, expectedDefault!.id,
        reason: 'قبل الإصلاح: activeIds تُصبح فارغةً فيبقى drawerSafeIds '
            'كما هو (={branchSafe} المعطَّلة) ويُصرف منها فعلياً رغم '
            'تعطيلها — انحدارٌ سلوكيٌّ عن getDefaultSafeByType القديمة '
            '(تفلتر isActive دوماً).');
    expect(
      DiagnosticLogger.testLog.any((line) =>
          line.contains('REFUND-SAFE-FALLBACK') &&
          line.contains('all-candidate-safes-inactive')),
      isTrue,
      reason: 'السقوطُ إلى الخزنة العامّة بسبب تعطُّل كلّ المرشَّحين يجب '
          'أن يُسجَّل بسببٍ مميَّزٍ يفرّقه عن السقوطات الخمس الأخرى.',
    );
  });

  test(
      'صفُّ shift_variance هو الحركةُ الوحيدةُ في النافذة — resolveRefundSafe '
      'تختار نفسَ ما يختاره منطقُ _settleShift', () async {
    // عطبٌ جديد ٢: حلقةُ moved في جولة ١ استثنَت shift_variance، بينما
    // حلقةُ moved في _settleShift (المصدرُ المطلوبُ توحيدُ الدرج معه)
    // لا تستثنيه — الاستثناءُ هناك في حلقةٍ أخرى (totalReceipts/
    // totalPayments لحساب expectedCash) لا حلقة بناء الدرج.
    final branch = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرع بصفّ تسويةٍ وحيد'),
        );
    final safeFirst = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'أ - الدرجُ الأوّل (بلا حركة)',
            safeType: const Value('cash'),
            branchId: Value(branch),
          ),
        );
    final safeVariance = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'ب - الدرجُ الثاني (عليه التسوية)',
            safeType: const Value('cash'),
            branchId: Value(branch),
          ),
        );

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'كاشير', isSystemRole: const Value(false)),
        );
    final userId = await db.createUser(
      username: 'variance_unify_cashier',
      password: 'x',
      displayName: 'كاشير توحيد الدرج',
      roleId: roleId,
    );
    final shiftStart = DateTime.now();
    await db.into(db.shifts).insert(
          ShiftsCompanion.insert(
            startTime: shiftStart,
            userId: userId,
            status: 'open',
            branchId: Value(branch),
          ),
        );
    // صفُّ تسويةِ فرقٍ (كما يكتبه _postVarianceSafeTransaction من وردية
    // سابقة) — بلا userId (مطابقةٌ لواقع صفوف التسوية القديمة، وكي لا
    // يلتقطها فلترُ "ما لمسَه هذا المستخدم" فيُحلّ الأمرُ بمسارِ سقوط
    // الفرع + ترجيح moved كما يفعل _settleShift تماماً).
    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: 'SHV-VARIANCE-TEST',
            safeId: safeVariance,
            transactionType: 'receipt',
            category: 'shift_variance',
            amount: 40,
            balanceAfter: 40,
            createdAt: Value(shiftStart.add(const Duration(minutes: 1))),
          ),
        );

    final resolved = await db.resolveRefundSafe(userId: userId);
    expect(resolved, isNotNull);

    // المقارنةُ المباشرة: نفسُ الدالّة الخالصة التي يستعملها _settleShift
    // (المهمّة ١)، بنفس مرشَّحي الفرع وبنفس خريطة الحركة — يجب أن تتّفق
    // النتيجتان تماماً، إثباتاً لتعريفٍ واحدٍ للدرج لا تعريفَين.
    final expectedByShiftDrawerLogic = resolveShiftDrawer(
      cashSafeIdsInBranch: {safeFirst, safeVariance},
      movedBySafeId: {safeVariance: 40},
    );
    expect(resolved!.id, expectedByShiftDrawerLogic,
        reason: 'resolveRefundSafe يجب أن يتّفق مع resolveShiftDrawer '
            '(المستعملة فعلياً في _settleShift) على نفس المدخلات بالضبط');
    expect(resolved.id, safeVariance,
        reason: 'قبل الإصلاح: استثناءُ shift_variance من moved كان يُفرغ '
            'خريطةَ الحركة فيختار resolveShiftDrawer أوّلَ خزنةٍ ($safeFirst) '
            'بدل التي عليها التسويةُ الفعلية ($safeVariance)');
  });

  group('processSalesReturn عبر السلك الحقيقيّ — يحمي الإصلاح لا الدالّةَ الخالصةَ وحدها', () {
    late ReturnsRepositoryImpl repo;
    late int warehouseId;
    late int productId;
    late int roleId;

    setUp(() async {
      // جولةُ مراجعةٍ ١ — يلتقط سطورَ `DiagnosticLogger.log('REFUND-SAFE-
      // FALLBACK', ...)` في `DiagnosticLogger.testLog` بدل كتابة ملفٍّ حقيقيّ
      // (‏نمطٌ مستعمَلٌ فعلاً في 16 ملفَّ اختبارٍ آخر، منها
      // `shift_sync_strategy_open_shift_test.dart`).
      DiagnosticLogger.enableTestMode();
      // مطلوبةٌ لتنجح `autoPostSalesReturn` (تحتاج دليلَ حساباتٍ ممتلئاً)
      // — مطابقةٌ لإعداد `sales_return_wac_gl_drift_test.dart`.
      await db.syncDefaultAccounts();
      repo = ReturnsRepositoryImpl(
        db,
        AccountingService(
          DriftAccountingRepository(db),
          _StubPartiesRepo(),
          _StubTreasuryRepo(),
          _StubProductRepo(),
          _StubInventoryRepo(),
          _StubSettingsRepo(),
          _StubAuditRepo(),
        ),
      );
      roleId = await db.into(db.roles).insert(
            RolesCompanion.insert(
                name: 'كاشير', isSystemRole: const Value(false)),
          );
      warehouseId = (await db.getDefaultWarehouse())!.id;
      productId = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'RTN-WIRE-01',
          name: 'منتج اختبار السلك',
          salePrice: const Value(100.0),
          costPrice: const Value(0),
          currentStock: const Value(0),
          // تبسيطٌ متعمَّد: الاختبارُ يفحص الصرفَ النقديّ لا المخزون، فتعطيلُ
          // تتبّع المخزون يتفادى إعدادَ WAC/adjustStock غيرَ ذي الصلة.
          trackInventory: const Value(false),
        ),
      );
    });

    Future<int> createCashier(String username) => db.createUser(
          username: username,
          password: 'x',
          displayName: username,
          roleId: roleId,
        );

    /// فاتورةُ بيعٍ نقديةٌ أصليةٌ بمعرّفٍ مستخدمٍ (admin، id=1) لا علاقة له
    /// بمن يعالج المرتجعَ لاحقاً — كي لا تتلوّث حركاتُ "مَن-لمَس-الدرجَ" التي
    /// يفحصها `resolveRefundSafe` بحركة البيع الأصليّ.
    Future<SalesInvoiceData> makeOriginalSale({double amount = 100}) async {
      final id = await db.createSalesInvoice(
        invoiceNumber: 'INV-WIRE-${DateTime.now().microsecondsSinceEpoch}',
        warehouseId: warehouseId,
        userId: 1,
        subtotal: amount,
        discount: 0,
        tax: 0,
        total: amount,
        paid: amount,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1,
            unitPrice: amount,
            total: amount,
            costPrice: const Value(0),
          ),
        ],
      );
      return (db.select(db.salesInvoices)..where((s) => s.id.equals(id)))
          .getSingle();
    }

    Future<Map<int, ProductEntity>> productCacheFor() async {
      final p = await db.getProductById(productId);
      return {
        productId: ProductEntity(
          id: p!.id,
          name: p.name,
          code: p.code,
          salePrice: p.salePrice,
          costPrice: p.costPrice,
          currentStock: p.currentStock,
          minStock: p.minStock,
          trackInventory: p.trackInventory,
        ),
      };
    }

    /// حركةُ الخزنة الوحيدة التي يُفترض أن يتركها مرتجعٌ نقديٌّ كامل
    /// (‏لا عميلَ على الفاتورة ⇒ لا حركةَ AR إضافية).
    Future<SafeTransactionData> refundTxnFor(SalesInvoiceData invoice) async {
      final rows = await (db.select(db.safeTransactions)
            ..where((t) =>
                t.referenceType.equals('sales_return') &
                t.referenceId.equals(invoice.id) &
                t.category.equals('sales_return')))
          .get();
      expect(rows, hasLength(1),
          reason:
              'مرتجعٌ نقديٌّ كاملٌ بلا عميلٍ يجب أن يترك حركةَ خزنةٍ واحدةً '
              'بفئة sales_return');
      return rows.single;
    }

    test(
        'كاشيرٌ بورديةٍ مفتوحةٍ في فرعٍ له درجُه — الحركةُ تقع على درج الفرع '
        'لا على الخزنة العامّة', () async {
      final invoice = await makeOriginalSale();

      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(name: 'فرع السلك ١'),
          );
      final drawerSafeId = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'درج فرع السلك ١',
              safeType: const Value('cash'),
              branchId: Value(branchId),
            ),
          );
      final cashierId = await createCashier('wire_cashier_1');
      await db.into(db.shifts).insert(
            ShiftsCompanion.insert(
              startTime: DateTime.now(),
              userId: cashierId,
              status: 'open',
              branchId: Value(branchId),
            ),
          );

      final items = await db.getSalesInvoiceItems(invoice.id);
      final ok = await repo.processSalesReturn(
        invoice: invoice,
        returnQuantities: {items.first.id: 1},
        productCache: await productCacheFor(),
        userId: cashierId,
        userName: 'Wire Cashier 1',
      );
      expect(ok, isTrue);

      final txn = await refundTxnFor(invoice);
      expect(txn.safeId, drawerSafeId,
          reason: 'المرتجعُ يجب أن يصرف من درج الفرع لا من الخزنة العامّة '
              '(‏«صندوق الكاشير» أو «الصندوق الرئيسي» المزروعتَين)');
    });

    test(
        'ورديةٌ بفرعٍ null (مديرُ نظامٍ بلا سقوطٍ في الفتح) — السقوطُ إلى '
        'فرع المستخدم لا إلى الخزنة العامّة', () async {
      // Critical (جولة مراجعة ١): `BranchScope.fullAccess()` يعطي
      // primaryBranchId=null، و`app_main_screen.dart:1390-1401` يفتح
      // الورديةَ بهذا الـnull بلا سقوطٍ احتياطيّ. تمريرُ null إلى
      // `getCashSafesForBranch` القديمة كان يتوسّع لخزائن **كلّ** الفروع
      // ويختار «الصندوق الرئيسي» (يسبق «صندوق الكاشير» أبجدياً) بدل خزنة
      // فرع المستخدم الحقيقية.
      final invoice = await makeOriginalSale();

      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(name: 'فرع السلك ٢'),
          );
      final drawerSafeId = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'درج فرع السلك ٢',
              safeType: const Value('cash'),
              branchId: Value(branchId),
            ),
          );
      final cashierId = await createCashier('wire_cashier_2');
      await db.setUserBranchAccess(cashierId, [branchId]);
      // الورديةُ تُفتح بلا فرعٍ — branchId غيرُ ممرَّرٍ فيبقى null.
      await db.into(db.shifts).insert(
            ShiftsCompanion.insert(
              startTime: DateTime.now(),
              userId: cashierId,
              status: 'open',
            ),
          );

      final items = await db.getSalesInvoiceItems(invoice.id);
      final ok = await repo.processSalesReturn(
        invoice: invoice,
        returnQuantities: {items.first.id: 1},
        productCache: await productCacheFor(),
        userId: cashierId,
        userName: 'Wire Cashier 2',
      );
      expect(ok, isTrue);

      final txn = await refundTxnFor(invoice);
      expect(txn.safeId, drawerSafeId,
          reason: 'shift.branchId=null يجب أن يسقط إلى فرع المستخدم '
              '(‏getUserBranchId) لا إلى الخزنة العامّة');
    });

    test('فرعٌ فيه خزنتان نقديتان — الاختيارُ بالخزنة الأكثر حركةً في الوردية',
        () async {
      final invoice = await makeOriginalSale();

      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(name: 'فرع السلك ٣'),
          );
      final safeLow = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'أ - درجٌ أقلّ حركة',
              safeType: const Value('cash'),
              branchId: Value(branchId),
            ),
          );
      final safeHigh = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'ب - درجٌ أكثر حركة',
              safeType: const Value('cash'),
              branchId: Value(branchId),
            ),
          );
      final cashierId = await createCashier('wire_cashier_3');
      final shiftStart = DateTime.now();
      await db.into(db.shifts).insert(
            ShiftsCompanion.insert(
              startTime: shiftStart,
              userId: cashierId,
              status: 'open',
              branchId: Value(branchId),
            ),
          );
      // حركتان فعليتان للكاشير في هذه الوردية، بمبلغَين مختلفَين — الدرجُ
      // الأكثر حركةً (٥٠) يجب أن يفوز على الأقلّ (٣٠)، بصرف النظر عن اسم
      // الخزنة أو ترتيب إنشائها.
      await db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: 'SALE-WIRE-3-LOW',
              safeId: safeLow,
              transactionType: 'receipt',
              category: 'sales',
              amount: 30,
              balanceAfter: 30,
              userId: Value(cashierId),
              createdAt: Value(shiftStart.add(const Duration(minutes: 1))),
            ),
          );
      await db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: 'SALE-WIRE-3-HIGH',
              safeId: safeHigh,
              transactionType: 'receipt',
              category: 'sales',
              amount: 50,
              balanceAfter: 50,
              userId: Value(cashierId),
              createdAt: Value(shiftStart.add(const Duration(minutes: 2))),
            ),
          );

      final items = await db.getSalesInvoiceItems(invoice.id);
      final ok = await repo.processSalesReturn(
        invoice: invoice,
        returnQuantities: {items.first.id: 1},
        productCache: await productCacheFor(),
        userId: cashierId,
        userName: 'Wire Cashier 3',
      );
      expect(ok, isTrue);

      final txn = await refundTxnFor(invoice);
      expect(txn.safeId, safeHigh,
          reason: 'الاختيارُ بالحركة الفعلية للوردية (٥٠ > ٣٠) لا بترتيب '
              'اسم الخزنة أو رقم إنشائها');
    });

    test(
        'غيابُ ورديةٍ أصلاً — نفسُ سلوك الخزنة الافتراضية العامّة القديم '
        'بالضبط (لا انحدار)', () async {
      final cashierId = await createCashier('wire_cashier_4');
      // لا وردية مفتوحة لهذا المستخدم إطلاقاً.

      final expectedDefault = await db.getDefaultSafeByType('cash');
      expect(expectedDefault, isNotNull);

      final invoice = await makeOriginalSale();
      final items = await db.getSalesInvoiceItems(invoice.id);
      final ok = await repo.processSalesReturn(
        invoice: invoice,
        returnQuantities: {items.first.id: 1},
        productCache: await productCacheFor(),
        userId: cashierId,
        userName: 'Wire Cashier 4',
      );
      expect(ok, isTrue);

      final txn = await refundTxnFor(invoice);
      expect(txn.safeId, expectedDefault!.id,
          reason:
              'بلا وردية مفتوحة، السلوكُ القديم (الخزنة الافتراضية العامّة) '
              'يجب أن يبقى كما هو بالضبط — هذا هو خطُّ الأساس الذي لا يجوز '
              'كسرُه.');

      // جولةُ مراجعةٍ ١ — «مطابقةُ المواصفة»: كلُّ سقوطٍ إلى الخزنة
      // الافتراضية العامّة يجب أن يُسجَّل فعلياً، لا أن يبقى مجرّد تعليقٍ.
      expect(
        DiagnosticLogger.testLog
            .any((line) => line.contains('REFUND-SAFE-FALLBACK')),
        isTrue,
        reason: 'سقوطُ resolveRefundSafe إلى الخزنة العامّة (بلا وردية '
            'مفتوحة) يجب أن يترك سطرَ DiagnosticLogger كي يظهر لمراجع.',
      );
    });
  });
}

// ── Collaborator stubs — مطابقةٌ لِمَا في sales_return_wac_gl_drift_test.dart
// (نفسُ نمط الإسكات: أيُّ نداءٍ غيرِ متوقَّعٍ يرمي بدل أن يمرّ صامتاً) ──────

class _StubPartiesRepo implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubTreasuryRepo implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
          String referenceType, int referenceId) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubProductRepo implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubInventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubSettingsRepo implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubAuditRepo implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}
