part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// توزيعُ مبلغِ السند على الفواتير — `Payments` + `PaymentAllocations`
// ═══════════════════════════════════════════════════════════════════════════
//
// ═══ 🔴 سجلٌّ لا حركةُ مال ═══
//
// سندُ القبض/الصرف **قيَّد المالَ سلفاً**: `createReceiptVoucher` يحرّك
// الخزنةَ ويكتب قيدَ Dr Safe / Cr Customer ويحدّث `parties.balance`. وهذه
// الدالّةُ تسجّل **أين ذهب** ذلك المبلغ بين فواتيره — ولا تُنشئ قيداً ولا
// حركةَ خزنةٍ ولا تمسّ رصيدَ الطرف.
//
// ومَن يضيف هنا نداءً إلى `createReceiptVoucher` أو `createJournalEntry`
// يُنتج **ازدواجاً في المال**: الخزنةُ تزيد مرّتين والعميلُ يُقيَّد مرّتين،
// والقيدان متّزنان فلا فحصَ اتّزانٍ يمسك شيئاً.
//
// ═══ 🔴 ولا تُنادى في وضع العميل ═══
//
// المعرّفاتُ هنا `autoIncrement` محلّيّة، والاستراتيجيّتان تكتبان صفوفَ
// الخادم **بمعرّفاته** (`id: Value(parseInt(map['id']))`) عبر
// `insertOnConflictUpdate`. فصفٌّ محلّيٌّ برقمٍ يصادف رقمَ صفٍّ على الخادم
// يُستبدَل به صامتاً — ويذهب تخصيصُ المستخدم.
//
// و`ClientWriteInterceptor.createReceipt` لا تحمل قائمةَ الفواتير أصلاً،
// فالخادمُ لا يعرف اختيارَ المستخدم. ⇒ المنادي يمرّر `voucherRowId` الذي
// يعود من الكتابة **المحلّيّة**، وهو صفرٌ في وضع العميل — وعندها لا يُنادى.
//
// ═══ ⚠️ والثابتُ الذي تحفظه ═══
//
//     paid = paid_unallocated + Σ payment_allocations
//
// فهي ترفع `paid` بقدر التخصيص و**لا تمسّ** `paid_unallocated` — وذلك
// بالضبط ما يجعل إعادةَ الحساب في `PaymentAllocationSyncStrategy` تُرجع
// نفسَ الرقم بدل أن تمحو ما دُفع عند البيع.

/// تخصيصُ مبلغٍ لفاتورةٍ بعينها.
typedef VoucherAllocationInput = ({
  /// `sales` أو `purchase` — مفرداتُ `PaymentAllocations.invoiceType`.
  String invoiceType,
  int invoiceId,
  double amount,
});

extension PaymentAllocationsDao on AppDatabase {
  /// يسجّل دفعةً واحدةً وتوزيعَها على فواتيرها.
  ///
  /// يُرجع معرّفَ صفِّ `Payments`.
  ///
  /// 🔴 **بلا حركةِ مالٍ ثانية** — راجع رأسَ الملفّ.
  Future<int> recordVoucherAllocations({
    required String paymentNumber,
    required DateTime paymentDate,
    required double amount,
    required String paymentMethod,
    required int safeId,

    /// `receipt` = سند قبض · `payment` = سند صرف.
    required String paymentType,
    required List<VoucherAllocationInput> allocations,
    int? partyId,
    int? userId,
    int? safeTransactionId,
    String? notes,
    String? globalId,
  }) async {
    if (allocations.isEmpty) {
      throw ArgumentError('لا فواتيرَ لتوزيع المبلغ عليها.');
    }
    for (final a in allocations) {
      if (a.amount <= 0) {
        throw ArgumentError(
          'مبلغُ التخصيص للفاتورة #${a.invoiceId} يجب أن يكون أكبر من صفر.',
        );
      }
      if (a.invoiceType != 'sales' && a.invoiceType != 'purchase') {
        throw ArgumentError('نوعُ فاتورةٍ غيرُ معروف: ${a.invoiceType}');
      }
    }

    // 🔴 **المجموعُ لا يتجاوز مبلغَ السند.** تخصيصٌ أكبرُ من المقبوض يُقفل
    //    فواتيرَ بمالٍ لم يُقبَض، ويخالف السندُ مجموعَ تخصيصاته فلا تعود
    //    المطابقةُ ممكنة. والمقارنةُ بالوحدات الصغرى لا بالكسر العائم.
    final allocatedMinor = allocations.fold<int>(
      0,
      (s, a) => s + FinancialUtils.toMinorUnits(a.amount),
    );
    if (allocatedMinor > FinancialUtils.toMinorUnits(amount)) {
      throw StateError(
        'مجموعُ التوزيع يتجاوز مبلغَ السند — وزّع ما لا يزيد عليه.',
      );
    }

    return transaction(() async {
      final paymentId = await into(payments).insert(
        PaymentsCompanion.insert(
          paymentNumber: paymentNumber,
          paymentDate: paymentDate,
          amount: amount,
          safeId: safeId,
          paymentType: paymentType,
          paymentMethod: Value(paymentMethod),
          partyId: Value(partyId),
          userId: Value(userId),
          safeTransactionId: Value(safeTransactionId),
          notes: Value(notes),
          globalId: Value(globalId ?? UuidV7.generate()),
        ),
      );

      for (final a in allocations) {
        await into(paymentAllocations).insert(
          PaymentAllocationsCompanion.insert(
            paymentId: paymentId,
            invoiceType: a.invoiceType,
            invoiceId: a.invoiceId,
            allocatedAmount: a.amount,
            globalId: Value(UuidV7.generate()),
          ),
        );
        await _advanceInvoicePaid(a);
      }

      markTablesUpdated({payments, paymentAllocations, salesInvoices});
      return paymentId;
    });
  }

