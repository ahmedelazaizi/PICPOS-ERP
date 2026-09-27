// نسخةُ PicPos من receipt_voucher_dialog.dart — فوركٌ مقصود.
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

import '../../../data/providers/providers.dart';
import '../../../services/generators/generators.dart';
import '../../../services/client_write_interceptor.dart';
import '../../../services/cheque_receipt_preflight.dart';
import '../../../core/utils/uuid_v7.dart';

import 'package:ural_erp/l10n/app_localizations.dart';
import '../../../../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../widgets/permission_guard.dart';
// نمطُ ديالوجات PicPos — الغلافُ المشترك.
import '../../picpos_shell/picpos_dialog.dart';

class ReceiptVoucherDialogPicpos extends ConsumerStatefulWidget {
  final Party? initialParty;
  const ReceiptVoucherDialogPicpos({super.key, this.initialParty});

  @override
  ConsumerState<ReceiptVoucherDialogPicpos> createState() =>
      _ReceiptVoucherDialogPicposState();
}

class _ReceiptVoucherDialogPicposState extends ConsumerState<ReceiptVoucherDialogPicpos> {
  final amountController = TextEditingController();
  final descriptionController = TextEditingController();
  final searchController = TextEditingController();
  final commissionController = TextEditingController();
  final discountController = TextEditingController();
  final paperNumberController = TextEditingController();
  final paperBankController = TextEditingController();

  String paymentMethod = 'cash'; // cash, check, bank
  DateTime? paperDueDate;
  List<String> checkNumbers = []; // Item 3: multiple check numbers
  Account? selectedAccount; // Item 1: COA selector for checks

  bool _isSaving = false; // A1: Double-click protection

