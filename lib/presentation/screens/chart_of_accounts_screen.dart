import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../services/printing/report_pdf_generator.dart';
import '../../core/widgets/app_toast.dart';
import 'coa/coa_shared.dart';
import 'coa/coa_dialogs.dart';
import 'coa/coa_rollup.dart';
import 'coa/coa_tree_node.dart';
import '../../data/providers/providers.dart';
import '../../services/coa_management_service.dart';

/// Chart of Accounts — Hierarchical tree-structured account management screen
/// Standards: IFRS (IAS 1), Egyptian Accounting Standards
/// Supports parent-child relationships for main and sub-accounts
class ChartOfAccountsScreen extends ConsumerStatefulWidget {
  const ChartOfAccountsScreen({super.key});

  @override
  ConsumerState<ChartOfAccountsScreen> createState() =>
      _ChartOfAccountsScreenState();
}

class _ChartOfAccountsScreenState
    extends ConsumerState<ChartOfAccountsScreen> {
  String _searchQuery = '';
  bool _showTaxAccountsOnly = false;
  final _searchController = TextEditingController();
  // Spec 135 BUG-E — memoize the COA roll-up so expand/collapse rebuilds don't
  // recompute it. Recomputed only when the underlying account list changes.
  List<Account>? _rollupSource;
  CoaRollup? _rollupCache;
  CoaRollup _rollupFor(List<Account> allAccounts) {
    if (!identical(_rollupSource, allAccounts)) {
      _rollupSource = allAccounts;
      // Map Account rows → plain records so the pure helper stays off a
      // data/database import (Constitution §IV / R7).
      _rollupCache = CoaRollup.compute(
        allAccounts.map((a) => (id: a.id, parentId: a.parentId, balance: a.balance)),
      );
    }
    return _rollupCache!;
  }
  final Set<int> _expandedAccounts = {};
  final Set<String> _expandedTypes = {
    'asset',
    'liability',
    'equity',
    'revenue',
    'expense',
  };

  late final CoaManagementService _coaService;

  @override
  void initState() {
    super.initState();
    // ISS-06: Route through coaManagementServiceProvider instead of direct DB access
    _coaService = ref.read(coaManagementServiceProvider) as CoaManagementService;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(accountingRepositoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(
          children: [
            _buildHeader(context),
            _buildSearchBar(),
            Expanded(
              child: StreamBuilder<List<Account>>(
                stream: repo.watchAllAccounts(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final allAccounts = snapshot.data!;
                  // Spec 135 BUG-E — roll-up computed over the UNFILTERED list
                  // so each parent's subtotal includes children hidden by the
                  // search/tax filter below.
                  final rollup = _rollupFor(allAccounts);
                  final filtered0 = _searchQuery.isEmpty
                      ? allAccounts
                      : allAccounts.where((a) =>
                          a.name.contains(_searchQuery) ||
                          a.code.contains(_searchQuery)).toList();
                  final filtered = _showTaxAccountsOnly
                      ? filtered0.where((a) =>
                          a.name.contains('ضري') ||
                          a.name.contains('ضريب') ||
                          a.name.contains('VAT') ||
                          a.name.toLowerCase().contains('tax')).toList()
                      : filtered0;

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: kAccountTypeConfig.entries.map((entry) {
                      final type = entry.key;
                      final info = entry.value;
                      final typeAccounts = filtered
                          .where((a) => a.accountType == type)
                          .toList();
                      return _buildAccountGroup(
                          context, repo, type, info, typeAccounts, allAccounts, rollup);
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              PhosphorIconsBold.treeStructure,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('دليل الحسابات'),
                style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                tr('IFRS / IAS 1 - شجرة الحسابات المحاسبية'),
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const Spacer(),
          // Expand/Collapse all
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                if (_expandedAccounts.isEmpty) {
                  final r = ref.read(accountingRepositoryProvider);
                  r.getAllAccounts().then((accounts) {
                    setState(() {
                      _expandedAccounts.addAll(
                        accounts.where((a) => a.parentId != null).map((a) => a.parentId!),
                      );
                    });
                  });
                } else {
                  _expandedAccounts.clear();
                }
              });
            },
            icon: Icon(
              _expandedAccounts.isEmpty
                  ? PhosphorIconsBold.arrowsOut
                  : PhosphorIconsBold.arrowsIn,
              size: 16,
            ),
            label: Text(
              _expandedAccounts.isEmpty ? tr('توسيع الكل') : tr('طي الكل'),
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          // Tax accounts filter
          FilterChip(
            selected: _showTaxAccountsOnly,
            onSelected: (v) => setState(() => _showTaxAccountsOnly = v),
            avatar: Icon(
              PhosphorIconsBold.percent,
              size: 14,
              color: _showTaxAccountsOnly ? Colors.white : AppColors.warning,
            ),
            label: Text(
              tr('حسابات الضريبة'),
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: _showTaxAccountsOnly ? Colors.white : AppColors.warning,
              ),
            ),
            selectedColor: AppColors.warning,
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            side: BorderSide(
              color: _showTaxAccountsOnly
                  ? AppColors.warning
                  : Colors.white.withValues(alpha: 0.4),
            ),
            showCheckmark: false,
          ),
          const SizedBox(width: 8),
          // Print/Export COA
          OutlinedButton.icon(
            onPressed: () => _printChartOfAccounts(context),
            icon: const Icon(PhosphorIconsBold.printer, size: 16),
            label: Text(tr('طباعة/PDF'), style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          // Export COA
          IconButton(
            onPressed: _handleExport,
            icon: const Icon(PhosphorIconsBold.microsoftExcelLogo, color: Colors.white),
            tooltip: tr('تصدير للدليل (Excel)'),
          ),
          // Import COA
          IconButton(
            onPressed: _handleImport,
            icon: const Icon(PhosphorIconsBold.fileArrowUp, color: Colors.white),
            tooltip: tr('استيراد الدليل (Excel)'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => showAddAccountDialog(context, ref,
                ref.read(accountingRepositoryProvider), null, null),
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label: Text(tr('إضافة حساب رئيسي'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SEARCH BAR
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: tr('بحث بالرمز أو الاسم...'),
          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(PhosphorIconsBold.x, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ACCOUNT GROUP
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildAccountGroup(BuildContext context, IAccountingRepository repo,
      String type, AccountTypeInfo info, List<Account> accounts,
      List<Account> allAccounts, CoaRollup rollup) {
    final isExpanded = _expandedTypes.contains(type);
    final rootAccounts = accounts
        .where((a) => a.parentId == null || !accounts.any((p) => p.id == a.parentId))
        .toList();
    // Spec 135 BUG-E — total over ROOTS only using the roll-up, so it matches
    // the per-node subtotals and never double-counts (a flat fold of own
    // balances is numerically equal, but this stays consistent with the tree).
    final totalBalance = rollup.grandTotalOfRoots(
        rootAccounts.map((a) => (id: a.id, parentId: a.parentId, balance: a.balance)));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: info.color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              if (isExpanded) {
                _expandedTypes.remove(type);
              } else {
                _expandedTypes.add(type);
              }
            }),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: info.color.withValues(alpha: 0.06),
                borderRadius: isExpanded
                    ? const BorderRadius.vertical(top: Radius.circular(12))
                    : BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: info.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(info.icon, color: info.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${info.label} (${info.range})',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: info.color,
                          ),
                        ),
                        Text(
                          tr('{p0} حساب', {'p0': accounts.length}),
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatAccountAmount(totalBalance),
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: totalBalance >= 0
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      PhosphorIconsBold.caretLeft,
                      size: 16,
                      color: info.color,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Account Tree
          if (isExpanded) ...[
            const Divider(height: 1),
            ...rootAccounts.map((account) => CoaTreeNode(
                  account: account,
                  typeInfo: info,
                  allTypeAccounts: accounts,
                  depth: 0,
                  repo: repo,
                  rollup: rollup,
                  expandedAccounts: _expandedAccounts,
                  onToggle: () => setState(() {
                    if (_expandedAccounts.contains(account.id)) {
                      _expandedAccounts.remove(account.id);
                    } else {
                      _expandedAccounts.add(account.id);
                    }
                  }),
                  onAction: _handleAccountAction,
                )),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════

  void _handleAccountAction(Account account, String action) {
    final repo = ref.read(accountingRepositoryProvider);
    switch (action) {
      case '_toggle':
        setState(() {
          if (_expandedAccounts.contains(account.id)) {
            _expandedAccounts.remove(account.id);
          } else {
            _expandedAccounts.add(account.id);
          }
        });
      case 'sub':
        showAddAccountDialog(context, ref, repo, account.id, account,
            onAccountAdded: () {
          if (mounted) setState(() => _expandedAccounts.add(account.id));
        });
      case 'ledger':
        showAccountLedger(context, repo, account);
      case 'edit':
        showEditAccountDialog(context, repo, account);
      case 'delete':
        confirmDeleteAccount(context, repo, account);
      case 'toggle_hide':
        _toggleHideFromEntries(repo, account);
    }
  }

  Future<void> _toggleHideFromEntries(IAccountingRepository repo, Account account) async {
    try {
      final newValue = !account.isHiddenFromEntries;
      await repo.updateAccount(
        account.id,
        isHiddenFromEntries: newValue,
      );
      if (mounted) {
        AppToast.show(
          context,
          newValue
              ? tr('تم إخفاء "{p0}" من سندات القيد', {'p0': account.name})
              : tr('تم إظهار "{p0}" في سندات القيد', {'p0': account.name}),
          type: ToastType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  /// Print Chart of Accounts as PDF
  Future<void> _printChartOfAccounts(BuildContext context) async {
    try {
      final repo = ref.read(accountingRepositoryProvider);
      final accounts = await repo.getAllAccounts();
      if (!context.mounted) return;
      if (accounts.isEmpty) {
        AppToast.show(context, tr('لا توجد حسابات للطباعة'), type: ToastType.warning);
        return;
      }

      final rows = <Map<String, dynamic>>[];
      for (final typeEntry in kAccountTypeConfig.entries) {
        final type = typeEntry.key;
        final info = typeEntry.value;
        final typeAccounts = accounts.where((a) => a.accountType == type).toList();
        if (typeAccounts.isEmpty) continue;

        rows.add({
          'is_header': true,
          'label': '${info.label} (${info.range})',
          'count': typeAccounts.length,
          'balance': typeAccounts.fold(0.0, (sum, a) => sum + a.balance),
        });

        typeAccounts.sort((a, b) => a.code.compareTo(b.code));
        for (final account in typeAccounts) {
          final depth = accounts.where((a) => a.id == account.parentId).isNotEmpty ? 1 : 0;
          rows.add({
            'code': account.code,
            'name': account.name,
            'balance': account.balance,
            'depth': depth,
            'is_system': account.isSystem,
          });
        }
      }

      await ReportPdfGenerator.printGeneralLedger(
        accountName: tr('دليل الحسابات الكامل'),
        data: rows.map((r) {
          if (r['is_header'] == true) {
            return {
              'entry_date': DateTime.now(),
              'entry_number': '',
              'description': tr('═══ {p0} ({p1} حساب) ═══', {'p0': r['label'], 'p1': r['count']}),
              'debit': 0.0,
              'credit': 0.0,
              'balance': (r['balance'] as double?) ?? 0.0,
              'is_opening': true,
            };
          }
          final depth = r['depth'] as int? ?? 0;
          final prefix = depth > 0 ? '  ↳ ' : '';
          return {
            'entry_date': DateTime.now(),
            'entry_number': r['code'] ?? '',
            'description': tr('{prefix}{p0}{p1}', {'prefix': prefix, 'p0': r['name'], 'p1': r['is_system'] == true ? tr(' [نظام]') : ''}),
            'debit': 0.0,
            'credit': 0.0,
            'balance': (r['balance'] as double?) ?? 0.0,
          };
        }).toList(),
      );
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, tr('خطأ في الطباعة: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  Future<void> _handleExport() async {
    try {
      final path = await _coaService.exportCoa();
      if (path != null && mounted) {
        AppToast.show(context, tr('تم تصدير الدليل بنجاح إلى: {path}', {'path': path}), type: ToastType.success);
      }
    } catch (e) {
      if (mounted) AppToast.show(context, tr('فشل التصدير: {e}', {'e': e}), type: ToastType.error);
    }
  }

  Future<void> _handleImport() async {
    try {
      final result = await _coaService.pickAndImportCoa(context);
      if (result.totalRows > 0 && mounted) {
        if (result.failed == 0) {
          AppToast.show(context, tr('تم استيراد {p0} سجل بنجاح ✓', {'p0': result.success}));
        } else {
          AppToast.show(
            context,
            tr('تم استيراد {p0} سجل ({p1} فشل)', {'p0': result.success, 'p1': result.failed}),
            type: ToastType.warning,
          );
          // Show errors in an alert if many
          if (result.errors.isNotEmpty) {
            _showImportErrors(result.errors);
          }
        }
      }
    } catch (e) {
      if (mounted) AppToast.show(context, tr('فشل الاستيراد: {e}', {'e': e}), type: ToastType.error);
    }
  }

  void _showImportErrors(List<String> errors) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(tr('أخطاء الاستيراد'), style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: errors.length > 10 ? 10 : errors.length,
              itemBuilder: (context, idx) => Text('• ${errors[idx]}'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      ),
    );
  }
}
