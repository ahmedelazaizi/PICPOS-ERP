// قفلُ تبديل العملة بعد أوّل حركةٍ ماليّة — قرارُ المالك 2026-08-23.
//
// ── لماذا يُقفَل أصلاً (م-٢ من مواصفة دقّة العملة) ─────────────────────────
// دقّةُ العملة صارت تتبع العملةَ: الدينارُ ٣ خاناتٍ والجنيهُ ٢. والتبديلُ
// متاحٌ من شاشة الإعدادات **في أيّ وقت**. فمبلغٌ مخزَّنٌ `12.345` يصير عند
// إعادة الحساب `12.35`، وقيدٌ مرحَّلٌ اتّزن بثلاث خاناتٍ قد **يختلّ**
// بخانتين — والسماحُ نفسُه يضيق من ١٠ وحداتٍ صغرى إلى **١**.
//
// فالعملةُ قرارُ تنصيبٍ لا تفضيلُ عرض: تُختار في معالج البدء بحرّية، وتُقفَل
// بمجرّد أن يقع أوّلُ أثرٍ ماليّ.
//
// ⚠️ والحارسُ في طبقتين عن قصد: المنتقي يُعطَّل في الواجهة، **و**الدالّةُ
//    نفسُها ترفض. الواجهةُ وحدَها تُلتَفّ (استدعاءٌ برمجيّ، مزامنة، سكربت).
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/data/providers/providers.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async {
    AppConstants.setCurrency('JOD');
    await db.close();
  });

  group('قاعدةٌ طازجةٌ ليست «حركةً ماليّة»', () {
    test('قاعدةٌ مزروعةٌ حديثاً ⇒ لا حركةَ ⇒ التبديلُ مسموح', () async {
      // ⚠️ هذا الحارسُ يقيس فرضيّةً لا يجوز افتراضُها: لو زرع الإقلاعُ قيداً
      // واحداً (أرصدةٌ افتتاحيّةٌ مثلاً) لانقفلت العملةُ **قبل** أن يصل
      // المستخدمُ إلى معالج البدء — فيُولد النظامُ ولا يمكن اختيارُ عملته.
      expect(await db.hasAnyFinancialMovement(), isFalse);
    });
  });

  group('أوّلُ أثرٍ ماليٍّ يقفل', () {
    test('فاتورةُ مبيعاتٍ تقفل', () async {
      await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'SINV-LOCK',
              warehouseId: 1,
              userId: 1,
              invoiceDate: DateTime(2026, 8, 23),
              total: const Value(10),
            ),
          );
      expect(await db.hasAnyFinancialMovement(), isTrue);
    });

    test('فاتورةُ مشترياتٍ تقفل', () async {
      await db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: 'PINV-LOCK',
              supplierId: 1,
              warehouseId: 1,
              invoiceDate: DateTime(2026, 8, 23),
              total: const Value(10),
            ),
          );
      expect(await db.hasAnyFinancialMovement(), isTrue);
    });

    test('حركةُ خزنةٍ تقفل', () async {
      await db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: 'RCPT-LOCK',
              safeId: 1,
              transactionType: 'receipt',
              category: 'sales',
              amount: 10,
              balanceAfter: 10,
            ),
          );
      expect(await db.hasAnyFinancialMovement(), isTrue);
    });

    test('المزوِّدُ نفسُه يرفض — لا الواجهةُ وحدَها', () async {
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(systemCurrencyProvider.notifier);

      // قبل أيّ حركة: التبديلُ يمرّ.
      await notifier.setCurrency('EGP');
      expect(AppConstants.decimalPlaces, 2);

      await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'SINV-GUARD',
              warehouseId: 1,
              userId: 1,
              invoiceDate: DateTime(2026, 8, 23),
              total: const Value(10),
            ),
          );

      await expectLater(
        notifier.setCurrency('JOD'),
        throwsA(isA<StateError>()),
        reason: 'الواجهةُ تُلتَفّ باستدعاءٍ برمجيّ — الحارسُ عند الكتابة',
      );
      expect(AppConstants.decimalPlaces, 2,
          reason: 'الرفضُ لا يترك الدقّةَ نصفَ مبدَّلة');
    });

    test('تبديلٌ إلى نفس العملة يمرّ ولو بعد حركة', () async {
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'SINV-SAME',
              warehouseId: 1,
              userId: 1,
              invoiceDate: DateTime(2026, 8, 23),
              total: const Value(10),
            ),
          );
      // ليس تبديلاً أصلاً، فلا يُرفَض.
      await expectLater(
        container.read(systemCurrencyProvider.notifier).setCurrency('JOD'),
        completes,
      );
    });

    test('الصفُّ المحذوفُ منطقيّاً لا يقفل', () async {
      await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'SINV-DEL',
              warehouseId: 1,
              userId: 1,
              invoiceDate: DateTime(2026, 8, 23),
              total: const Value(10),
              isDeleted: const Value(true),
            ),
          );
      expect(await db.hasAnyFinancialMovement(), isFalse,
          reason: 'فاتورةٌ ملغاةٌ ليست أثراً ماليّاً قائماً');
    });
  });
}