  String category = 'customer_payment';
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
      searchController.text = selectedParty!.name;
      if (selectedParty!.isDeliveryCompany == true) {
        category = 'other';
      } else {
        category = 'customer_payment';
      }
    }

    // Pre-load parties data
    _loadParties();

    // Load cost centers
    _loadCostCenters();
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
    // was a no-op in Riverpod 3.x: `ref.listen` only subscribes during
    // build, and the Future.microtask wrapping meant the autoDispose
    // `allPartiesProvider` was disposed before any value arrived → the
    // party search TextField appeared unresponsive because _allParties
    // stayed empty and _searchParties had nothing to filter.
    //
    // `ref.listenManual(..., fireImmediately: true)`:
    //   - subscribes correctly from initState,
    //   - keeps the autoDispose provider alive for the dialog's lifetime,
    //   - fires immediately with the current AsyncValue (handles both
    //     "already loaded" and "still loading then data" through one
    //     code path).
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
      final lowerQuery = query.toLowerCase();
      setState(() {
        filteredParties = _allParties
            .where(
              (p) =>
                  (p.isCustomer || p.isDeliveryCompany == true) &&
                  (p.name.toLowerCase().contains(lowerQuery) ||
                      p.name.contains(query) ||
                      (p.phone?.contains(query) ?? false)),
            )
            .take(10)
            .toList();
      });
    }
  }

  /// Calculate commission amount
  double get _commissionPercent {
    return double.tryParse(commissionController.text) ?? 0;
  }

  double get _grossAmount {
    return double.tryParse(amountController.text) ?? 0;
  }

  double get _commissionAmount {
    return _grossAmount * (_commissionPercent / 100);
  }

  double get _netAmount {
    return _grossAmount - _commissionAmount;
  }

  double get _discountAmount {
    return double.tryParse(discountController.text) ?? 0;
  }

  bool get _isDeliveryCompany =>
      selectedParty?.isDeliveryCompany == true;

  @override
  Widget build(BuildContext context) {
    final safes = ref.watch(scopedSafesProvider).value ?? [];
    final localizations = AppLocalizations.of(context)!;

    // نمطُ ديالوجات PicPos (تصميمُ 2026-08-21) — الغلافُ وحدَه تبدّل:
    // رأسٌ بأيقونةٍ ملوّنةٍ وسطرٍ خافت، وتذييلٌ بخلفيّةِ الحقل.
    // **ومحتوى الحوار لم يُمَسّ** — لا حقلٌ أُضيف ولا نداءُ حفظٍ تغيّر.
    //
    // Issue 13 — landscape dialog. Wider footprint + paired short
    // fields (amount/discount, safe/cost-center) sit side-by-side
    // so the form fits one screen height instead of forcing a long
    // vertical scroll. The wider rendering also matches the printed
    // A4 voucher orientation, so what the cashier sees on screen
    // visually previews the print. والعرضُ الآن سقفٌ لا إلزام، فلا يخرج
    // الحوارُ عن حدّ شاشةٍ أضيقَ منه.
    return PicPosDialog(
      icon: PhosphorIconsBold.arrowCircleDown,
      accent: AppColors.success,
      title: localizations.receiptVoucher,
      width: 760,
      onCancel: () => Navigator.pop(context),
      cancelLabel: localizations.cancel,
      secondaryActions: [
        PicPosDialogAction(
          label: 'طباعة A4',
          icon: PhosphorIconsBold.printer,
          onPressed: () => _printA4Preview(),
        ),
        PicPosDialogAction(
          label: 'حفظ + حراري',
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
                      value: 'customer_payment',
                      child: Text(localizations.customerPayment),
                    ),
                    DropdownMenuItem(
                      value: 'sales',
                      child: Text(localizations.sales),
                    ),
                    DropdownMenuItem(
                      value: 'other',
                      child: Text(localizations.other),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      category = v!;
                      // Feature 013 / Issue VOUCHER-PARTY: keep `selectedParty`
                      // intact across category changes so the voucher always
                      // posts against the chosen party regardless of GL
                      // classification. Previously this nulled the party
                      // whenever the user picked a non-customer category, so
                      // the voucher saved with partyId=NULL and never
                      // appeared on كشف حساب for that party.
                      // Only the commission control (delivery-company-only)
                      // resets — it depends on the party's type AND the
                      // category logic, not on party identity.
                      commissionController.clear();
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Payment Method selection
                const Text(
                  'طريقة الدفع',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildPaymentMethodButton(
                      id: 'cash',
                      label: 'نقدي',
                      icon: PhosphorIconsFill.money,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 8),
                    _buildPaymentMethodButton(
                      id: 'bank',
                      label: 'تحويل بنكي',
                      icon: PhosphorIconsFill.bank,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    _buildPaymentMethodButton(
                      id: 'check',
                      label: 'شيك',
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
                        // Multi-check number input
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: paperNumberController,
                                decoration: InputDecoration(
                                  labelText: 'رقم الشيك',
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
                                  hintText: 'أدخل رقم الشيك + إضافة',
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
                              onDeleted: () => setState(() => checkNumbers.remove(num)),
                              backgroundColor: AppColors.warning.withValues(alpha: 0.1),
                              side: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
                            )).toList(),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: paperBankController,
                          decoration: const InputDecoration(
                            labelText: 'البنك المسحوب عليه',
                            prefixIcon: Icon(PhosphorIconsLight.bank, size: 20),
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
                            decoration: const InputDecoration(
                                labelText: 'تاريخ الاستحقاق',
                                prefixIcon: Icon(PhosphorIconsLight.calendar, size: 20)),
                            child: Text(
                              paperDueDate == null
                                  ? 'اختر التاريخ'
                                  : '${paperDueDate!.day}/${paperDueDate!.month}/${paperDueDate!.year}',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // COA Account selector (for all payment methods)
                FutureBuilder<List<Account>>(
                  future: ref.read(accountingRepositoryProvider).getAllAccounts().then((all) {
                    final parentIds = all.where((a) => a.parentId != null).map((a) => a.parentId!).toSet();
                    return all.where((a) => !parentIds.contains(a.id) && !a.isHiddenFromEntries).toList();
                  }),
                  builder: (ctx, snap) {
                    final accounts = snap.data ?? [];
                    if (accounts.isEmpty) return const SizedBox.shrink();
                    return Autocomplete<Account>(
                      optionsBuilder: (textValue) {
                        if (textValue.text.isEmpty) return accounts.take(20);
                        final q = textValue.text.toLowerCase();
                        return accounts.where((a) =>
                            a.name.toLowerCase().contains(q) ||
                            a.code.toLowerCase().contains(q));
                      },
                      displayStringForOption: (a) => '${a.code} - ${a.name}',
                      fieldViewBuilder: (ctx, controller, focusNode, onSubmitted) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'الحساب المقابل (من دليل الحسابات)',
                            hintText: 'ابحث بالاسم أو الرمز...',
                            prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        );
                      },
                      onSelected: (a) => setState(() => selectedAccount = a),
                    );
                  },
                ),
                if (selectedAccount != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(PhosphorIconsBold.checkCircle, size: 14, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text('${selectedAccount!.code} - ${selectedAccount!.name}',
                            style: const TextStyle(fontSize: 11, color: AppColors.success)),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Party selection (for customer payment)
                if (category == 'customer_payment') ...[
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو الهاتف...',
                      prefixIcon:
                          const Icon(PhosphorIconsBold.magnifyingGlass),
                      suffixIcon: selectedParty != null
                          ? IconButton(
                              icon: const Icon(PhosphorIconsBold.x),
                              onPressed: () {
                                setState(() {
                                  selectedParty = null;
                                  searchController.clear();
                                  filteredParties = [];
                                  commissionController.clear();
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
                                leading: p.isDeliveryCompany == true
                                    ? const Icon(PhosphorIconsBold.truck,
                                        color: AppColors.warning, size: 18)
                                    : const Icon(PhosphorIconsBold.user,
                                        color: AppColors.primary, size: 18),
                                title: Text(p.name),
                                subtitle: Text(
                                  'رصيد: ${p.balance.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                                ),
                                trailing: Text(
                                  p.phone ?? '',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onTap: () {
                                  setState(() {
                                    selectedParty = p;
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
                        color: (_isDeliveryCompany
                                ? AppColors.warning
                                : AppColors.primary)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isDeliveryCompany
                                ? PhosphorIconsBold.truck
                                : PhosphorIconsBold.user,
                            color: _isDeliveryCompany
                                ? AppColors.warning
                                : AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      selectedParty!.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (_isDeliveryCompany) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.warning,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'شركة توصيل',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  'الرصيد المستحق: ${selectedParty!.balance.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
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

                // Amount (Gross)
                TextField(
                  controller: amountController,
                  decoration: InputDecoration(
                    labelText: _isDeliveryCompany
                        ? 'المبلغ الكلي (قبل العمولة)'
                        : localizations.amount,
                    prefixIcon:
                        const Icon(PhosphorIconsLight.money, size: 20),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),

                // Discount (Settlement Discount)
                if (category == 'customer_payment' || category == 'other') ...[
                  TextField(
                    controller: discountController,
                    decoration: const InputDecoration(
                      labelText: 'خصم معجل دفع (Settlement Discount)',
                      prefixIcon: Icon(PhosphorIconsLight.tag, size: 20),
                      hintText: '0.00',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                ],

                // Commission % — only for delivery companies (guarded)
                if (_isDeliveryCompany) ...[
                  PermissionGuard(
                    permission: PermissionCodes.treasuryCommission,
                    showDisabled: true,
                    child: TextField(
                      controller: commissionController,
                      decoration: const InputDecoration(
                        labelText: 'نسبة العمولة %',
                        prefixIcon:
                            Icon(PhosphorIconsLight.percent, size: 20),
                        hintText: 'مثال: 15',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Commission calculation breakdown
                  if (_grossAmount > 0 && _commissionPercent > 0)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.info.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildCalcRow(
                            'المبلغ الكلي',
                            _grossAmount.toStringAsFixed(AppConstants.decimalPlaces),
                          ),
                          const Divider(height: 8),
                          _buildCalcRow(
                            'العمولة (${_commissionPercent.toStringAsFixed(1)}%)',
                            '- ${_commissionAmount.toStringAsFixed(AppConstants.decimalPlaces)}',
                            color: AppColors.error,
                          ),
                          const Divider(height: 8),
                          _buildCalcRow(
                            'صافي التحصيل',
                            _netAmount.toStringAsFixed(AppConstants.decimalPlaces),
                            color: AppColors.success,
                            isBold: true,
                          ),
                        ],
                      ),
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

                // Issue 13 — Safe + Cost Center side-by-side. Two short
                // single-line dropdowns that paired vertically wasted
                // half the wider dialog's space.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: selectedSafe?.id,
                        // Phase 5B.6 (Issue 7) — surface that the safe is
                        // mandatory now that the DAO no longer falls back
                        // to a default safe on client mode (5B.5).
                        decoration: InputDecoration(
                          labelText: '${localizations.safe} *',
                          helperText: 'مطلوب',
                        ),
                        items: safes.whereType<SafeData>().map((s) {
                          return DropdownMenuItem<int>(
                            value: s.id,
                            child: Row(
                              children: [
                                Icon(
                                  s.safeType == 'cash'
                                      ? PhosphorIconsBold.money
                                      : s.safeType == 'click'
                                          ? PhosphorIconsBold.cellSignalFull
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
                    if (_costCenters.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          initialValue: selectedCostCenterId,
                          // Phase 5B.6 (Issue 7) — make cost center
                          // mandatory so the entry can't silently route
                          // to whichever centre the GL defaulting logic
                          // happened to pick. The previous "بدون مركز
                          // تكلفة" option let users skip the picker
                          // entirely and was the source of the
                          // wrong-centre complaint in the field.
                          decoration: const InputDecoration(
                            labelText: 'مركز التكلفة *',
                            helperText: 'مطلوب',
                            prefixIcon:
                                Icon(PhosphorIconsLight.target, size: 20),
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
      AppToast.show(context, 'يرجى إدخال مبلغ صحيح للمعاينة');
      return;
    }

    final settingsRepo = ref.read(settingsRepositoryProvider);
    final companyName = await settingsRepo.getSetting('company_name');
    final companyPhone = await settingsRepo.getSetting('company_phone');
    final companyAddress = await settingsRepo.getSetting('company_address');
    final companyTaxId = await settingsRepo.getSetting('company_tax_id');

    await VouchersPdfGenerator.printVoucher(
      voucherNumber: 'PREVIEW',
      voucherType: 'receipt',
      date: DateTime.now(),
      amount: amount,
      discount: _discountAmount + (_isDeliveryCompany ? _commissionAmount : 0),
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

  Widget _buildCalcRow(String label, String value,
      {Color? color, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          '$value ${AppConstants.currencySymbolEn}',
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    amountController.dispose();
    descriptionController.dispose();
    searchController.dispose();
    commissionController.dispose();
    discountController.dispose();
    paperNumberController.dispose();
    paperBankController.dispose();
    super.dispose();
  }

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

    // Spec 108 (C) — when the operator records a cheque AND has picked an
    // explicit counter-account (e.g. البنك), the safe is logically already
    // implied: the cheque does not enter a cash drawer, it lands directly
    // in the bank's safe / clearing safe. Auto-resolve a matching default
    // safe so the operator is not asked to also pick "الخزينة" twice for
    // the same operation. We prefer a bank safe when the counter-account
    // looks like a bank account; otherwise we accept any default safe so
    // the voucher can still post.
    if (selectedSafe == null && paymentMethod == 'check' && selectedAccount != null) {
      final db = ref.read(databaseProvider);
      Safe? autoSafe;
      final code = selectedAccount!.code;
      // The seed COA puts bank under 1113 and click under 1121 style codes.
      // Anything starting with the bank code prefix → resolve a bank-type safe.
      if (code.startsWith('1113') || code.startsWith('111-')) {
        autoSafe = await db.getDefaultSafeByType('bank');
      }
      autoSafe ??= await db.getDefaultSafeByType('cash');
      if (autoSafe != null) {
        // Convert Drift's Safe row → domain SafeData (matches the type the
        // rest of the dialog uses for `selectedSafe`).
        final resolvedSafe = SafeData(
          id: autoSafe.id,
          name: autoSafe.name,
          safeType: autoSafe.safeType,
          balance: autoSafe.balance,
          isDefault: autoSafe.isDefault,
          isActive: autoSafe.isActive,
          bankName: autoSafe.bankName,
          accountNumber: autoSafe.accountNumber,
          costCenterId: autoSafe.costCenterId,
          branchId: autoSafe.branchId,
          linkedAccountId: autoSafe.linkedAccountId,
        );
        setState(() => selectedSafe = resolvedSafe);
        debugPrint(
          '[RECEIPT-VOUCHER] auto-resolved safeId=${resolvedSafe.id} '
          '(type=${resolvedSafe.safeType}) for cheque with explicit account '
          'code=${selectedAccount!.code}',
        );
      }
    }

    if (selectedSafe == null) {
      AppToast.show(context, 'الرجاء اختيار الخزينة');
      return;
    }

    // Phase 5B.6 (Issue 7) — when cost centers exist on the system, one
    // MUST be selected before the voucher can post. Without this gate the
    // DAO's create method silently posts to whichever cost centre the
    // accounting fallback picks (often "GEN"), which the user reported
    // as "the entry went to the wrong cost center".
    if (_costCenters.isNotEmpty && selectedCostCenterId == null) {
      AppToast.show(context, 'الرجاء اختيار مركز التكلفة');
      return;
    }

    final grossAmount = double.tryParse(amountController.text);
    if (grossAmount == null || grossAmount <= 0) {
      AppToast.show(context, localizations.enterValidAmount);
      return;
    }

    if (category == 'customer_payment' && selectedParty == null) {
      AppToast.show(context, 'الرجاء اختيار العميل');
      return;
    }

    if (paymentMethod == 'check') {
      // Collect all check numbers: from chips + what's in the text field
      final currentText = paperNumberController.text.trim();
      if (currentText.isNotEmpty && !checkNumbers.contains(currentText)) {
        checkNumbers.add(currentText);
      }
      if (checkNumbers.isEmpty) {
        AppToast.show(context, 'يرجى إدخال رقم شيك واحد على الأقل');
        return;
      }
    }

    final discount = _discountAmount;
    if (discount < 0) {
      AppToast.show(context, 'الخصم لا يمكن أن يكون سالباً');
      return;
    }
    final commissionPct = _commissionPercent;
    if (commissionPct < 0 || commissionPct > 100) {
      AppToast.show(context, 'نسبة العمولة يجب أن تكون بين 0 و 100');
      return;
    }

    final commissionAmt = _isDeliveryCompany ? _commissionAmount : 0.0;
    final totalDiscount = discount + commissionAmt;
    final netAmount = grossAmount - totalDiscount;

    if (netAmount <= 0) {
      AppToast.show(context, 'صافي المبلغ يجب أن يكون أكبر من صفر');
      return;
    }

    // Spec 133 (FR-013) — pre-flight COA validation for cheque receipts.
    // Runs BEFORE any write so the operator gets a clear Arabic message
    // when Notes Receivable or the customer sub-account is unmapped,
    // instead of a silent zero-credit (the cash-leg JE is skipped for
    // cheques per Commit A — if the commercial-papers autopost also
    // can't post for a mapping reason, the customer would otherwise
    // be debited zero with no signal). Matches Spec 082's fail-loud
    // philosophy.
    if (paymentMethod == 'check' && selectedParty != null) {
      try {
        await ChequeReceiptPreflight.validate(
          customerPartyId: selectedParty!.id,
          db: ref.read(databaseProvider),
        );
      } catch (e) {
        if (context.mounted) {
          AppToast.show(
            context,
            e is StateError ? e.message : e.toString(),
            type: ToastType.error,
          );
        }
        return;
      }
    }

    try {
      final treasuryRepo = ref.read(treasuryRepositoryProvider);
      final voucherNumber =
          'REC${DateTime.now().year}${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

      // Build description
      String description = descriptionController.text.isEmpty
          ? (category == 'customer_payment'
              ? 'تحصيل من عميل: ${selectedParty!.name}'
              : localizations.receiptVoucher)
          : descriptionController.text;

      if (_isDeliveryCompany && commissionPct > 0) {
        description +=
            ' | المبلغ الكلي: ${grossAmount.toStringAsFixed(AppConstants.decimalPlaces)} | عمولة: ${commissionPct.toStringAsFixed(1)}% (${commissionAmt.toStringAsFixed(AppConstants.decimalPlaces)})';
      }
      if (discount > 0) {
        description += ' | خصم: ${discount.toStringAsFixed(AppConstants.decimalPlaces)}';
      }
      // Build check numbers string for description
      final allCheckNumbers = checkNumbers.join(', ');
      if (paymentMethod == 'check') {
        description += ' | شيك رقم: $allCheckNumbers';
        if (selectedAccount != null) {
          description += ' | حساب: ${selectedAccount!.code} - ${selectedAccount!.name}';
        }
      }

      // Issue 12 — share one globalId between the local write and the
      // server-bound copy so SafeTransactionSyncStrategy can dedup on
      // pull. Without this each side minted its own UUID and the
      // cashier saw the same voucher twice after sync.
      final sharedGlobalId = UuidV7.generate();

      // ── Client mode: route to server first ──
      // Issue 3 (Feature 020): thread the operator's CoA account pick all
      // the way to the server so the server's JE credit leg matches the
      // local one. Without this, paired-client / mirror writes silently
      // diverged from HQ on every receipt with a non-default account.
      // Spec 133: also thread paperType so the server skips the cash-leg
      // JE + safe transaction for cheques (was always null pre-133, so
      // server posted a duplicate JE on top of the commercial-paper
      // autopost — the field-confirmed double-credit bug on 3.1.0+202).
      // Spec 135 BUG-C — attribute the voucher JE to the operator's working
      // branch (activeBranchIdProvider), not the target safe's branch. Null
      // when not yet resolved → DAO falls back to safe.branchId (legacy).
      final operatingBranchId = ref.read(activeBranchIdProvider).value;

      final intercepted = await ClientWriteInterceptor.createReceipt(
        amount: netAmount,
        category: category,
        description: description,
        partyId: selectedParty?.id,
        safeId: selectedSafe!.id,
        branchId: operatingBranchId,
        costCenterId: selectedCostCenterId,
        linkedAccountId: selectedAccount?.id,
        globalId: sharedGlobalId,
        paperType: paymentMethod == 'check' ? 'cheque' : null,
      );
      // معرّفُ صفِّ السند — تحمله كلُّ ورقةٍ تُولَد منه في `sourceVoucherId`،
      // فيقرؤه زرُّ «عرض السند» في «إدارة الشيكات».
      //
      // ⚠️ **ويبقى صفراً في وضع العميل**: الكتابةُ تقع على الخادم ويصل الصفُّ
      // بالمزامنة، فلا معرّفَ محلّيٌّ هنا. وصفرٌ يعني «لا سندَ بعد» لا خطأً —
      // والورقةُ تُكتَب على أيّ حال.
      int voucherRowId = 0;
      if (intercepted == null) {
        // Not in client mode or server handled it — write locally
        voucherRowId = await treasuryRepo.createReceiptVoucher(
          amount: netAmount,
          discount: totalDiscount,
          category: category,
          safeId: selectedSafe!.id,
          partyId: selectedParty?.id,
          description: description,
          costCenterId: selectedCostCenterId,
          linkedAccountId: selectedAccount?.id, // GAP-03: Pass selected GL account
          paperNumber: paymentMethod == 'check' ? allCheckNumbers : null,
          paperType: paymentMethod == 'check' ? 'cheque' : null,
          paperBankName: paymentMethod == 'check' ? paperBankController.text : null,
          paperDueDate: paymentMethod == 'check' ? paperDueDate : null,
          paperIssueDate: paymentMethod == 'check' ? DateTime.now() : null,
          globalId: sharedGlobalId,
          operatingBranchId: operatingBranchId, // Spec 135 BUG-C
        );
      }

      // Item 4: Auto-forward checks to commercial papers
      // Spec 029 corrective patch — dual-write per ENGINEERING_GUIDELINES.md R4. Each
      // cheque is sent to the server (ClientWriteInterceptor) AND written
      // locally (cpRepo). The same globalId is shared between sides so
      // CommercialPaperSyncStrategy dedups on next pull. Without the
      // server-side write, mirror/client cheques stayed local-only —
      // a different paired client would never see them, and the
      // server-side payment-voucher cheque picker would be empty.
      if (paymentMethod == 'check') {
        try {
          final cpRepo = ref.read(commercialPapersRepositoryProvider);
          // A3: Correct rounding for split amounts
          final count = checkNumbers.length;
          final perCheck = double.parse((netAmount / count).toStringAsFixed(AppConstants.decimalPlaces));
          final lastCheck = double.parse((netAmount - perCheck * (count - 1)).toStringAsFixed(AppConstants.decimalPlaces));

          for (int i = 0; i < count; i++) {
            final perCheckGlobalId = UuidV7.generate();
            final paperNumber = checkNumbers[i];
            final paperAmount = (i == count - 1) ? lastCheck : perCheck;
            final dueDate =
                paperDueDate ?? DateTime.now().add(const Duration(days: 30));
            final bankName = paperBankController.text.isNotEmpty
                ? paperBankController.text
                : null;
            const notesForPaper = null; // built per-cheque below
            final paperNotes = 'ترحيل تلقائي من سند قبض $voucherNumber';

            // 1. Server-side authoritative write (no-op in standalone).
            await ClientWriteInterceptor.createCommercialPaper(
              paperNumber: paperNumber,
              type: 'cheque',
              direction: 'received',
              partyId: selectedParty?.id ?? 0,
              amount: paperAmount,
              issueDate: DateTime.now(),
              dueDate: dueDate,
              bankName: bankName,
              accountNumber: null,
              notes: notesForPaper ?? paperNotes,
              globalId: perCheckGlobalId,
            );

            // 2. Local light cache so the UI reflects the new cheque
            //    immediately — pull-sync dedups on globalId.
            await cpRepo.createPaper(
              sourceVoucherId: voucherRowId > 0 ? voucherRowId : null,
              paperNumber: paperNumber,
              type: 'cheque',
              direction: 'received',
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
            AppToast.show(context, 'خطأ في الأوراق التجارية: $e', type: ToastType.error);
          }
        }
      }

      final user = ref.read(authProvider).user;
      final activityLogRepo = ref.read(activityLogRepositoryProvider);
      await activityLogRepo.logActivity(
        userId: user?.id,
        userName: user?.displayName ?? 'مجهول',
        action: 'receipt',
        entityType: 'payment',
        description:
            'سند قبض $paymentMethod رقم $voucherNumber بمبلغ ${grossAmount.toStringAsFixed(AppConstants.decimalPlaces)}',
        amount: grossAmount,
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
            voucherType: 'receipt',
            date: DateTime.now(),
            amount: grossAmount,
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
            voucherType: 'receipt',
            date: DateTime.now(),
            amount: grossAmount,
            discount: totalDiscount,
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
        AppToast.show(context, 'تم حفظ سند القبض بنجاح');
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, 'خطأ في الحفظ: $e');
      }
    }

    } finally { // A1: Always reset saving state
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
