import 'package:ural_erp/core/i18n/tr.dart';
// شاشةُ «سند قبض» — تصميمُ المالك `(12)` و`(13)`.
//
// ═══ ⚠️ مسارُ المال **منقولٌ** من الحوار لا مُعادُ كتابته ═══
//
// `receipt_voucher_dialog_picpos.dart` يحمل إصلاحاتٍ لا تُستعاد بالتخمين:
// مواصفةُ ١٣٣ (‏فحصُ دليل الحسابات قبل أيّ كتابة، وإسقاطُ قيدِ النقديّة
// وحركةِ الخزنة للشيك لئلّا يُقيَّد العميلُ مرّتين)، والكتابةُ المزدوجةُ
// عبر `ClientWriteInterceptor` بمعرّفٍ عامٍّ **مشترَك** (‏Issue 12) لئلّا
// يرى الكاشيرُ السندَ مرّتين بعد المزامنة، ونسبةُ الفرع إلى فرع المشغِّل لا
// فرع الخزنة (‏مواصفة ١٣٥ BUG-C).
//
// فنُقلت الكتلةُ كما هي، وتغيّر ما يقرأ حالةَ الشاشة وحدَه.
//
// ═══ 🔴 وما أُصلح أثناء النقل: مبلغُ كلِّ شيكٍ يُكتَب ولا يُقسَّم ═══
//
// الحوارُ يجمع **أرقامَ** الشيكات وحدَها ثمّ:
//
//     final perCheck = netAmount / count;
//
// فثلاثةُ شيكاتٍ بـ١٠٠٠ و٢٠٠٠ و٣٠٠٠ تُكتَب ٢٠٠٠ و٢٠٠٠ و٢٠٠٠. والمجموعُ
// صحيحٌ فلا شيءَ يبدو معطوباً — حتى يحين تحصيلُ أوّلِ شيكٍ فيُقيَّد بمبلغٍ
// لم يُكتَب على الورقة، أو يرتدّ بمبلغٍ مخترَع.
//
// ═══ 🔴 و«توزيع المبلغ على الفواتير» يكتب فعلاً ═══
//
// `recordVoucherAllocations` — **سجلٌّ لا حركةُ مالٍ ثانية**: السندُ قيَّد
// Dr Safe / Cr Customer سلفاً. راجع رأسَ `payment_allocations_dao.dart`.
//
// ⚠️ **ولا يُنادى في وضع العميل**: الكتابةُ تقع على الخادم فيعود
// `voucherRowId = 0`، والمعرّفاتُ المحلّيّةُ تتصادم مع معرّفات الخادم عند
// السحب. فالتوزيعُ يُكتَب حين تقع الكتابةُ محلّيّاً وحدَها، ويُقال ذلك.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/utils/uuid_v7.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../services/cheque_receipt_preflight.dart';
import '../../../services/client_write_interceptor.dart';
import '../../widgets/permission_guard.dart';
import '../voucher_sources.dart';
import 'voucher_form_picpos.dart';

/// مراكزُ التكلفة النشطة — إلزاميّةٌ حين تكون معرَّفة.
final _costCentersProvider = FutureProvider.autoDispose<List<CostCenter>>(
    (ref) => ref.watch(accountingRepositoryProvider).getActiveCostCenters());

/// فواتيرُ الطرف المفتوحة — تُقرأ عند اختياره.
/// ⚠️ **عامٌّ ليقرأه سندُ الصرف أيضاً**: نسختان كانتا تفترقان عند أوّل
/// تعديلٍ في شرط «مفتوحة».
final voucherOpenInvoicesProvider = FutureProvider.autoDispose
    .family<List<VoucherInvoiceOption>, ({int partyId, bool supplier})>(
        (ref, key) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.getOpenInvoicesForParty(
    partyId: key.partyId,
    forSupplier: key.supplier,
  );
  return [
    for (final r in rows)
      (
        invoiceType: r.invoiceType,
        id: r.id,
        number: r.number,
        date: r.date,
        total: r.total,
        paid: r.paid,
      ),
  ];
});

class ReceiptVoucherPicposScreen extends ConsumerStatefulWidget {
  const ReceiptVoucherPicposScreen({super.key});

  @override
  ConsumerState<ReceiptVoucherPicposScreen> createState() =>
      _ReceiptVoucherPicposScreenState();
}

