import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import 'chart_of_accounts_detail_panel.dart';
import '../../services/network_service.dart';
import '../../domain/models/account_facts.dart';
import '../picpos_shell/picpos_kpi_row.dart';
import '../picpos_shell/picpos_toolbar.dart';
import '../picpos_shell/picpos_dialog.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../services/printing/report_pdf_generator.dart';
import '../../core/widgets/app_toast.dart';
import '../screens/coa/coa_shared.dart';
import '../screens/coa/coa_dialogs.dart';
import '../screens/coa/coa_rollup.dart';
import '../screens/coa/coa_tree_node.dart';
import '../../data/providers/providers.dart';
import '../../services/coa_management_service.dart';

/// Chart of Accounts — Hierarchical tree-structured account management screen
/// Standards: IFRS (IAS 1), Egyptian Accounting Standards
/// Supports parent-child relationships for main and sub-accounts
class ChartOfAccountsPicPosScreen extends ConsumerStatefulWidget {
  const ChartOfAccountsPicPosScreen({super.key});

  @override
  ConsumerState<ChartOfAccountsPicPosScreen> createState() =>
      _ChartOfAccountsPicPosScreenState();
}

class _ChartOfAccountsPicPosScreenState
    extends ConsumerState<ChartOfAccountsPicPosScreen> {
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

  /// الحسابُ المعروضُ في اللوح الجانبيّ — أو `null` فلا لوحَ.
  int? _panelAccountId;

  /// وضعُ الإنشاء: اللوحُ مفتوحٌ على حسابٍ جديدٍ تحت هذا الأب (أو جذرٍ).
  bool _creating = false;
  int? _createParentId;

  void _openPanelFor(int accountId) => setState(() {
        _creating = false;
        _createParentId = null;
        _panelAccountId = accountId;
      });

  void _startCreate({int? parentId}) => setState(() {
        _creating = true;
        _createParentId = parentId;
        _panelAccountId = null;
      });

  void _closePanel() => setState(() {
        _creating = false;
        _createParentId = null;
        _panelAccountId = null;
      });

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(accountingRepositoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: StreamBuilder<List<Account>>(
                stream: repo.watchAllAccounts(),
                builder: (context, snapshot) {
                  final allAccounts = snapshot.data ?? const <Account>[];
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

                  // ⚠️ العدّاداتُ من القائمة **غيرِ المرشَّحة**: الترشيحُ
                  //    يُخفي صفوفاً ولا يحذفها، فعدّادٌ يتبع البحثَ يقول
                  //    للمستخدم إنّ حساباتِه نقصت. والمعروضُ يُذكر على حدة.
                  final roots =
                      allAccounts.where((a) => a.parentId == null).length;
                  final leaves = allAccounts
                      .where((a) => !allAccounts.any((c) => c.parentId == a.id))
                      .length;

                  return PicPosScreenScaffold(
                    title: 'دليل الحسابات',
                    subtitle: 'IFRS / IAS 1 — شجرةُ الحسابات المحاسبية',
                    icon: PhosphorIconsBold.treeStructure,
                    headerSearch: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'بحث بالرمز أو الاسم...',
                        prefixIcon: const Icon(
                            PhosphorIconsBold.magnifyingGlass, size: 16),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon:
                                    const Icon(PhosphorIconsBold.x, size: 14),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    // ⚠️ الفعلُ الأساسيُّ وحدَه في الترويسة. خمسةُ أفعالٍ
                    //    معها بحثٌ وعنوانٌ تفيض **٣٠٧ بكسل عند ١٢٨٠** ولا
                    //    تفيض عند ١٩٢٠ — أمسكه اختبارُ التركيب بعرضَين.
                    //    و`headerActions` صفٌّ لا يلتفّ، بخلاف `PicPosToolbar`.
                    headerActions: [_addAccountButton(context)],
                    // ⚠️ ومرشِّحُ حسابات الضريبة كان في الشريط المتدرّج
                    //    المحذوف — واللِّنتُ وحدَه كشف غيابَه
                    //    (`_showTaxAccountsOnly` صار بلا مُسنِد). فعلٌ حقيقيٌّ
                    //    كاد يسقط في إعادة التنسيق بلا أن يلاحظه أحد.
                    toolbar: PicPosToolbar(
                      children: [
                        FilterChip(
                          selected: _showTaxAccountsOnly,
                          onSelected: (v) =>
                              setState(() => _showTaxAccountsOnly = v),
                          avatar: const Icon(PhosphorIconsBold.percent,
                              size: 14),
                          label: const Text('حسابات الضريبة'),
                          labelStyle: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700),
                          showCheckmark: false,
                        ),
                        ..._secondaryActions(context),
                      ],
                    ),
                    subHeader: PicPosKpiRow(
                      kpis: [
                        PicPosKpi(
                          label: 'إجمالي الحسابات',
                          value: '${allAccounts.length}',
                          icon: PhosphorIconsBold.treeStructure,
                          tint: AppColors.primary,
                        ),
                        PicPosKpi(
                          label: 'حسابات رئيسية',
                          value: '$roots',
                          icon: PhosphorIconsBold.folder,
                          tint: AppColors.info,
                        ),
                        PicPosKpi(
                          label: 'حسابات تفصيليّة',
                          value: '$leaves',
                          icon: PhosphorIconsBold.file,
                          tint: AppColors.success,
                        ),
                        PicPosKpi(
                          label: 'المعروض بعد الترشيح',
                          value: '${filtered.length}',
                          icon: PhosphorIconsBold.funnel,
                          tint: AppColors.textMuted,
                        ),
                      ],
                    ),
                    body: !snapshot.hasData
                        ? const Center(child: CircularProgressIndicator())
                        // ⚠️ **لوحان بـ`flex` لا بعرضٍ ثابت**: لوحٌ بعرضٍ
                        //    ثابتٍ بجوار شجرةٍ يفيض عند العروض الصغيرة
                        //    ويُبتِر الشجرةَ — والشجرةُ هي ما يُحرَّر منه.
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 3,
                                child: ListView(
                                  padding: EdgeInsets.zero,
                                  children:
                                      kAccountTypeConfig.entries.map((entry) {
                                    final type = entry.key;
                                    final info = entry.value;
                                    final typeAccounts = filtered
                                        .where((a) => a.accountType == type)
                                        .toList();
                                    return _buildAccountGroup(
                                        context,
                                        repo,
                                        type,
                                        info,
                                        typeAccounts,
                                        allAccounts,
                                        rollup);
                                  }).toList(),
                                ),
                              ),
                              if (_creating || _panelAccountId != null) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: _buildDetailPanel(repo, allAccounts),
                                ),
                              ],
                            ],
                          ),
                  );
                },
      ),
    );
  }

  /// اللوحُ الجانبيُّ — إنشاءً وتعديلاً في مكانٍ واحد.
  ///
  /// ⚠️ **و`key` من معرّف الحساب**: بدونها يُعاد استعمالُ حالةِ اللوح عند
  /// تبديل الاختيار، فتبقى حقولُ الحساب السابق معروضةً على الجديد — ويُحفَظ
  /// اسمُ حسابٍ على آخر.
  Widget _buildDetailPanel(
    IAccountingRepository repo,
    List<Account> allAccounts,
  ) {
    final current = _panelAccountId == null
        ? null
        : allAccounts.where((a) => a.id == _panelAccountId).firstOrNull;

    // ⚠️ الاختيارُ يُقرأ من القائمة الحيّة: حسابٌ حُذف أو أُخفي يترك لوحاً
    //    يعمل على ما لا يُرى.
    if (!_creating && current == null) {
      return const SizedBox.shrink();
    }

    AccountParentOption opt(Account a) =>
        (id: a.id, code: a.code, name: a.name, accountType: a.accountType);

    final parentId = _creating ? _createParentId : current?.parentId;
    final parent =
        allAccounts.where((a) => a.id == parentId).map(opt).firstOrNull;

    return AccountDetailPanel(
      key: ValueKey('coa_panel_${_creating ? 'new_$_createParentId' : current!.id}'),
      account: current == null
          ? null
          : AccountPanelValue(
              id: current.id,
              code: current.code,
              name: current.name,
              accountType: current.accountType,
              accountNature: current.accountNature,
              isActive: current.isActive,
              isSystem: current.isSystem,
              isHiddenFromEntries: current.isHiddenFromEntries,
              parentId: current.parentId,
            ),
      parent: parent,
      allAccounts: [for (final a in allAccounts) opt(a)],
      onClose: _closePanel,
      onOpenLedger:
          current == null ? null : () => showAccountLedger(context, repo, current),
      onSave: ({
        required String code,
        required String name,
        required String accountType,
        required String accountNature,
        required bool isActive,
        required bool isHiddenFromEntries,
        int? parentId,
      }) async {
        try {
          if (current == null) {
            final id = await repo.createAccount(
              code: code,
              name: name,
              accountType: accountType,
              parentId: parentId,
              accountNature: accountNature,
            );
            NetworkService.instance.broadcastChange('accounts');
            if (!mounted) return;
            AppToast.show(context, 'تم إنشاء الحساب');
            // يُفتَح المُنشأُ في اللوح: المستخدمُ يرى ما صنع، ويُتابع تحريرَه.
            _openPanelFor(id);
          } else {
            await repo.updateAccount(
              current.id,
              name: name,
              // ⚠️ رمزُ حساب النظام لا يُمرَّر أصلاً — الحقلُ معطَّلٌ فوقه
              //    بسببٍ ظاهر، وتمريرُه كان يكتبه من قيمةٍ لم تُحرَّر.
              code: current.isSystem ? null : code,
              isActive: isActive,
              isHiddenFromEntries: isHiddenFromEntries,
              accountNature: accountNature,
            );
            NetworkService.instance.broadcastChange('accounts');
            if (!mounted) return;
            AppToast.show(context, 'تم تحديث الحساب');
          }
        } catch (e) {
          if (mounted) {
            AppToast.show(context, 'خطأ: $e', type: ToastType.error);
          }
        }
      },
    );
  }

  /// الفعلُ الأساسيّ — وحدَه في الترويسة.
  Widget _addAccountButton(BuildContext context) => ElevatedButton.icon(
        onPressed: () => _startCreate(),
        icon: const Icon(PhosphorIconsBold.plus, size: 16),
        label: const Text('إضافة حساب رئيسي'),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
        ),
      );

  /// الأفعالُ الثانويّة — في الشريط لأنّه `Wrap` يلتفّ، لا صفٌّ يفيض.
  ///
  /// ⚠️ ولا فعلَ يسقط في النقل: توسيع/طي · طباعة · تصدير · استيراد.
  /// إعادةُ التنسيق أسهلُ مكانٍ يختفي فيه زرٌّ بلا أن يلاحظه أحد — ويقيسها
  /// الاختبارُ واحداً واحداً.
  List<Widget> _secondaryActions(BuildContext context) {
    return [
      OutlinedButton.icon(
        onPressed: () {
          setState(() {
            if (_expandedAccounts.isEmpty) {
              final r = ref.read(accountingRepositoryProvider);
              r.getAllAccounts().then((accounts) {
                setState(() {
                  _expandedAccounts.addAll(accounts
                      .where((a) => a.parentId != null)
                      .map((a) => a.parentId!));
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
          size: 15,
        ),
        label: Text(_expandedAccounts.isEmpty ? 'توسيع الكل' : 'طي الكل'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 34),
          textStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      OutlinedButton.icon(
        onPressed: () => _printChartOfAccounts(context),
        icon: const Icon(PhosphorIconsBold.printer, size: 15),
        label: const Text('طباعة/PDF'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 34),
          textStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      IconButton(
        onPressed: _handleExport,
        icon: const Icon(PhosphorIconsBold.microsoftExcelLogo, size: 18),
        tooltip: 'تصدير الدليل (Excel)',
      ),
      IconButton(
        onPressed: _handleImport,
        icon: const Icon(PhosphorIconsBold.fileArrowUp, size: 18),
        tooltip: 'استيراد الدليل (Excel)',
      ),
    ];
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
                          '${accounts.length} حساب',
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
      // ⚠️ **الحواراتُ لم تعد تُفتَح من هنا** — قرارُ المالك: لوحٌ جانبيٌّ
      //    يحلّ محلَّها تماماً. و`coa_dialogs` تبقى كما هي لفرع UralCash.
      case 'sub':
        _startCreate(parentId: account.id);
        setState(() => _expandedAccounts.add(account.id));
      case 'ledger':
        // نقرةُ الصفّ تختار في اللوح كما يرسم التصميم؛ ودفترُ الأستاذ
        // يبقى في قائمة الصفّ فلا يضيع فعلٌ.
        _openPanelFor(account.id);
      case 'edit':
        _openPanelFor(account.id);
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
              ? 'تم إخفاء "${account.name}" من سندات القيد'
              : 'تم إظهار "${account.name}" في سندات القيد',
          type: ToastType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    }
  }

  /// Print Chart of Accounts as PDF
  Future<void> _printChartOfAccounts(BuildContext context) async {
    try {
      final repo = ref.read(accountingRepositoryProvider);
      final accounts = await repo.getAllAccounts();
      if (accounts.isEmpty) {
        if (mounted) AppToast.show(context, 'لا توجد حسابات للطباعة', type: ToastType.warning);
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
        accountName: 'دليل الحسابات الكامل',
        data: rows.map((r) {
          if (r['is_header'] == true) {
            return {
              'entry_date': DateTime.now(),
              'entry_number': '',
              'description': '═══ ${r['label']} (${r['count']} حساب) ═══',
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
            'description': '$prefix${r['name']}${r['is_system'] == true ? ' [نظام]' : ''}',
            'debit': 0.0,
            'credit': 0.0,
            'balance': (r['balance'] as double?) ?? 0.0,
          };
        }).toList(),
      );
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
    }
  }

  Future<void> _handleExport() async {
    try {
      final path = await _coaService.exportCoa();
      if (path != null && mounted) {
        AppToast.show(context, 'تم تصدير الدليل بنجاح إلى: $path', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'فشل التصدير: $e', type: ToastType.error);
    }
  }

  Future<void> _handleImport() async {
    try {
      final result = await _coaService.pickAndImportCoa(context);
      if (result.totalRows > 0 && mounted) {
        if (result.failed == 0) {
          AppToast.show(context, 'تم استيراد ${result.success} سجل بنجاح ✓');
        } else {
          AppToast.show(
            context,
            'تم استيراد ${result.success} سجل (${result.failed} فشل)',
            type: ToastType.warning,
          );
          // Show errors in an alert if many
          if (result.errors.isNotEmpty) {
            _showImportErrors(result.errors);
          }
        }
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'فشل الاستيراد: $e', type: ToastType.error);
    }
  }

  void _showImportErrors(List<String> errors) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: PicPosDialog(
          icon: PhosphorIconsBold.warningCircle,
          title: 'أخطاء الاستيراد',
          // ⚠️ العددُ الكاملُ في السطر الخافت: القائمةُ تعرض عشرةً فقط،
          //    فمن رأى عشرةً ظنّها كلَّ الأخطاء وأصلحها ثمّ فوجئ بالباقي.
          subtitle: errors.length > 10
              ? 'أوّلُ ١٠ من ${errors.length} خطأً'
              : '${errors.length} خطأ',
          accent: AppColors.error,
          width: 520,
          onCancel: () => Navigator.pop(context),
          cancelLabel: 'إغلاق',
          body: [
            for (final e in errors.take(10)) Text('• $e'),
          ],
        ),
      ),
    );
  }
}
