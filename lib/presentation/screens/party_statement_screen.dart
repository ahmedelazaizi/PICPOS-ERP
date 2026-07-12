import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart' show Uint8List, debugPrint;
import '../../core/utils/platform_init.dart';
import '../../core/utils/file_utils.dart' show fileUtils;
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:excel/excel.dart' hide Border;
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shimmer_loading.dart';

import '../../data/providers/providers.dart';
import '../../domain/entities/product_entity.dart';
import '../../services/invoice_generator.dart';
import '../../services/generators/vouchers_pdf_generator.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../core/constants/app_constants.dart';

// ── Part files (mixin-based extraction) ─────────────────────────────────
part 'party_statement/party_statement_table.dart';
part 'party_statement/party_statement_dialogs.dart';

/// Party Account Statement Screen
/// Shows detailed account statement for a customer or supplier
class PartyStatementScreen extends ConsumerStatefulWidget {
  final int? partyId;
  final bool? isCustomer;
  final String partyName;
  final bool isSupplier;

  const PartyStatementScreen({
    super.key,
    this.partyId,
    this.partyName = '',
    this.isSupplier = false,
    this.isCustomer,
  });

  @override
  ConsumerState<PartyStatementScreen> createState() =>
      _PartyStatementScreenState();
}

class _PartyStatementScreenState extends ConsumerState<PartyStatementScreen>
    with _PartyStatementTableMixin, _PartyStatementDialogsMixin {
  @override
  DateTime? fromDate;
  @override
  DateTime? toDate;
  @override
  List<PartyStatementEntry> entries = [];
  @override
  PartySummary? summary;
  @override
  Party? party;
  @override
  bool isLoading = true;

  @override
  final DateFormat dateFormat = DateFormat('yyyy/MM/dd');

  // For party selection when no partyId is provided
  int? _selectedPartyId;
  List<Party> _allParties = [];

  @override
  void initState() {
    super.initState();
    if (widget.partyId != null) {
      _selectedPartyId = widget.partyId;
      loadData();
    } else {
      _loadPartiesList();
    }
  }

  Future<void> _loadPartiesList() async {
    setState(() => isLoading = true);
    try {
      final repo = ref.read(partiesRepositoryProvider);
      final parties = await repo.watchAllParties().first;
      if (mounted) {
      final isSupplierMode = widget.isSupplier || widget.isCustomer == false;
      final isCustomerMode = widget.isCustomer == true;
        setState(() {
          _allParties = parties
              .where((p) {
                if (isSupplierMode) return p.isSupplier;
                if (isCustomerMode) return p.isCustomer;
                return true; // fallback: show all
              })
              .toList();
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Future<void> loadData() async {
    final partyId = _selectedPartyId ?? widget.partyId;
    if (partyId == null) {
      setState(() => isLoading = false);
      return;
    }

    setState(() => isLoading = true);

    try {
      final repo = ref.read(partiesRepositoryProvider);
      final p = await repo.getPartyById(partyId);

      // Feature 010 / Cluster E (Issue 5) — short-circuit when the party
      // row could not be resolved. Without this, the next call
      // (getPartySummary) throws "Party not found" inside this try, the
      // catch fires a transient toast (easy to miss), and the screen
      // body renders BLANK — there was no else-branch in build() for
      // `_selectedPartyId != null && party == null`. The user reported
      // exactly this symptom on the server build: AppBar updates but
      // body stays empty (the button "doesn't respond"). Now we leave
      // party=null and let build() show a clear placeholder.
      if (p == null) {
        unawaited(DiagnosticLogger.log('PARTY-STATEMENT',
            '⚠ getPartyById returned null for partyId=$partyId — '
            'rendering missing-party placeholder'));
        if (mounted) {
          setState(() {
            party = null;
            entries = const [];
            summary = null;
            isLoading = false;
          });
        }
        return;
      }

      final e = await repo.getPartyStatement(partyId, fromDate: fromDate, toDate: toDate);
      final s = await repo.getPartySummary(partyId);

      if (mounted) {
        setState(() {
          party = p;
          entries = e;
          summary = s;
          isLoading = false;
        });
      }
    } catch (e, st) {
      // Field-collected diagnostics — Cluster E was originally invisible
      // because errors only surfaced as a transient toast. Persist the
      // failure so the next session can see why the load failed.
      debugPrint('[PARTY-STATEMENT] loadData failed for partyId=$partyId: $e\n$st');
      unawaited(DiagnosticLogger.log('PARTY-STATEMENT',
          '❌ loadData failed partyId=$partyId: $e'));
      if (mounted) {
        setState(() => isLoading = false);
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final partyLabel = widget.isSupplier ? 'مورد' : 'عميل';
    final selectedName = party?.name ?? widget.partyName;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: Text('كشف حساب: ${selectedName.isEmpty ? partyLabel : selectedName}'),
          backgroundColor: widget.isSupplier ? AppColors.warning : AppColors.primary,
          foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.microsoftExcelLogo),
              onPressed: entries.isEmpty ? null : exportToExcel,
              tooltip: 'تصدير Excel',
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.printer),
              onPressed: entries.isEmpty ? null : printStatement,
              tooltip: 'طباعة PDF',
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: isLoading
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: ShimmerLoading.list(itemCount: 6),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Party selector when no partyId is provided
                    if (widget.partyId == null) ...[
                      _buildPartySelector(partyLabel),
                      const SizedBox(height: 8),
                    ],
                    if (_selectedPartyId != null && party != null) ...[
                      buildPartyHeader(),
                      const SizedBox(height: 8),
                      buildDateFilter(),
                      const SizedBox(height: 8),
                      Expanded(child: buildStatementTable()),
                      buildTotalsFooter(),
                    ] else if (_selectedPartyId != null && party == null) ...[
                      // Feature 010 / Cluster E — explicit placeholder for
                      // the case where a partyId was passed in (so we did
                      // NOT show the autocomplete picker above) but the row
                      // could not be resolved. Without this branch the body
                      // rendered blank and the user perceived the entry-
                      // point button as broken ("لا يستجيب").
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                PhosphorIconsBold.warningCircle,
                                size: 64,
                                color: AppColors.warning.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'تعذّر تحميل بيانات هذا ال$partyLabel',
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'قد يكون الحساب محذوفاً أو غير متاح من هذا الجهاز. '
                                'جرّب المزامنة أو افتح كشف حساب طرف آخر.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else if (_selectedPartyId == null) ...[
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                PhosphorIconsBold.userList,
                                size: 64,
                                color: AppColors.textMuted.withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'اختر $partyLabel لعرض كشف حسابه',
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPartySelector(String partyLabel) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            widget.isSupplier ? PhosphorIconsBold.truck : PhosphorIconsBold.user,
            color: AppColors.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Autocomplete<Party>(
              optionsBuilder: (textValue) {
                if (textValue.text.isEmpty) return _allParties;
                return _allParties.where(
                  (p) => p.name.toLowerCase().contains(textValue.text.toLowerCase()) ||
                      (p.phone?.contains(textValue.text) ?? false),
                );
              },
              displayStringForOption: (p) => p.name,
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'اختر $partyLabel',
                    hintText: 'ابحث بالاسم أو رقم الهاتف...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                  ),
                );
              },
              onSelected: (selectedParty) {
                setState(() {
                  _selectedPartyId = selectedParty.id;
                });
                loadData();
              },
            ),
          ),
        ],
      ),
    );
  }
}

