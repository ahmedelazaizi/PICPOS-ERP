import 'package:ural_erp/core/i18n/tr.dart';
// نسخةُ PicPos من payment_voucher_dialog.dart — فوركٌ مقصود.
//
// ═══ لماذا نسخٌ لا مشاركة ═══
//
// الأصلُ مشتركٌ بين شاشةِ الخزينة القديمة (`screens/treasury_screen.dart`)
// وشاشةِ PicPos. وقاعدةُ هذا المستودع: الودجتُ المشتركةُ
// **تُنسَخُ إلى `*_picpos/` ثمَّ تُعدَّلُ النّسخة** — فإعادةُ تصميمِ سندِ
// PicPos لا تُغيِّرُ سلوكَ الشاشةِ القديمةِ تحتَ أقدامِها.
//
// والنّسخةُ هنا **مطابقةٌ حرفاً بحرف** للأصلِ عدا اسمَ الصنف —
// الفوركُ خطوةٌ مستقلّةٌ عن إعادةِ التصميم عمداً: خلطُهما يجعلُ
// الفرقَ ألفَ سطرٍ لا يُراجَع. والتّعديلُ يبدأُ في الكوميتِ التّالي.
//
// ⚠️ والعمقُ واحدٌ (`lib/presentation/X/widgets/`) فالاستيراداتُ
// النّسبيّةُ تبقى كما هي حرفاً.

import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_surface.dart';
// نمطُ ديالوجات PicPos — الغلافُ المشترك.
import '../../picpos_shell/picpos_dialog.dart';

import '../../../data/providers/providers.dart';
import '../../../services/generators/generators.dart';
import '../../../services/client_write_interceptor.dart';
import '../../../core/utils/uuid_v7.dart';

import 'package:ural_erp/l10n/app_localizations.dart';
import '../../../../../../core/constants/app_constants.dart';

class PaymentVoucherDialogPicpos extends ConsumerStatefulWidget {
  final Party? initialParty;
  const PaymentVoucherDialogPicpos({super.key, this.initialParty});

  @override
  ConsumerState<PaymentVoucherDialogPicpos> createState() =>
      _PaymentVoucherDialogPicposState();
}

class _PaymentVoucherDialogPicposState extends ConsumerState<PaymentVoucherDialogPicpos> {
  final amountController = TextEditingController();
  final descriptionController = TextEditingController();
  final searchController = TextEditingController();
  final discountController = TextEditingController();
  final paperNumberController = TextEditingController();
  final paperBankController = TextEditingController();
  final foreignAmountController = TextEditingController();
  final paymentRateController = TextEditingController();
  Currency? _foreignCurrency;

  bool get _showForeignFields => selectedParty?.currencyId != null && _foreignCurrency != null;

  Future<void> _loadPartyCurrency(Party? party) async {
    final currencyId = party?.currencyId;
    if (currencyId == null) {
      if (mounted) setState(() => _foreignCurrency = null);
      return;
    }
    final db = ref.read(databaseProvider);
    final currency = await (db.select(db.currencies)..where((c) => c.id.equals(currencyId))).getSingleOrNull();
    if (!mounted) return;
    final rate = await db.getExchangeRate(currencyId);
    setState(() {
      _foreignCurrency = currency?.isDefault == true ? null : currency;
      if (_foreignCurrency != null && paymentRateController.text.isEmpty) {
        paymentRateController.text = rate.toString();
      }
    });
  }

  String paymentMethod = 'cash'; // cash, check, bank
  DateTime? paperDueDate;
  List<String> checkNumbers = []; // Item 3: multiple check numbers

  // Pre-registered outgoing cheques (from the commercial-papers screen)
  // available to pick in the dropdown. Only status='pending' is shown —
  // once deposited/cashed/cancelled a paper is no longer selectable.
  List<CommercialPaperData> _availableCheques = [];

  // Feature 053 (v133): when the operator picks a pre-registered cheque
  // from the dropdown, the voucher amount must equal the cheque amount —
  // cheques are paid in full, not partially. We auto-fill the amount field
  // and lock it (`_amountLockedByCheque = true`) so the operator can't
  // type a divergent value that would later mismatch the underlying paper.
  // Lock releases automatically when the cheque list is empty again.
  bool _amountLockedByCheque = false;

  bool _isSaving = false; // A1: Double-click protection