  /// يرفع مسدَّدَ الفاتورة بقدر التخصيص — **وحدَه، بلا قاعدة**.
  ///
  /// ⚠️ **ولا يُنادى `updateSalesInvoicePaidAmount` — والسببُ الترتيبُ لا
  /// الحساب.** ذاك يُعيد حسابَ القاعدة `base = newPaid − Σ`، وهو يعطي هنا
  /// **نفسَ** النتيجة ما دام صفُّ التخصيص قد أُدرج قبله في الحلقة أعلاه.
  ///
  /// وقد جُرّب: طفرةُ استبداله **نجت** من السويّة كاملةً — لأنّ الصيغتَين
  /// متكافئتان بهذا الترتيب بالضبط. فلو عُكس السطران يوماً (إدراجٌ بعد
  /// الرفع) لصارت القاعدةُ `paid − 0` عند الأولى ثمّ `0` بالقصّ، ويعود
  /// المسدَّدُ إلى مجموع التخصيصات وحدَه عند أوّل إعادةِ حساب — أي **عينُ
  /// العطب** الذي بُني العمودُ لأجله.
  ///
  /// والكتابةُ المباشرةُ هنا لا تعتمد على ترتيبٍ إطلاقاً: ترفع `paid` بقدر
  /// التخصيص وتترك `paid_unallocated` كما هو.
  Future<void> _advanceInvoicePaid(VoucherAllocationInput a) async {
    if (a.invoiceType == 'sales') {
      final inv = await (select(salesInvoices)
            ..where((i) => i.id.equals(a.invoiceId)))
          .getSingleOrNull();
      if (inv == null) {
        throw StateError('لا فاتورةَ مبيعاتٍ بالرقم #${a.invoiceId}.');
      }
      final newPaid = inv.paid + a.amount;
      // 🔴 **ولا يتجاوز إجماليَّ الفاتورة**: فاتورةٌ «مدفوعةٌ أكثرَ من
      //    قيمتها» تُنتج رصيداً دائناً للعميل في تقريرٍ وتُقرأ خطأَ إدخالٍ
      //    في آخر — والفائضُ سندُ دفعةٍ مقدَّمةٍ لا تخصيصُ فاتورة.
      if (FinancialUtils.toMinorUnits(newPaid) >
          FinancialUtils.toMinorUnits(inv.total)) {
        throw StateError(
          'التخصيصُ يتجاوز باقيَ الفاتورة ${inv.invoiceNumber} '
          '(الباقي ${(inv.total - inv.paid).toStringAsFixed(2)}).',
        );
      }
      final status = FinancialUtils.toMinorUnits(newPaid) >=
              FinancialUtils.toMinorUnits(inv.total)
          ? 'paid'
          : 'partial';
      await (update(salesInvoices)..where((i) => i.id.equals(a.invoiceId)))
          .write(SalesInvoicesCompanion(
        paid: Value(newPaid),
        status: Value(status),
      ));
    } else {
      final inv = await (select(purchaseInvoices)
            ..where((i) => i.id.equals(a.invoiceId)))
          .getSingleOrNull();
      if (inv == null) {
        throw StateError('لا فاتورةَ مشترياتٍ بالرقم #${a.invoiceId}.');
      }
      final newPaid = inv.paid + a.amount;
      if (FinancialUtils.toMinorUnits(newPaid) >
          FinancialUtils.toMinorUnits(inv.total)) {
        throw StateError(
          'التخصيصُ يتجاوز باقيَ فاتورة المشتريات #${inv.id} '
          '(الباقي ${(inv.total - inv.paid).toStringAsFixed(2)}).',
        );
      }
      final status = FinancialUtils.toMinorUnits(newPaid) >=
              FinancialUtils.toMinorUnits(inv.total)
          ? 'paid'
          : 'partial';
      await (update(purchaseInvoices)..where((i) => i.id.equals(a.invoiceId)))
          .write(PurchaseInvoicesCompanion(
        paid: Value(newPaid),
        status: Value(status),
      ));
    }
  }
}
