// إعادة محاولة قيود الترحيل التلقائي الفاشلة (R1 / T1).
//
// مسار الحفظ (`createSalesInvoice` Phase 8) يكتب صفاً في `failed_autoposts` عند
// فشل قيد البيع/المرتجع بعد تثبيت المخزون والخزنة، ولم يكن أحد يقرأ الجدول.
// هذه الدالة تقرؤه وتعيد الترحيل بالدوال القائمة نفسها (لا منطق محاسبي مكرر).
//
// لا أعمدة جديدة: عدّاد المحاولات يُحفظ كبادئة `[attempts=N]` في `error_message`
// (يحمل آخر خطأ بعدها)، والحل يُعلَّم بـ`is_resolved/resolved_at`.
part of 'database.dart';

/// السقف الأعلى لمحاولات الصف الواحد قبل أن يُترك للمراجعة اليدوية.
const int kFailedAutopostMaxAttempts = 5;

final RegExp _attemptsPrefix = RegExp(r'^\[attempts=(\d+)\]\s*');

int _attemptsOf(String message) {
  final m = _attemptsPrefix.firstMatch(message);
  return m == null ? 0 : int.parse(m.group(1)!);
}

String _withAttempts(int attempts, String error) =>
    '[attempts=$attempts] ${error.replaceFirst(_attemptsPrefix, '')}';

/// نتيجة جولة إعادة المحاولة.
class FailedAutopostRetryResult {
  final int resolved;
  final int failed;
  final int skippedAtCap;
  const FailedAutopostRetryResult(this.resolved, this.failed, this.skippedAtCap);
}

extension FailedAutopostRetry on AppDatabase {
  /// يعيد ترحيل صفوف `failed_autoposts` غير المحلولة. لا يرمي أبداً.
  Future<FailedAutopostRetryResult> retryFailedAutoposts({
    int limit = 50,
    int maxAttempts = kFailedAutopostMaxAttempts,
  }) async {
    var resolved = 0, failed = 0, capped = 0;
    List<FailedAutopost> rows;
    try {
      rows = await (select(failedAutoposts)
            ..where((f) => f.isResolved.equals(false) & f.deletedAt.isNull())
            ..orderBy([(f) => OrderingTerm.asc(f.id)])
            ..limit(limit))
          .get();
    } catch (e) {
      debugPrint('[AUTOPOST-RETRY] read failed: $e');
      return const FailedAutopostRetryResult(0, 0, 0);
    }

    for (final row in rows) {
      final attempts = _attemptsOf(row.errorMessage);
      if (attempts >= maxAttempts) {
        capped++;
        continue;
      }
      try {
        await _repostOne(row);
        await _markResolved(row.id);
        resolved++;
      } catch (e) {
        failed++;
        debugPrint('[AUTOPOST-RETRY] ${row.referenceType} #${row.invoiceId}: $e');
        try {
          await (update(failedAutoposts)..where((f) => f.id.equals(row.id)))
              .write(FailedAutopostsCompanion(
            errorMessage: Value(_withAttempts(attempts + 1, e.toString())),
            lastModifiedAt: Value(DateTime.now()),
          ));
        } catch (logErr) {
          debugPrint('[AUTOPOST-RETRY] could not record failure: $logErr');
        }
      }
    }
    if (rows.isNotEmpty) {
      debugPrint('[AUTOPOST-RETRY] resolved=$resolved failed=$failed '
          'atCap=$capped');
    }
    return FailedAutopostRetryResult(resolved, failed, capped);
  }

  Future<void> _markResolved(int id) =>
      (update(failedAutoposts)..where((f) => f.id.equals(id))).write(
        FailedAutopostsCompanion(
          isResolved: const Value(true),
          resolvedAt: Value(DateTime.now()),
          lastModifiedAt: Value(DateTime.now()),
        ),
      );

  /// يرمي عند الفشل؛ يعود بسلام إذا القيد موجود (قبل أو بعد) أو الفاتورة محذوفة.
  Future<void> _repostOne(FailedAutopost row) async {
    final id = row.invoiceId;
    switch (row.referenceType) {
      case 'sale':
      case 'sales_invoice':
        if (await hasAutoPostEntry('sale', id) ||
            await hasAutoPostEntry('sales_invoice', id)) {
          return;
        }
        final sale = await _loadSale(id);
        if (sale == null) return;
        final isFullCredit = sale.paymentMethod == 'credit' ||
            (sale.total - sale.paid > 0.01 && sale.paid == 0);
        if (isFullCredit) {
          await autoPostCreditSale(sale, costCenterId: sale.costCenterId);
        } else {
          await autoPostCashSale(sale, costCenterId: sale.costCenterId);
        }
        if (!(await hasAutoPostEntry('sale', id) ||
            await hasAutoPostEntry('sales_invoice', id))) {
          throw StateError('لم يُنشأ قيد البيع #$id');
        }
      case 'sales_return':
        // مرتجع البيع السريع: الفاتورة نفسها هي «الأصل» في المسار الأصلي.
        if (await hasAutoPostEntry('sales_return', id)) return;
        final ret = await _loadSale(id);
        if (ret == null) return;
        await _repostQuickReturn(ret);
        if (!await hasAutoPostEntry('sales_return', id)) {
          throw StateError('لم يُنشأ قيد المرتجع #$id');
        }
      case 'purchase':
      case 'purchase_invoice':
        if (await hasAutoPostEntry('purchase', id) ||
            await hasAutoPostEntry('purchase_invoice', id)) {
          return;
        }
        final purchase = await (select(purchaseInvoices)
              ..where((p) => p.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
        if (purchase == null) return;
        await autoPostPurchase(purchase, costCenterId: purchase.costCenterId);
        if (!(await hasAutoPostEntry('purchase', id) ||
            await hasAutoPostEntry('purchase_invoice', id))) {
          throw StateError('لم يُنشأ قيد الشراء #$id');
        }
      default:
        throw StateError('نوع مرجع غير مدعوم: ${row.referenceType}');
    }
  }

  Future<SalesInvoiceData?> _loadSale(int id) =>
      (select(salesInvoices)
            ..where((i) => i.id.equals(id) & i.isDeleted.equals(false))
            ..limit(1))
          .getSingleOrNull();

  /// يعيد بناء مبالغ المرتجع من صف الفاتورة نفسه (cashPaid/bankPaid/tax/البنود)
  /// بنفس معادلات `createSalesInvoice` Phase 8، ثم يستدعي `autoPostSalesReturn`.
  Future<void> _repostQuickReturn(SalesInvoiceData ret) async {
    final pm = ret.paymentMethod;
    final isSplit = pm == 'multiple' || pm == 'mixed';
    final cashRefund = pm == 'cash' ? ret.paid : (isSplit ? ret.cashPaid : 0.0);
    final bankRefund =
        isBankPaymentMethod(pm) ? ret.paid : (isSplit ? ret.bankPaid : 0.0);
    final arRefund = (ret.total - ret.paid).clamp(0.0, double.infinity);
    final items = await (select(salesInvoiceItems)
          ..where((i) => i.invoiceId.equals(ret.id)))
        .get();
    final cogs = items.fold<double>(
        0.0, (s, i) => s + i.costPrice * i.quantity * i.quantityInBase);
    await autoPostSalesReturn(
      originalInvoice: ret,
      returnAmount: ret.total,
      cogsAmount: cogs,
      cashRefund: cashRefund,
      bankRefund: bankRefund,
      arRefund: arRefund,
      vatAmount: ret.tax,
      costCenterId: ret.costCenterId,
    );
  }
}