  String category = 'supplier_payment';
  Party? selectedParty;
  SafeData? selectedSafe;
  int? selectedCostCenterId;
  List<CostCenter> _costCenters = [];
  List<Party> filteredParties = [];
  List<Party> _allParties = [];

  @override
  void initState() {
    super.initState();
    // Initialize default safe
    final safes = ref.read(scopedSafesProvider).value ?? [];
    if (safes.isNotEmpty) {
      selectedSafe = safes.whereType<SafeData>().firstWhere(
        (s) => s.isDefault,
        orElse: () => safes.whereType<SafeData>().first,
      );
    }

    // Initialize with provided party
    if (widget.initialParty != null) {
      selectedParty = widget.initialParty;
      _loadPartyCurrency(selectedParty);
      searchController.text = selectedParty!.name;
      category = 'supplier_payment';
    }

    // Pre-load parties data
    _loadParties();

    // Load cost centers
    _loadCostCenters();

    // Load pre-registered outgoing cheques for the picker dropdown
    _loadAvailableCheques();
  }

  Future<void> _loadAvailableCheques() async {
    try {
      final repo = ref.read(commercialPapersRepositoryProvider);
      // direction='issued' → outgoing cheques we've written.
      // The user can park a new cheque either directly as 'pending' or
      // move it into the portfolio ('in_portfolio'). Both statuses mean
      // "available to use" in a payment voucher, so we load both and
      // merge. 'deposited' / 'cashed' / 'bounced' / 'cancelled' /
      // 'endorsed' are terminal/inflight and correctly excluded.
      final pending = await repo.getCommercialPapers(
        direction: 'issued',
        status: 'pending',
      );
      final inPortfolio = await repo.getCommercialPapers(
        direction: 'issued',
        status: 'in_portfolio',
      );
      final combined = [...pending, ...inPortfolio]
          .where((p) => p.type == 'cheque')
          .toList();
      if (mounted) {
        setState(() => _availableCheques = combined);
      }
    } catch (_) {}
  }

  Future<void> _loadCostCenters() async {
    try {
      final accountingRepo = ref.read(accountingRepositoryProvider);
      final centers = await accountingRepo.getActiveCostCenters();
      if (mounted) setState(() => _costCenters = centers);
    } catch (_) {}
  }

  void _loadParties() {
    // Hotfix 2026-05-26 (Spec 133 field smoke) — port of branch
    // fix/treasury-dialog-party-autocomplete commit f80cdbe which never
    // merged into main. The old `Future.microtask + ref.listen` pattern
    // was a no-op in Riverpod 3.x and the party search TextField
    // appeared unresponsive. See receipt_voucher_dialog.dart for the
    // full rationale — same fix here.
    ref.listenManual<AsyncValue<List<Party>>>(
      allPartiesProvider,
      (_, next) {
        if (next.hasValue && mounted) {
          setState(() {
            _allParties = next.value ?? [];
          });
        }
      },
      fireImmediately: true,
    );
  }

