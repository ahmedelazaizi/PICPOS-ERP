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
// ═══ ⚠️ وما لم يُنقَل: اختيارُ شيكٍ مسجَّلٍ سلفاً ═══
//
// الحوارُ يسمح بانتقاء ورقةٍ **قائمةٍ** من القائمة فيُعلِّقها بملاحظةِ
// تاريخٍ بدل إنشاء ورقةٍ ثانية. وهو مسارٌ لدفاتر الشيكات المطبوعة مسبقاً،
// ومكانُه الطبيعيُّ **دفترُ الشيكات** (`ChequeBooks`) الذي لم يُبنَ بعد.
// فبُني هنا مسارُ الشيك الجديد وحدَه، والقديمُ باقٍ في الحوار حتى يصل
// الدفتر — ولا يُحذَف الحوارُ قبلَه.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/utils/uuid_v7.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../services/client_write_interceptor.dart';
import '../../widgets/permission_guard.dart';
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
        busy: _busy,
        onPartyPicked: (id) => setState(() => _partyId = id),
        onCancel: () => Navigator.of(context).maybePop(),
        onSubmit: _save,
      ),
    );
  }

  Future<void> _save(VoucherSubmission v) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final amount = v.grossAmount;
      final allCheckNumbers = v.cheques.map((c) => c.number).join(', ');
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
        await _createCheques(v, voucherRowId);
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
      Navigator.of(context).maybePop();
    } catch (e) {
      _toast('خطأ في الحفظ: $e', ToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 🔴 **بمبلغِ كلِّ شيكٍ كما كُتب** — لا قسمةً بالتساوي.
  Future<void> _createCheques(VoucherSubmission v, int voucherRowId) async {
    final cpRepo = ref.read(commercialPapersRepositoryProvider);
    for (final c in v.cheques) {
      final gid = UuidV7.generate();
      final dueDate =
          c.dueDate ?? DateTime.now().add(const Duration(days: 30));
      final bank = c.bank.isEmpty ? null : c.bank;
      const notes = 'ترحيل تلقائي من سند صرف';

      await ClientWriteInterceptor.createCommercialPaper(
        paperNumber: c.number,
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
        paperNumber: c.number,
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

  void _toast(String message, ToastType type) {
    if (!mounted) return;
    AppToast.show(context, message, type: type);
  }
}