class _ReceiptVoucherPicposScreenState
    extends ConsumerState<ReceiptVoucherPicposScreen> {
  bool _busy = false;
  int? _partyId;

  /// عدّادُ تجديد الاستمارة — تبديلُه يُعيد بناءَ `PicPosVoucherForm` بحالةٍ
  /// نظيفة. راجع `finishVoucherSave` في `voucher_form_picpos.dart`.
  int _formEpoch = 0;

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
                    (partyId: _partyId!, supplier: false)))
                .value ??
            const <VoucherInvoiceOption>[];
    // E2/E3 — الدليلُ ودفاترُ السندات. والمفتاحُ يتبع تحميلَهما: الاستمارةُ
    // تقرأ الافتراضيَّ في `initState` فتُبنى ثانيةً حين يصلان.
    final accounts = ref.watch(voucherAccountOptionsProvider).value ??
        const <VoucherAccountOption>[];
    final books = ref.watch(voucherBookOptionsProvider('receipt')).value;

    return PermissionGuard(
      // ⚠️ **`treasury_view` لا `treasury_receipts_create`.** الكودُ
      //    الثاني موجودٌ في السجلّ و**غيرُ ممنوحٍ لأيّ دورٍ** في
      //    `RoleGrantMatrix.defaultGrants` — فربطُ الشاشة به كان يسحبها من
      //    الجميع. والحوارُ الذي تحلّ محلَّه يُبلَغ اليومَ بـ`treasury_view`
      //    وحدَه، فالتوصيلُ يُبقي **مَن يُنشئ سنداً** كما هو.
      permission: PermissionCodes.treasuryView,
      child: PicPosVoucherForm(
        key: ValueKey(
            '$_formEpoch-${accounts.isNotEmpty}-${books != null}'),
        kind: PicPosVoucherKind.receipt,
        accounts: accounts,
        voucherBooks: books?.books ?? const [],
        initialBookId: books?.defaultId,
        parties: [
          for (final p in parties)
            if (p.isCustomer)
              (
                id: p.id,
                name: p.name,
                meta: p.phone,
                isDeliveryCompany: p.isDeliveryCompany,
              ),
        ],
        safes: [
          for (final s in safes)
            (id: s.id, name: s.name, type: s.safeType),
        ],
        costCenters: [
          for (final c in costCenters) (id: c.id, name: c.name),
        ],
        openInvoices: invoices,
        busy: _busy,
        onPartyPicked: (id) => setState(() => _partyId = id),
        onCancel: _finish,
        onSubmit: _save,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // الحفظ — منقولٌ من الحوار، وما تغيّر هو مصدرُ القراءة وحدَه
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _save(VoucherSubmission v) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final grossAmount = v.grossAmount;
      final commissionAmt =
          grossAmount * (v.commissionPercent / 100);
      final totalDiscount = v.discount + commissionAmt;
      final netAmount = grossAmount - totalDiscount;

      // Spec 133 (FR-013) — فحصُ دليل الحسابات **قبل أيّ كتابة**: حين تكون
      // أوراقُ القبض أو حسابُ العميل غيرَ مربوطَين يخرج نصٌّ عربيٌّ واضح،
      // بدل قيدِ صفرٍ صامتٍ يترك العميلَ مديناً بلا إشارة.
      if (v.method == 'check' && v.partyId != null) {
        try {
          await ChequeReceiptPreflight.validate(
            customerPartyId: v.partyId!,
            db: ref.read(databaseProvider),
          );
        } catch (e) {
          _toast(e is StateError ? e.message : '$e', ToastType.error);
          return;
        }
      }

      // E3 — ورقةُ الدفتر تُفحَص قبل أيّ كتابة: خارجَ المدى أو مكرّرةً أو ملغاة.
      final db = ref.read(databaseProvider);
      try {
        await preValidateVoucherBookLeaf(db, v);
      } catch (e) {
        _toast('$e', ToastType.error);
        return;
      }
      // خزنةُ المستند: المختارةُ، وإلّا أوّلُ خزنةٍ في النطاق (للشيك والتحويل).
      final docSafeId = v.safeId ??
          ref.read(scopedSafesProvider).value?.firstOrNull?.id;
      final isTransfer = v.method != 'check' &&
          v.safeId == null &&
          v.treasuryAccountId != null;
      if (isTransfer && voucherRunsOnClient) {
        _toast(tr('سند التحويل المحاسبي يُنشأ على جهاز الخادم.'),
            ToastType.error);
        return;
      }
      if (docSafeId == null) {
        _toast(tr('اختر الخزينة.'), ToastType.error);
        return;
      }
      final category = v.partyId == null ? 'other' : 'customer_payment';

      final treasuryRepo = ref.read(treasuryRepositoryProvider);
      final voucherNumber = 'REC${DateTime.now().year}'
          '${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

      final allCheckNumbers = v.cheques.map((c) => c.number).join(', ');
      final description = _describe(v, grossAmount, commissionAmt,
          allCheckNumbers);

      // Issue 12 — معرّفٌ عامٌّ **مشترَكٌ** بين الكتابة المحلّيّة ونسخةِ
      // الخادم، وإلّا رأى الكاشيرُ السندَ مرّتين بعد السحب.
      final sharedGlobalId = UuidV7.generate();
      // Spec 135 BUG-C — فرعُ المشغِّل لا فرعُ الخزنة.
      final operatingBranchId = ref.read(activeBranchIdProvider).value;

      // E2 — التحويلُ المحاسبيُّ مسارٌ محلّيٌّ وحدَه (رُفض في وضع العميل أعلاه).
      final intercepted = isTransfer
          ? null
          : await ClientWriteInterceptor.createReceipt(
              amount: netAmount,
              category: category,
              description: description,
              partyId: v.partyId,
              safeId: docSafeId,
              branchId: operatingBranchId,
              costCenterId: v.costCenterId,
              linkedAccountId: v.beneficiaryAccountId,
              globalId: sharedGlobalId,
              paperType: v.method == 'check' ? 'cheque' : null,
            );

      // ⚠️ يبقى صفراً في وضع العميل: الكتابةُ على الخادم والصفُّ يصل
      //    بالمزامنة. وصفرٌ يعني «لا سندَ محلّيّاً» لا خطأً.
      int voucherRowId = 0;
      if (isTransfer) {
        voucherRowId = await treasuryRepo.createAccountTransferVoucher(
          isReceipt: true,
          amount: netAmount,
          discount: totalDiscount,
          treasuryAccountId: v.treasuryAccountId!,
          beneficiaryAccountId: v.beneficiaryAccountId,
          partyId: v.partyId,
          category: category,
          description: description,
          userId: ref.read(authProvider).user?.id,
          costCenterId: v.costCenterId,
          documentSafeId: docSafeId,
          globalId: sharedGlobalId,
          operatingBranchId: operatingBranchId,
        );
      } else if (intercepted == null) {
        voucherRowId = await treasuryRepo.createReceiptVoucher(
          amount: netAmount,
          discount: totalDiscount,
          category: category,
          linkedAccountId: v.beneficiaryAccountId,
          safeId: docSafeId,
userId: ref.read(authProvider).user?.id,
           manualEntry: true,
          partyId: v.partyId,
          description: description,
          costCenterId: v.costCenterId,
          paperNumber: v.method == 'check' ? allCheckNumbers : null,
          paperType: v.method == 'check' ? 'cheque' : null,
          paperBankName:
              v.method == 'check' ? v.cheques.first.bank : null,
          paperDueDate: v.method == 'check' ? v.cheques.first.dueDate : null,
          paperIssueDate: v.method == 'check' ? DateTime.now() : null,
          globalId: sharedGlobalId,
          operatingBranchId: operatingBranchId,
        );
      }

      // E3 — ختمُ ورقة الدفتر على صفّ السند وتقديمُ الدفتر.
      await stampVoucherBookLeaf(db, v, voucherRowId);
      if (v.bookId != null) ref.invalidate(voucherBookOptionsProvider);

      if (v.method == 'check') {
        await _createCheques(v, voucherNumber, voucherRowId);
      }

      await _recordAllocations(v, voucherNumber, netAmount, voucherRowId,
          docSafeId, interceptedByServer: intercepted != null);

      final user = ref.read(authProvider).user;
      await ref.read(activityLogRepositoryProvider).logActivity(
            userId: user?.id,
            userName: user?.displayName ?? tr('مجهول'),
            action: 'receipt',
            entityType: 'payment',
            description: tr('سند قبض {p0} رقم {voucherNumber} بمبلغ {p1}', {'p0': v.method, 'voucherNumber': voucherNumber, 'p1': grossAmount.toStringAsFixed(AppConstants.decimalPlaces)}),
            amount: grossAmount,
          );

      if (!mounted) return;
      _toast(tr('تم حفظ سند القبض'), ToastType.success);
      _finish();
    } catch (e) {
      _toast(tr('خطأ في الحفظ: {e}', {'e': e}), ToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describe(
    VoucherSubmission v,
    double grossAmount,
    double commissionAmt,
    String allCheckNumbers,
  ) {
    var d = v.notes.isEmpty ? tr('تحصيل من عميل') : v.notes;
    if (v.commissionPercent > 0) {
      d += tr(' | المبلغ الكلي: {p0} | عمولة: {p1}% ({p2})', {'p0': grossAmount.toStringAsFixed(AppConstants.decimalPlaces), 'p1': v.commissionPercent.toStringAsFixed(1), 'p2': commissionAmt.toStringAsFixed(AppConstants.decimalPlaces)});
    }
    if (v.discount > 0) {
      d += tr(' | خصم: {p0}', {'p0': v.discount.toStringAsFixed(AppConstants.decimalPlaces)});
    }
    if (v.method == 'check') d += tr(' | شيك رقم: {allCheckNumbers}', {'allCheckNumbers': allCheckNumbers});
    return d;
  }

  /// 🔴 **بمبلغِ كلِّ شيكٍ كما كُتب** — لا قسمةً بالتساوي.
  Future<void> _createCheques(
    VoucherSubmission v,
    String voucherNumber,
    int voucherRowId,
  ) async {
    final cpRepo = ref.read(commercialPapersRepositoryProvider);
    for (final c in v.cheques) {
      final gid = UuidV7.generate();
      final dueDate =
          c.dueDate ?? DateTime.now().add(const Duration(days: 30));
      final bank = c.bank.isEmpty ? null : c.bank;
      var notes = tr('ترحيل تلقائي من سند قبض {voucherNumber}', {'voucherNumber': voucherNumber});
      // E4 — الساحبُ لا عمودَ له في `commercial_papers`، فيُحفَظ في الملاحظة.
      if (c.drawer.isNotEmpty) {
        notes += tr(' | الساحب: {p0}', {'p0': c.drawer});
      }

      // الكتابةُ المزدوجة (R4): الخادمُ ثمّ المحلّيّ بنفس المعرّف، وإلّا
      // بقي الشيكُ محلّيّاً ولم يره جهازٌ آخر.
      await ClientWriteInterceptor.createCommercialPaper(
        paperNumber: c.number,
        type: 'cheque',
        direction: 'received',
        partyId: v.partyId ?? 0,
        amount: c.amount,
        issueDate: DateTime.now(),
        dueDate: dueDate,
        bankName: bank,
        accountNumber: null,
        notes: notes,
        globalId: gid,
      );

      final paperId = await cpRepo.createPaper(
        sourceVoucherId: voucherRowId > 0 ? voucherRowId : null,
        paperNumber: c.number,
        type: 'cheque',
        direction: 'received',
        partyId: v.partyId ?? 0,
        amount: c.amount,
        issueDate: DateTime.now(),
        dueDate: dueDate,
        bankName: bank,
        notes: notes,
        globalId: gid,
      );

      // 🔴 **الإيداعُ انتقالٌ بقيده لا وسمٌ عند الإنشاء.** المحرّكُ يُنشئ
      //    الورقةَ عند `pending` ويقيّد أوراقَ القبض؛ والإيداعُ حالةٌ تاليةٌ
      //    لها قيدُها. وزيفُ الحالة عند الإنشاء كان يُظهر الشيكَ مودعاً
      //    ولا قيدَ يقابله.
      if (v.depositImmediately) {
        await cpRepo.updatePaperStatus(
          paperId,
          'deposited',
          changedBy: ref.read(authProvider).user?.id,
          notes: tr('إيداعٌ فوريٌّ من سند القبض {voucherNumber}', {'voucherNumber': voucherNumber}),
        );
      }
    }
  }

  Future<void> _recordAllocations(
    VoucherSubmission v,
    String voucherNumber,
    double netAmount,
    int voucherRowId,
    int docSafeId, {
    required bool interceptedByServer,
  }) async {
    if (v.allocations.isEmpty) return;
    if (interceptedByServer) {
      // ⚠️ راجع رأسَ الملفّ: المعرّفاتُ المحلّيّةُ تتصادم مع معرّفات الخادم.
      _toast(
        tr('حُفظ السندُ على الخادم — والتوزيعُ على الفواتير لا يُسجَّل من جهازٍ عميل.'),
        ToastType.info,
      );
      return;
    }
    await ref.read(databaseProvider).recordVoucherAllocations(
          paymentNumber: voucherNumber,
          paymentDate: v.date,
          amount: netAmount,
          paymentMethod: v.method,
          safeId: docSafeId,
          paymentType: 'receipt',
          partyId: v.partyId,
          userId: ref.read(authProvider).user?.id,
          notes: tr('توزيع سند القبض {voucherNumber}', {'voucherNumber': voucherNumber}),
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