  void _searchParties(String query) {
    if (query.isEmpty) {
      setState(() => filteredParties = []);
    } else {
      setState(() {
        filteredParties = _allParties
            .where(
              (p) =>
                  p.isSupplier && // Search for suppliers
                  (p.name.contains(query) ||
                      (p.phone?.contains(query) ?? false)),
            )
            .take(5)
            .toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final safes = ref.watch(scopedSafesProvider).value ?? [];
    final localizations = AppLocalizations.of(context)!;

    // نمطُ ديالوجات PicPos (تصميمُ 2026-08-21) — الغلافُ وحدَه تبدّل،
    // **والمحتوى لم يُمَسّ**. اللونُ المميّز أحمرُ لا أخضر: هذا صرفٌ لا قبض،
    // والفرقُ بينهما اتّجاهُ المال — فلا يُترَك للعنوان وحدَه.
    //
    // Issue 13 — landscape dialog (mirrors receipt_voucher_dialog).
    return PicPosDialog(
      icon: PhosphorIconsBold.arrowCircleUp,
      accent: AppColors.error,
      title: localizations.paymentVoucher,
      width: 760,
      onCancel: () => Navigator.pop(context),
      cancelLabel: localizations.cancel,
      secondaryActions: [
        PicPosDialogAction(
          label: tr('طباعة A4'),
          icon: PhosphorIconsBold.printer,
          onPressed: () => _printA4Preview(),
        ),
        PicPosDialogAction(
          label: tr('حفظ + حراري'),
          icon: PhosphorIconsBold.receipt,
          onPressed: () =>
              _saveVoucher(context, ref, localizations, printMode: 'thermal'),
        ),
      ],
      primaryAction: PicPosDialogAction(
        label: localizations.save,
        icon: PhosphorIconsBold.check,
        onPressed: () =>
            _saveVoucher(context, ref, localizations, printMode: 'none'),
      ),
      body: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category selection
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: InputDecoration(
                    labelText: localizations.voucherType,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'supplier_payment',
                      child: Text(localizations.supplierPayment),
                    ),
                    DropdownMenuItem(
                      value: 'expense',
                      child: Text(localizations.expense),
                    ),
                    DropdownMenuItem(
                      value: 'salary',
                      child: Text(localizations.salary),
                    ),
                    DropdownMenuItem(
                      value: 'other',
                      child: Text(localizations.other),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      category = v!;
                      // Feature 013 / Issue VOUCHER-PARTY: keep
                      // `selectedParty` intact across category changes so
                      // payments save with partyId set and appear in the
                      // supplier's كشف حساب regardless of the GL category
                      // chosen. See receipt_voucher_dialog for the
                      // mirror change.
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Payment Method selection
                 Text(
                  tr('طريقة الدفع'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildPaymentMethodButton(
                      id: 'cash',
                      label: tr('نقدي'),
                      icon: PhosphorIconsFill.money,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 8),
                    _buildPaymentMethodButton(
                      id: 'bank',
                      label: tr('تحويل بنكي'),
                      icon: PhosphorIconsFill.bank,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    _buildPaymentMethodButton(
                      id: 'check',
                      label: tr('شيك'),
                      icon: PhosphorIconsFill.newspaper,
                      color: AppColors.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Check Details (if payment method is check)
                if (paymentMethod == 'check') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        // Picker: pre-registered outgoing cheques from the
                        // commercial-papers screen. Selecting one auto-fills
                        // the number, bank and due-date below and pulls it
                        // out of the available list (no double-use).
                        if (_availableCheques.isNotEmpty) ...[
                          DropdownButtonFormField<int>(
                            isExpanded: true,
                            initialValue: null,
                            decoration:  InputDecoration(
                              labelText: tr('اختر من الشيكات المحفوظة'),
                              prefixIcon: const Icon(PhosphorIconsLight.listChecks, size: 20),
                            ),
                            items: _availableCheques
                                .where((p) => !checkNumbers.contains(p.paperNumber))
                                .map((p) => DropdownMenuItem<int>(
                                      value: p.id,
                                      child: Text(
                                        '${p.paperNumber}  •  ${p.amount.toStringAsFixed(2)}  •  ${p.bankName ?? ""}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                .toList(),
                            onChanged: (id) {
                              if (id == null) return;
                              final paper =
                                  _availableCheques.firstWhere((p) => p.id == id);
                              setState(() {
                                if (!checkNumbers.contains(paper.paperNumber)) {
                                  checkNumbers.add(paper.paperNumber);
                                }
                                // Auto-fill bank + due date from the saved paper
                                // so the downstream audit matches the stored record.
                                if (paperBankController.text.isEmpty &&
                                    (paper.bankName ?? '').isNotEmpty) {
                                  paperBankController.text = paper.bankName!;
                                }
                                paperDueDate ??= paper.dueDate;
                                // Feature 053: cheques are disbursed in full.
                                // Auto-fill the voucher amount from the
                                // selected cheque (sum if multiple) and lock
                                // the field so the operator can't enter a
                                // divergent value.
                                final totalSelected = _availableCheques
                                    .where((p) =>
                                        checkNumbers.contains(p.paperNumber))
                                    .fold<double>(
                                        0, (sum, p) => sum + p.amount);
                                amountController.text =
                                    totalSelected.toStringAsFixed(
                                        AppConstants.decimalPlaces);
                                _amountLockedByCheque = true;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        // Manual-entry fallback (for cheques that aren't yet
                        // registered in the commercial-papers screen).
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: paperNumberController,
                                decoration: InputDecoration(
                                  labelText: tr('رقم الشيك'),
                                  prefixIcon: const Icon(PhosphorIconsLight.hash, size: 20),
                                  suffixIcon: IconButton(
                                    icon: const Icon(PhosphorIconsBold.plus, size: 18, color: AppColors.success),
                                    onPressed: () {
                                      final num = paperNumberController.text.trim();
                                      if (num.isNotEmpty && !checkNumbers.contains(num)) {
                                        setState(() {
                                          checkNumbers.add(num);
                                          paperNumberController.clear();
                                        });
                                      }
                                    },
                                  ),
                                  hintText: tr('أدخل رقم الشيك يدوياً + إضافة'),
                                ),
                                onSubmitted: (v) {
                                  final num = v.trim();
                                  if (num.isNotEmpty && !checkNumbers.contains(num)) {
                                    setState(() {
                                      checkNumbers.add(num);
                                      paperNumberController.clear();
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        if (checkNumbers.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: checkNumbers.map((num) => Chip(
                              label: Text(num, style: const TextStyle(fontSize: 12)),
                              deleteIcon: const Icon(PhosphorIconsBold.x, size: 14),
                              onDeleted: () => setState(() {
                                checkNumbers.remove(num);
                                // Feature 053: recompute the auto-filled
                                // amount from the remaining selected cheques.
                                // If none left, release the lock so the
                                // operator can resume manual entry (e.g.
                                // switching to manually-typed cheque numbers).
                                final remaining = _availableCheques
                                    .where((p) => checkNumbers
                                        .contains(p.paperNumber))
                                    .fold<double>(0, (s, p) => s + p.amount);
                                if (checkNumbers.isEmpty) {
                                  _amountLockedByCheque = false;
                                  amountController.clear();
                                } else if (_amountLockedByCheque) {
                                  amountController.text = remaining
                                      .toStringAsFixed(
                                          AppConstants.decimalPlaces);
                                }
                              }),
                              backgroundColor: AppColors.warning.withValues(alpha: 0.1),
                              side: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
                            )).toList(),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: paperBankController,
                          decoration:  InputDecoration(
                            labelText: tr('البنك المسحوب عليه'),
                            prefixIcon: const Icon(PhosphorIconsLight.bank, size: 20),
                          ),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: paperDueDate ?? DateTime.now().add(const Duration(days: 30)),
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                            );
                            if (date != null) setState(() => paperDueDate = date);
                          },
                          child: InputDecorator(
                            decoration:  InputDecoration(
                                labelText: tr('تاريخ الاستحقاق'),
                                prefixIcon: const Icon(PhosphorIconsLight.calendar, size: 20)),
                            child: Text(
                              paperDueDate == null
                                  ? tr('اختر التاريخ')
                                  : '${paperDueDate!.day}/${paperDueDate!.month}/${paperDueDate!.year}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Party selection (only for supplier payment)
                if (category == 'supplier_payment') ...[
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText:
                          tr('ابحث بالاسم أو الهاتف...'), // Consider localizing
                      prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                      suffixIcon: selectedParty != null
                          ? IconButton(
                              icon: const Icon(PhosphorIconsBold.x),
                              onPressed: () {
                                setState(() {
                                  selectedParty = null;
                                  searchController.clear();
                                  filteredParties = [];
                                });
                              },
                            )
                          : null,
                    ),
                    onChanged: _searchParties,
                  ),
                  if (filteredParties.isNotEmpty && selectedParty == null)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: filteredParties
                            .map(
                              (p) => ListTile(
                                dense: true,
                                title: Text(p.name),
                                subtitle: Text(
                                  tr('رصيد: {p0} {p1}', {'p0': p.balance.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn}),
                                ),
                                trailing: Text(
                                  p.phone ?? '',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onTap: () {
                                  setState(() {
                                    selectedParty = p;
                                    _loadPartyCurrency(p);
                                    searchController.text = p.name;
                                    filteredParties = [];
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  if (selectedParty != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            PhosphorIconsBold.truck,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedParty!.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  tr('الرصيد المستحق له: {p0} {p1}', {'p0': selectedParty!.balance.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn}),
                                  style: TextStyle(
                                    color: selectedParty!.balance > 0
                                        ? AppColors.error
                                        : AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                ],

                TextField(
                  controller: amountController,
                  // Feature 053: cheques are disbursed in full, so when the
                  // amount has been auto-filled from one or more selected
                  // pre-registered cheques we lock the field. Hint explains
                  // how to release the lock without re-engineering the UI.
                  readOnly: _amountLockedByCheque,
                  decoration: InputDecoration(
                    labelText: localizations.amount,
                    helperText: _amountLockedByCheque
                        ? tr('قيمة الشيك تلقائية — احذف الشيك من القائمة لتعديل المبلغ')
                        : null,
                    filled: _amountLockedByCheque,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),

                if (_showForeignFields) ...[
                  Text(tr('عملة التسوية: {p0} — {p1}', {'p0': _foreignCurrency!.code, 'p1': _foreignCurrency!.name})),
                  Row(children: [
                    Expanded(child: TextField(controller: foreignAmountController, decoration:  InputDecoration(labelText: tr('المبلغ الأجنبي')), keyboardType: TextInputType.number, onChanged: (_) => setState(() {}))),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(controller: paymentRateController, decoration:  InputDecoration(labelText: tr('سعر الدفع')), keyboardType: TextInputType.number, onChanged: (_) => setState(() {}))),
                  ]),
                  Text(tr('المبلغ المحلي المحسوب: {p0}', {'p0': ((double.tryParse(foreignAmountController.text) ?? 0) * (double.tryParse(paymentRateController.text) ?? 0)).toStringAsFixed(AppConstants.decimalPlaces)})),
                  const SizedBox(height: 12),
                ],

                // Discount (Settlement Discount Received)
                if (category == 'supplier_payment' || category == 'expense') ...[
                  TextField(
                    controller: discountController,
                    decoration:  InputDecoration(
                      labelText: tr('خصم معجل دفع (Discount Received)'),
                      prefixIcon: const Icon(PhosphorIconsLight.tag, size: 20),
                      hintText: '0.00',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                ],

                // Description
                TextField(
                  controller: descriptionController,
                  decoration: InputDecoration(
                    labelText: localizations.description,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Issue 13 — Safe + Cost Center side-by-side (mirrors
                // receipt voucher dialog). Safe row hides entirely for
                // check payments since no cash leaves a safe.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (paymentMethod != 'check')
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: selectedSafe?.id,
                          // Phase 5B.6 (Issue 7) — see receipt_voucher_dialog;
                          // safe is mandatory now that the DAO no longer
                          // falls back to a default safe in client mode.
                          decoration: InputDecoration(
                            labelText: '${localizations.safe} *',
                            helperText: tr('مطلوب'),
                          ),
                          items: safes.whereType<SafeData>().map((s) {
                            return DropdownMenuItem<int>(
                              value: s.id,
                              child: Row(
                                children: [
                                  Icon(
                                    s.safeType == 'cash'
                                        ? PhosphorIconsBold.money
                                        : PhosphorIconsBold.bank,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(s.name),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              selectedSafe = safes
                                  .whereType<SafeData>()
                                  .firstWhere((s) => s.id == v);
                            });
                          },
                        ),
                      ),
                    if (paymentMethod != 'check' && _costCenters.isNotEmpty)
                      const SizedBox(width: 12),
                    if (_costCenters.isNotEmpty)
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          initialValue: selectedCostCenterId,
                          // Phase 5B.6 (Issue 7) — same rationale as the
                          // receipt-voucher dialog: drop the
                          // "بدون مركز تكلفة" option so the entry can't
                          // silently route to whichever centre the GL
                          // defaulting logic picks.
                          decoration:  InputDecoration(
                            labelText: tr('مركز التكلفة *'),
                            helperText: tr('مطلوب'),
                            prefixIcon:
                                const Icon(PhosphorIconsLight.target, size: 20),
                          ),
                          items: _costCenters
                              .map((cc) => DropdownMenuItem<int?>(
                                    value: cc.id,
                                    child: Text(cc.name),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => selectedCostCenterId = v),
                        ),
                      ),
                  ],
                ),
              ],
            ),
      ],
    );
  }

  Widget _buildPaymentMethodButton({
    required String id,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = paymentMethod == id;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => paymentMethod = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            border: Border.all(color: isSelected ? color : context.picposHairline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : color,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _printA4Preview() async {
    final amount = double.tryParse(amountController.text) ?? 0;
    if (amount <= 0) {
      AppToast.show(context, tr('يرجى إدخال مبلغ صحيح للمعاينة'));
      return;
    }

    final settingsRepo = ref.read(settingsRepositoryProvider);
    final companyName = await settingsRepo.getSetting('company_name');
    final companyPhone = await settingsRepo.getSetting('company_phone');
    final companyAddress = await settingsRepo.getSetting('company_address');
    final companyTaxId = await settingsRepo.getSetting('company_tax_id');

    await VouchersPdfGenerator.printVoucher(
      voucherNumber: 'PREVIEW',
      voucherType: 'payment',
      date: DateTime.now(),
      amount: amount,
      discount: double.tryParse(discountController.text) ?? 0,
      partyName: selectedParty?.name,
      description: descriptionController.text,
      safeName: selectedSafe?.name,
      employeeName: ref.read(authProvider).user?.displayName,
      paperNumber: paymentMethod == 'check' ? paperNumberController.text : null,
      paperBankName: paymentMethod == 'check' ? paperBankController.text : null,
      paperDueDate: paymentMethod == 'check' ? paperDueDate : null,
      companyName: companyName,
      companyPhone: companyPhone,
      companyAddress: companyAddress,
      companyTaxId: companyTaxId,
    );
  }

  @override
  void dispose() {
    amountController.dispose();
    descriptionController.dispose();
    searchController.dispose();
    discountController.dispose();
    paperNumberController.dispose();
    paperBankController.dispose();
    super.dispose();
  }

  /// Save voucher and optionally print
  Future<void> _saveVoucher(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations localizations, {
    required String printMode, // 'none', 'thermal', 'a4'
  }) async {
    // A1: Double-click protection
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try { // A1: Outer try for _isSaving reset in finally

    // For check payments, no safe is needed (no physical cash movement)
    // Phase 5B.6 (Issue 7) — when cost centers exist on the system, one
    // MUST be selected (matches receipt_voucher_dialog).
    if (_costCenters.isNotEmpty && selectedCostCenterId == null) {
      AppToast.show(context, tr('الرجاء اختيار مركز التكلفة'));
      return;
    }

    if (selectedSafe == null && paymentMethod != 'check') {
      AppToast.show(context, tr('الرجاء اختيار الخزينة'));
      return;
    }

    final amount = double.tryParse(amountController.text);
    if (amount == null || amount <= 0) {
      AppToast.show(context, localizations.enterValidAmount);
      return;
    }

    if (category == 'supplier_payment' && selectedParty == null) {
      AppToast.show(context, localizations.selectSupplier);
      return;
    }

    if (paymentMethod == 'check') {
      // Collect all check numbers: from chips + what's in the text field
      final currentText = paperNumberController.text.trim();
      if (currentText.isNotEmpty && !checkNumbers.contains(currentText)) {
        checkNumbers.add(currentText);
      }
      if (checkNumbers.isEmpty) {
        AppToast.show(context, tr('يرجى إدخال رقم شيك واحد على الأقل'));
        return;
      }
    }

    // Validate discount is not negative
    final discountVal = double.tryParse(discountController.text) ?? 0;
    if (discountVal < 0) {
      AppToast.show(context, tr('الخصم لا يمكن أن يكون سالباً'));
      return;
    }

    // A4: Negative balance warning (soft) instead of hard block
    if (paymentMethod != 'check' && selectedSafe!.balance < amount) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.warning, color: Colors.orange),
              const SizedBox(width: 8),
              Text(tr('تنبيه: رصيد الخزينة لا يكفي')),
            ],
          ),
          content: Text(
            'رصيد الخزينة الحالي: ${selectedSafe!.balance.toStringAsFixed(AppConstants.decimalPlaces)}\n'
            'المبلغ المطلوب: ${amount.toStringAsFixed(AppConstants.decimalPlaces)}\n\n'
            'سيصبح الرصيد سالباً. هل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child:  Text(tr('متابعة')),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    try {
      final treasuryRepo = ref.read(treasuryRepositoryProvider);
      final voucherNumber =
          'PAY${DateTime.now().year}${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

      String description = descriptionController.text.isEmpty
          ? (category == 'supplier_payment'
              ? tr('دفع لمورد: {p0}', {'p0': selectedParty!.name})
              : localizations.paymentVoucher)
          : descriptionController.text;

      // Build check numbers string for description
      final allCheckNumbers = checkNumbers.join(', ');
      if (paymentMethod == 'check') {
        description += tr(' | شيك رقم: {allCheckNumbers}', {'allCheckNumbers': allCheckNumbers});
      }

      // Spec 135 BUG-C — attribute the voucher JE to the operator's working
      // branch (activeBranchIdProvider), not the target safe's branch.
      final operatingBranchId = ref.read(activeBranchIdProvider).value;

      // ── Client mode: route to server first ──
      final intercepted = await ClientWriteInterceptor.createExpense(
        amount: amount,
        category: category,
        description: description,
        partyId: selectedParty?.id,
        safeId: paymentMethod == 'check' ? null : selectedSafe?.id,
        branchId: operatingBranchId,
        costCenterId: selectedCostCenterId,
        paperType: paymentMethod == 'check' ? 'cheque' : null,
      );
      // معرّفُ صفِّ السند — نظيرُ ما في حوار القبض. راجع تعليقَه: يبقى صفراً
      // في وضع العميل لأنّ الكتابةَ على الخادم، والورقةُ تُكتَب على أيّ حال.
      int voucherRowId = 0;
      if (intercepted == null) {
        // Not in client mode or server handled it — write locally
        voucherRowId = await treasuryRepo.createPaymentVoucher(
          amount: amount,
          discount: double.tryParse(discountController.text) ?? 0,
          category: category,
          safeId: paymentMethod == 'check' ? null : selectedSafe?.id,
          partyId: selectedParty?.id,
          description: description,
          costCenterId: selectedCostCenterId,
          // Check metadata
          paperNumber: paymentMethod == 'check' ? allCheckNumbers : null,
          paperType: paymentMethod == 'check' ? 'cheque' : null,
          paperBankName: paymentMethod == 'check' ? paperBankController.text : null,
          paperDueDate: paymentMethod == 'check' ? paperDueDate : null,
          paperIssueDate: paymentMethod == 'check' ? DateTime.now() : null,
          operatingBranchId: operatingBranchId, // Spec 135 BUG-C
          currencyId: _showForeignFields ? _foreignCurrency!.id : null,
          paymentRate: _showForeignFields ? double.tryParse(paymentRateController.text) : null,
          foreignAmount: _showForeignFields ? double.tryParse(foreignAmountController.text) : null,
        );
      }

      // Item 4: Auto-forward checks to commercial papers
      // Spec 029 corrective patch — dual-write per ENGINEERING_GUIDELINES.md R4 (server +
      // light local cache, shared globalId for pull-dedup). Plus Bug B:
      // when the user picks a PRE-REGISTERED cheque from the dropdown,
      // the existing local row was being silently skipped — partyId
      // and audit trail were lost. Now we still skip the create (avoids
      // unique-constraint violation), but APPEND a status-history note
      // recording which voucher used the cheque + which party received
      // it. The cheque's lifecycle status stays unchanged (the user can
      // explicitly transition to 'cashed'/'deposited' from the
      // commercial-papers screen later), so accounting is undisturbed.
      if (paymentMethod == 'check') {
        try {
          final cpRepo = ref.read(commercialPapersRepositoryProvider);
          // A3: Correct rounding for split amounts
          final count = checkNumbers.length;
          final perCheck = double.parse((amount / count).toStringAsFixed(AppConstants.decimalPlaces));
          final lastCheck = double.parse((amount - perCheck * (count - 1)).toStringAsFixed(AppConstants.decimalPlaces));
          final selectedPartyName =
              selectedParty?.name ?? tr('مستفيد غير محدد');

          for (int i = 0; i < count; i++) {
            final num = checkNumbers[i];
            final preExisting =
                _availableCheques.where((p) => p.paperNumber == num).toList();

            if (preExisting.isNotEmpty) {
              // Bug B fix: tag the pre-registered cheque with a history
              // note linking it to the voucher + recipient. Status stays
              // unchanged; updatePaperStatus also accepts the same
              // `status` value and just appends a history entry — that
              // becomes the audit-trail anchor without re-posting any JE.
              final existing = preExisting.first;
              final note =
                  tr('استُخدمت في سند صرف {voucherNumber} لـ {selectedPartyName}', {'voucherNumber': voucherNumber, 'selectedPartyName': selectedPartyName});
              try {
                await ClientWriteInterceptor.updateCommercialPaperStatus(
                  existing.id,
                  existing.status,
                  changedBy: ref.read(authProvider).user?.id,
                  notes: note,
                );
                await cpRepo.updatePaperStatus(
                  existing.id,
                  existing.status,
                  changedBy: ref.read(authProvider).user?.id,
                  notes: note,
                );
              } catch (_) {
                // Non-fatal: the voucher is already saved; the note is
                // diagnostic only.
              }
              continue;
            }

            // Fresh cheque path — dual-write to server + local.
            final perCheckGlobalId = UuidV7.generate();
            final paperAmount = (i == count - 1) ? lastCheck : perCheck;
            final dueDate =
                paperDueDate ?? DateTime.now().add(const Duration(days: 30));
            final bankName = paperBankController.text.isNotEmpty
                ? paperBankController.text
                : null;
            final paperNotes = tr('ترحيل تلقائي من سند صرف {voucherNumber}', {'voucherNumber': voucherNumber});

            await ClientWriteInterceptor.createCommercialPaper(
              paperNumber: num,
              type: 'cheque',
              direction: 'issued',
              partyId: selectedParty?.id ?? 0,
              amount: paperAmount,
              issueDate: DateTime.now(),
              dueDate: dueDate,
              bankName: bankName,
              accountNumber: null,
              notes: paperNotes,
              globalId: perCheckGlobalId,
            );
            await cpRepo.createPaper(
              sourceVoucherId: voucherRowId > 0 ? voucherRowId : null,
              paperNumber: num,
              type: 'cheque',
              direction: 'issued',
              partyId: selectedParty?.id ?? 0,
              amount: paperAmount,
              issueDate: DateTime.now(),
              dueDate: dueDate,
              bankName: bankName,
              notes: paperNotes,
              globalId: perCheckGlobalId,
            );
          }
        } catch (e) {
          if (context.mounted) {
            AppToast.show(context, tr('خطأ في الأوراق التجارية: {e}', {'e': e}), type: ToastType.error);
          }
        }
      }

      final user = ref.read(authProvider).user;
      final activityLogRepo = ref.read(activityLogRepositoryProvider);
      await activityLogRepo.logActivity(
        userId: user?.id,
        userName: user?.displayName ?? tr('مجهول'),
        action: 'expense',
        entityType: 'payment',
        description:
            tr('سند صرف {paymentMethod} رقم {voucherNumber} بمبلغ {p0}', {'paymentMethod': paymentMethod, 'voucherNumber': voucherNumber, 'p0': amount.toStringAsFixed(AppConstants.decimalPlaces)}),
        amount: amount,
      );

      if (printMode != 'none') {
        final settingsRepo = ref.read(settingsRepositoryProvider);
        final companyName = await settingsRepo.getSetting('company_name');
        final companyPhone = await settingsRepo.getSetting('company_phone');
        final companyAddress = await settingsRepo.getSetting('company_address');
        final companyTaxId = await settingsRepo.getSetting('company_tax_id');

        if (printMode == 'thermal') {
          await ThermalVoucherGenerator.printVoucher(
            voucherNumber: voucherNumber,
            voucherType: 'payment',
            date: DateTime.now(),
            amount: amount,
            companyName: companyName,
            companyPhone: companyPhone,
            companyAddress: companyAddress,
            partyName: selectedParty?.name,
            partyPhone: selectedParty?.phone,
            description: description,
            safeName: selectedSafe?.name,
            employeeName: user?.displayName,
          );
        } else if (printMode == 'a4') {
          await VouchersPdfGenerator.printVoucher(
            voucherNumber: voucherNumber,
            voucherType: 'payment',
            date: DateTime.now(),
            amount: amount,
            discount: double.tryParse(discountController.text) ?? 0,
            partyName: selectedParty?.name,
            description: description,
            safeName: selectedSafe?.name,
            employeeName: user?.displayName,
            paperNumber: paymentMethod == 'check' ? paperNumberController.text : null,
            paperBankName: paymentMethod == 'check' ? paperBankController.text : null,
            paperDueDate: paymentMethod == 'check' ? paperDueDate : null,
            companyName: companyName,
            companyPhone: companyPhone,
            companyAddress: companyAddress,
            companyTaxId: companyTaxId,
          );
        }
      }

      if (context.mounted) {
        Navigator.pop(context);
        AppToast.show(context, tr('تم حفظ سند الصرف بنجاح'));
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, tr('خطأ في الحفظ: {e}', {'e': e}));
      }
    }

    } finally { // A1: Always reset saving state
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
