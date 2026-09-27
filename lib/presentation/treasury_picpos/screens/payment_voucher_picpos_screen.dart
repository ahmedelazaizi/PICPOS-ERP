// شاشةُ «سند صرف» — تصميمُ المالك `(11)`.
//
// ═══ ⚠️ مسارُ المال **منقولٌ** من الحوار لا مُعادُ كتابته ═══
//
// كما في شاشة القبض: الكتابةُ المزدوجةُ عبر `ClientWriteInterceptor`،
// ونسبةُ الفرع إلى فرع المشغِّل (‏مواصفة ١٣٥ BUG-C)، و**إسقاطُ الخزنة
// للشيك** (`safeId: null`) لأنّ الشيكَ لا يدخل درجاً — القيدُ يملكه
// ترحيلُ الأوراق التجارية.
//
// ═══ 🔴 وما أُصلح أثناء النقل: مبلغُ كلِّ شيكٍ يُكتَب ولا يُقسَّم ═══
//
// راجع رأسَ `voucher_form_picpos.dart`: `amount / count` كانت تخترع مبالغَ
// الشيكات، والمجموعُ وحدَه صحيح.
//
// ═══ ✅ وما وصل الآن: الرقمُ يُسحَب من دفترٍ لا يُكتَب بيد (v175) ═══
//
// الحوارُ كان يسمح بانتقاء ورقةٍ **قائمةٍ** من قائمة `commercial_papers` —
// وهي حيلةٌ لغياب الدفتر: المستخدمُ يُنشئ الشيكاتِ يدويّاً في «إدارة
// الشيكات» ثمّ ينتقيها هنا. ومع `ChequeBooks` صار المسارُ الصحيحُ متاحاً:
// يُختار الدفترُ فتُسحَب أرقامُه **داخلَ معاملة** وتُكتَب على الورقة مع
// `cheque_book_id`.
//
// ⚠️ **والكتابةُ بيدٍ تبقى ممكنة**: دفاترُ قديمةٌ لم تُسجَّل، وشيكٌ مصرفيٌّ
//    من غير دفترنا. ومنعُها كان يوقف الصرفَ حتى يُسجَّل كلُّ دفترٍ في الدرج.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/utils/uuid_v7.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/cheque_book_plan.dart';
import '../../../services/client_write_interceptor.dart';
import '../../widgets/permission_guard.dart';
import 'cheque_books_picpos_screen.dart' show chequeBooksListProvider;
import 'receipt_voucher_picpos_screen.dart' show voucherOpenInvoicesProvider;
import 'voucher_form_picpos.dart';

final _costCentersProvider = FutureProvider.autoDispose<List<CostCenter>>(
    (ref) => ref.watch(accountingRepositoryProvider).getActiveCostCenters());

class PaymentVoucherPicposScreen extends ConsumerStatefulWidget {
  const PaymentVoucherPicposScreen({super.key});

  @override
  ConsumerState<PaymentVoucherPicposScreen> createState() =>
      _PaymentVoucherPicposScreenState();
}

class _PaymentVoucherPicposScreenState
    extends ConsumerState<PaymentVoucherPicposScreen> {
  bool _busy = false;
  int? _partyId;

  /// عدّادُ تجديد الاستمارة — تبديلُه يُعيد بناءَ `PicPosVoucherForm` بحالةٍ
  /// نظيفة. راجع `finishVoucherSave` في `voucher_form_picpos.dart`.
  int _formEpoch = 0;

  /// الأرقامُ التي سُحبت فعلاً في هذه المحاولة — تُقال في رسالة الفشل.
  List<int> _drawn = const [];

  @override
  Widget build(BuildContext context) {
    final parties = ref.watch(allPartiesProvider).value ?? const <Party>[];
    final safes = ref.watch(scopedSafesProvider).value ?? const [];
    final costCenters =
        ref.watch(_costCentersProvider).value ?? const <CostCenter>[];

    final invoices = _partyId == null
        ? const <VoucherInvoiceOption>[]
        : ref
                .watch(voucherOpenInvoicesProvider(
                    (partyId: _partyId!, supplier: true)))
                .value ??
            const <VoucherInvoiceOption>[];

    return PermissionGuard(
      // ⚠️ راجع نظيرَه في شاشة القبض: `treasury_payments_create` غيرُ
      //    ممنوحٍ لأيّ دور، فربطُ الشاشة به يسحبها من الجميع.
      permission: PermissionCodes.treasuryView,
      child: PicPosVoucherForm(
        key: ValueKey(_formEpoch),
        kind: PicPosVoucherKind.payment,
        parties: [
          for (final p in parties)
            if (p.isSupplier)
              (
                id: p.id,
                name: p.name,
                meta: p.phone,
                isDeliveryCompany: p.isDeliveryCompany,
              ),
        ],
        safes: [
          for (final s in safes) (id: s.id, name: s.name, type: s.safeType),
        ],
        costCenters: [
          for (final c in costCenters) (id: c.id, name: c.name),
        ],
        openInvoices: invoices,
        chequeBooks: _bookOptions(),
        busy: _busy,
        onPartyPicked: (id) => setState(() => _partyId = id),
        onCancel: _finish,
        onSubmit: _save,
      ),
    );
  }

  /// الدفاترُ الصالحةُ للسحب — **السارية وحدَها**.
  ///
  /// ⚠️ الملغى والمنتهي يُقصيان هنا لا في المحرّك وحدَه: خيارٌ يُعرَض ثمّ
  ///    يُرفَض عند الحفظ بعد أن مُلئ السندُ كلُّه وعدٌ كاذب.
  List<VoucherChequeBookOption> _bookOptions() {
    final books =
        ref.watch(chequeBooksListProvider).value ?? const <ChequeBookData>[];
    return [
      for (final b in books)
        if (b.status == 'active' &&
            chequesRemaining(nextNumber: b.nextNumber, toNumber: b.toNumber) >
                0)
          (
            id: b.id,
            label: b.bookNumber,
            prefix: b.prefix,
            nextNumber: b.nextNumber,
            toNumber: b.toNumber,
            remaining: chequesRemaining(
                nextNumber: b.nextNumber, toNumber: b.toNumber),
          ),
    ];
  }

  Future<void> _save(VoucherSubmission v) async {
    if (_busy) return;
    setState(() => _busy = true);
    _drawn = const [];
    try {
      final amount = v.grossAmount;

      // 🔴 **السحبُ أوّلاً وفي معاملةٍ واحدة.** الأرقامُ التي عاينها النموذجُ
      //    قد تكون بطُلت — جهازٌ آخرُ سحب قبله — فالحكمُ لما تُرجعه
      //    `allocateChequeNumbers` لا لما عُرض.
      //
      // ⚠️ **وقبل أيّ كتابةٍ ماليّة**: الأرقامُ تدخل وصفَ السند وأرقامَ
      //    الأوراق معاً، فسحبٌ بعدَها كان يترك سنداً يصف أرقاماً غيرَ التي
      //    كُتبت.
      final numbers = await _drawNumbers(v);
      final allCheckNumbers = numbers.join(', ');
      var description =
          v.notes.isEmpty ? 'دفع لمورد' : v.notes;
      if (v.method == 'check') {
        description += ' | شيك رقم: $allCheckNumbers';
      }

      // Spec 135 BUG-C — فرعُ المشغِّل لا فرعُ الخزنة.
      final operatingBranchId = ref.read(activeBranchIdProvider).value;

      // ⚠️ **الخزنةُ تُسقَط للشيك** (`safeId: null`): الشيكُ لا يدخل درجاً،
      //    والقيدُ يملكه ترحيلُ الأوراق التجارية. وتمريرُها كان يُخرج
      //    نقديّةً مرّتين.
      final intercepted = await ClientWriteInterceptor.createExpense(
        amount: amount,
        category: 'supplier_payment',
        description: description,
        partyId: v.partyId,
        safeId: v.method == 'check' ? null : v.safeId,
        branchId: operatingBranchId,
        costCenterId: v.costCenterId,
        paperType: v.method == 'check' ? 'cheque' : null,
      );

      int voucherRowId = 0;
      if (intercepted == null) {
        voucherRowId =
            await ref.read(treasuryRepositoryProvider).createPaymentVoucher(
                  amount: amount,
                  discount: v.discount,
                  category: 'supplier_payment',
                  safeId: v.method == 'check' ? null : v.safeId,
userId: ref.read(authProvider).user?.id,
                   manualEntry: true,
                  partyId: v.partyId,
                  description: description,
                  costCenterId: v.costCenterId,
                  paperNumber: v.method == 'check' ? allCheckNumbers : null,
                  paperType: v.method == 'check' ? 'cheque' : null,
                  paperBankName:
                      v.method == 'check' ? v.cheques.first.bank : null,
                  paperDueDate:
                      v.method == 'check' ? v.cheques.first.dueDate : null,
                  paperIssueDate:
                      v.method == 'check' ? DateTime.now() : null,
                  operatingBranchId: operatingBranchId,
                );
      }

      if (v.method == 'check') {
        await _createCheques(v, voucherRowId, numbers);
      }

      await _recordAllocations(v, amount, interceptedByServer: intercepted != null);

      final user = ref.read(authProvider).user;
      await ref.read(activityLogRepositoryProvider).logActivity(
            userId: user?.id,
            userName: user?.displayName ?? 'مجهول',
            action: 'payment',
            entityType: 'payment',
            description: 'سند صرف ${v.method} بمبلغ '
                '${amount.toStringAsFixed(AppConstants.decimalPlaces)}',
            amount: amount,
          );

      if (!mounted) return;
      _toast('تم حفظ سند الصرف', ToastType.success);
      _finish();
    } catch (e) {
      // 🔴 **وما سُحب من الدفتر يُقال.** الفشلُ بعد السحب يترك أرقاماً
      //    مُستهلَكةً في الدفتر بلا شيكٍ يقابلها — ورقةٌ نُزعت وأُتلفت.
      //    وصمتٌ عنها يجعل المستخدمَ يعيد المحاولةَ ظانّاً أنّه يكتب نفسَ
      //    الرقم، ثمّ يجد فجوةً في الدفتر لا يعرف سببَها.
      final burnt = _drawn.isEmpty
          ? ''
          : ' — وقد سُحبت من الدفتر الأرقامُ ${_drawn.join('، ')} ولم '
              'تُكتَب على شيك. صحّح «التالي» من شاشة دفتر الشيكات إن لزم.';
      _toast('خطأ في الحفظ: $e$burnt', ToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 🔴 **الأرقامُ تُسحَب من الدفتر في معاملةٍ واحدة** — أو تبقى كما كتبها
  /// المستخدمُ بيده إن لم يُختَر دفتر.
  ///
  /// ⚠️ **وما سُحب لا يُردّ.** لو فشل الحفظُ بعد هذه النقطة احترقت الأرقامُ
  ///    — تماماً كورقةٍ نُزعت من الدفتر ثمّ أُتلفت. وإنقاصُ `next_number`
  ///    تعويضاً كان **أخطرَ**: جهازٌ آخرُ قد يكون سحب بعدنا، فإنقاصُنا
  ///    يُعيد إصدارَ رقمٍ في يد مورّد. ولذلك «التالي» حقلٌ محرَّرٌ في شاشة
  ///    الدفتر، والرسالةُ تقول ما احترق.
  Future<List<String>> _drawNumbers(VoucherSubmission v) async {
    final typed = [for (final c in v.cheques) c.number];
    if (v.method != 'check' || v.chequeBookId == null || v.cheques.isEmpty) {
      return typed;
    }
    final book = (ref.read(chequeBooksListProvider).value ??
            const <ChequeBookData>[])
        .where((b) => b.id == v.chequeBookId)
        .firstOrNull;
    final drawn =
        await ref.read(chequeBooksRepositoryProvider).allocateChequeNumbers(
              bookId: v.chequeBookId!,
              count: v.cheques.length,
            );
    _drawn = drawn;
    return [
      for (final n in drawn)
        formatChequeNumber(
          prefix: book?.prefix,
          number: n,
          toNumber: book?.toNumber ?? n,
        ),
    ];
  }

  /// 🔴 **بمبلغِ كلِّ شيكٍ كما كُتب** — لا قسمةً بالتساوي.
  Future<void> _createCheques(
    VoucherSubmission v,
    int voucherRowId,
    List<String> numbers,
  ) async {
    final cpRepo = ref.read(commercialPapersRepositoryProvider);
    for (var i = 0; i < v.cheques.length; i++) {
      final c = v.cheques[i];
      final number = i < numbers.length ? numbers[i] : c.number;
      final gid = UuidV7.generate();
      final dueDate =
          c.dueDate ?? DateTime.now().add(const Duration(days: 30));
      final bank = c.bank.isEmpty ? null : c.bank;
      const notes = 'ترحيل تلقائي من سند صرف';

      await ClientWriteInterceptor.createCommercialPaper(
        paperNumber: number,
        type: 'cheque',
        direction: 'issued',
        partyId: v.partyId ?? 0,
        amount: c.amount,
        issueDate: DateTime.now(),
        dueDate: dueDate,
        bankName: bank,
        accountNumber: null,
        notes: notes,
        globalId: gid,
      );
      await cpRepo.createPaper(
        sourceVoucherId: voucherRowId > 0 ? voucherRowId : null,
        // v175 — الدفترُ الذي سُحب منه الرقمُ فعلاً. بلا هذا العمود يبقى
        // الدفترُ متقدّماً وشيكُه مجهولَ المصدر.
        chequeBookId: v.chequeBookId,
        paperNumber: number,
        type: 'cheque',
        direction: 'issued',
        partyId: v.partyId ?? 0,
        amount: c.amount,
        issueDate: DateTime.now(),
        dueDate: dueDate,
        bankName: bank,
        notes: notes,
        globalId: gid,
      );
    }
  }

  Future<void> _recordAllocations(
    VoucherSubmission v,
    double amount, {
    required bool interceptedByServer,
  }) async {
    if (v.allocations.isEmpty) return;
    if (interceptedByServer) {
      _toast(
        'حُفظ السندُ على الخادم — والتوزيعُ على الفواتير لا يُسجَّل من جهازٍ '
        'عميل.',
        ToastType.info,
      );
      return;
    }
    await ref.read(databaseProvider).recordVoucherAllocations(
          paymentNumber: 'PAY${DateTime.now().millisecondsSinceEpoch}',
          paymentDate: v.date,
          amount: amount,
          paymentMethod: v.method,
          safeId: v.safeId!,
          paymentType: 'payment',
          partyId: v.partyId,
          userId: ref.read(authProvider).user?.id,
          notes: 'توزيع سند الصرف',
          allocations: [
            for (final a in v.allocations)
              (
                invoiceType: a.invoiceType,
                invoiceId: a.invoiceId,
                amount: a.amount
              ),
          ],
        );
  }

  /// يُغلق الاستمارةَ إن كانت مدفوعةً، وإلّا يُجدّدُها نظيفةً.
  void _finish() {
    if (!mounted) return;
    if (finishVoucherSave(context)) setState(() => _formEpoch++);
  }

  void _toast(String message, ToastType type) {
    if (!mounted) return;
    AppToast.show(context, message, type: type);
  }
}
