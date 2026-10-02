import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import 'chart_of_accounts_detail_panel.dart';
import 'chart_of_accounts_insight.dart';
import 'chart_of_accounts_overview.dart';
import 'chart_of_accounts_search.dart';
import 'general_ledger_picpos_screen.dart';
import '../../services/network_service.dart';
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

  /// الحسابُ المختارُ في اللوح — أو `null` فاللوحُ على حالته الفارغة.
  ///
  /// ⚠️ **اللوحُ لا يختفي** (البند ١٩، المرحلة G): الشجرةُ والتفاصيلُ ظاهرتان
  /// معاً، و`null` يرسم إرشاداً لا فراغاً.
  int? _panelAccountId;

  /// وضعُ الإنشاء: اللوحُ مفتوحٌ على حسابٍ جديدٍ تحت هذا الأب (أو جذرٍ).
  bool _creating = false;
  int? _createParentId;

  /// التحريرُ داخلَ اللوح — نموذجُ `AccountDetailPanel` بدل العرض.
  bool _editing = false;

  /// الاختيارُ قبل «إضافة» — يعود إليه «رجوع» من نموذج الإنشاء.
  int? _beforeCreateId;

  /// آخرُ قائمةٍ حيّة — يقرؤها البحثُ في `onChanged` خارجَ `build`.
  List<Account> _latestAccounts = const [];

  /// رصيدُ المختار وحركاتُه — مخبّأٌ بمعرّفه كي لا يُعاد الطلبُ مع كلّ بناء.
  Future<AccountInsight>? _insight;
  int? _insightId;

  void _openPanelFor(int accountId) => setState(() {
        _creating = false;
        _createParentId = null;
        _editing = false;
        _panelAccountId = accountId;
      });

  void _startCreate({int? parentId}) => setState(() {
        _beforeCreateId = _creating ? _beforeCreateId : _panelAccountId;
        _creating = true;
        _editing = false;
        _createParentId = parentId;
        _panelAccountId = null;
      });

  /// «رجوع» من النموذج: من التحرير إلى العرض، ومن الإنشاء إلى ما كان مختاراً.
  void _closeForm() => setState(() {
        if (_creating) {
          _creating = false;
          _createParentId = null;
          _panelAccountId = _beforeCreateId;
          _beforeCreateId = null;
        }
        _editing = false;
      });

  void _closePanel() => setState(() {
        _creating = false;
        _createParentId = null;
        _editing = false;
        _panelAccountId = null;
      });

  Future<AccountInsight> _insightFor(IAccountingRepository repo, int id) {
    if (_insightId != id || _insight == null) {
      _insightId = id;
      _insight = loadAccountInsight(
        repo: repo,
        accountId: id,
        // ⚠️ نطاقُ الفروع الأمنيُّ نفسُه الذي يمرّره دفترُ الأستاذ.
        allowedBranches: () async {
          final scope = await ref.read(branchScopeProvider.future);
          return scope.hasFullAccess ? null : scope.allowedBranchIds;
        },
      );
    }
    return _insight!;
  }

  /// البحثُ: يرشّح الشجرةَ، ويوسّع إلى المطابق، ويختار أقربَه في اللوح.
  ///
  /// ⚠️ **لا يختار فوق نموذجٍ مفتوح**: تبديلُ الحساب أثناء التحرير أو
  /// الإنشاء يُسقط ما كُتب بصمت.
  void _onSearch(String value) {
    setState(() {
      _searchQuery = value;
      if (value.trim().isEmpty) return;
      final result = coaSearch(_searchRows(_latestAccounts), value);
      _expandedAccounts.addAll(result.ancestorIds);
      for (final a in _latestAccounts) {
        if (result.matchIds.contains(a.id)) _expandedTypes.add(a.accountType);
      }
      final best = result.bestMatchId;
      if (best != null && !_editing && !_creating) _panelAccountId = best;
    });
  }

  static List<CoaSearchRow> _searchRows(List<Account> accounts) => [
        for (final a in accounts)
          (id: a.id, parentId: a.parentId, code: a.code, name: a.name),
      ];

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(accountingRepositoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: StreamBuilder<List<Account>>(
                stream: repo.watchAllAccounts(),
                builder: (context, snapshot) {
                  final allAccounts = snapshot.data ?? const <Account>[];
                  _latestAccounts = allAccounts;
                  // Spec 135 BUG-E — roll-up computed over the UNFILTERED list
                  // so each parent's subtotal includes children hidden by the
                  // search/tax filter below.
                  final rollup = _rollupFor(allAccounts);
                  // المطابقُ **وأسلافُه** — فيُرسَم الحسابُ في موضعه من
                  // الشجرة لا جذراً بلا سياق (`chart_of_accounts_search`).
                  final visible = _searchQuery.trim().isEmpty
                      ? null
                      : coaSearch(_searchRows(allAccounts), _searchQuery)
                          .visibleIds;
                  final filtered0 = visible == null
                      ? allAccounts
                      : allAccounts
                          .where((a) => visible.contains(a.id))
                          .toList();
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
                    // الترويسةُ (`PicPosPageHeader`) تترجم العنوانَ بنفسها —
                    // فـ`tr()` هنا كانت ترجمةً مزدوجة تبحث عن «Chart of
                    // Accounts» في الكتالوج فتسجّل نقصاً.
                    title: 'دليل الحسابات',
                    subtitle: 'IFRS / IAS 1 — شجرةُ الحسابات المحاسبية',
                    icon: PhosphorIconsBold.treeStructure,
                    headerSearch: TextField(
                      key: const Key('coa_search'),
                      controller: _searchController,
                      onChanged: _onSearch,
                      onSubmitted: _onSearch,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: tr('بحث بالرمز أو الاسم...'),
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
                          label:  Text(tr('حسابات الضريبة')),
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
                          label: tr('إجمالي الحسابات'),
                          value: '${allAccounts.length}',
                          icon: PhosphorIconsBold.treeStructure,
                          tint: AppColors.primary,
                        ),
                        PicPosKpi(
                          label: tr('حسابات رئيسية'),
                          value: '$roots',
                          icon: PhosphorIconsBold.folder,
                          tint: AppColors.info,
                        ),
                        PicPosKpi(
                          label: tr('حسابات تفصيليّة'),
                          value: '$leaves',
                          icon: PhosphorIconsBold.file,
                          tint: AppColors.success,
                        ),
                        PicPosKpi(
                          label: tr('المعروض بعد الترشيح'),
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
                        //
                        // 🔴 **والاثنان ظاهران دائماً** (البند ١٩، المرحلة G):
                        //    الشجرةُ ٤٠٪ واللوحُ ٦٠٪ جنباً إلى جنب، وتحت
                        //    ٧٦٠ بكسلاً يُكدَّسان رأسيّاً بدل أن ينضغطا.
                        : LayoutBuilder(builder: (context, c) {
                            final tree = ListView(
                              key: const Key('coa_tree'),
                              padding: EdgeInsets.zero,
                              children:
                                  kAccountTypeConfig.entries.map((entry) {
                                final type = entry.key;
                                final info = entry.value;
                                final typeAccounts = filtered
                                    .where((a) => a.accountType == type)
                                    .toList();
                                return _buildAccountGroup(context, repo, type,
                                    info, typeAccounts, allAccounts, rollup);
                              }).toList(),
                            );
                            final panel = _buildDetailPanel(repo, allAccounts);
                            final wide = c.maxWidth >= 760;
                            return Flex(
                              direction:
                                  wide ? Axis.horizontal : Axis.vertical,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: wide ? 4 : 5, child: tree),
                                SizedBox(
                                    width: wide ? 12 : 0,
                                    height: wide ? 0 : 12),
                                Expanded(flex: wide ? 6 : 5, child: panel),
                              ],
                            );
                          }),
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
    //    يعمل على ما لا يُرى — فيعود اللوحُ إلى حالته الفارغة.
    if (!_creating && current == null) {
      return const CoaEmptyPanel();
    }

    AccountParentOption opt(Account a) =>
        (id: a.id, code: a.code, name: a.name, accountType: a.accountType);

    AccountPanelValue value(Account a) => AccountPanelValue(
          id: a.id,
          code: a.code,
          name: a.name,
          accountType: a.accountType,
          accountNature: a.accountNature,
          isActive: a.isActive,
          isSystem: a.isSystem,
          isHiddenFromEntries: a.isHiddenFromEntries,
          parentId: a.parentId,
        );

    // العرضُ — والتحريرُ زرٌّ فيه يفتح النموذجَ في المكان نفسِه.
    if (!_creating && !_editing && current != null) {
      final byId = {for (final a in allAccounts) a.id: a};
      final path = <AccountParentOption>[];
      final seen = <int>{current.id};
      var p = current.parentId;
      // `seen` حارسُ حلقةٍ على بياناتٍ تالفة.
      while (p != null && seen.add(p) && byId[p] != null) {
        path.insert(0, opt(byId[p]!));
        p = byId[p]!.parentId;
      }
      return AccountOverviewPanel(
        key: ValueKey('coa_overview_${current.id}'),
        account: value(current),
        path: path,
        childCount: allAccounts.where((a) => a.parentId == current.id).length,
        insight: _insightFor(repo, current.id),
        onEdit: () => setState(() => _editing = true),
        onAddChild: () => _handleAccountAction(current, 'sub'),
        onOpenLedger: (insight) => _openGeneralLedger(current, insight),
        onClose: _closePanel,
        onSelectAncestor: _openPanelFor,
      );
    }

    final parentId = _creating ? _createParentId : current?.parentId;
    final parent =
        allAccounts.where((a) => a.id == parentId).map(opt).firstOrNull;

    return AccountDetailPanel(
      key: ValueKey('coa_panel_${_creating ? 'new_$_createParentId' : current!.id}'),
      account: current == null ? null : value(current),
      parent: parent,
      allAccounts: [for (final a in allAccounts) opt(a)],
      onClose: _closeForm,
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
            // نفسُ حارس حوار الإنشاء (`showAddAccountDialog`، Feature 005
            // Phase 8): اسمٌ نشطٌ مكرَّرٌ تحت الأب نفسِه يصنع صفَّين لكيانٍ
            // واحد. يُقرأ من القائمة الحيّة بدل استعلام القاعدة من العرض.
            final dup = allAccounts
                .where((a) =>
                    a.isActive && a.parentId == parentId && a.name == name)
                .firstOrNull;
            if (dup != null) {
              AppToast.show(
                context,
                tr('يوجد حساب باسم "{trimmedName}" تحت نفس الأب (الكود {p0}). لتجنّب التكرار، أنشئ الصندوق من شاشة "إدارة الصناديق" وسيتم ربط الحساب تلقائياً.', {'trimmedName': name, 'p0': dup.code}),
                type: ToastType.error,
              );
              return;
            }
            final id = await repo.createAccount(
              code: code,
              name: name,
              accountType: accountType,
              parentId: parentId,
              accountNature: accountNature,
            );
            NetworkService.instance.broadcastChange('accounts');
            if (!mounted) return;
            AppToast.show(context, tr('تم إنشاء الحساب'));
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
            AppToast.show(context, tr('تم تحديث الحساب'));
            // يعود اللوحُ إلى العرض: المستخدمُ يرى ما حفظ.
            setState(() => _editing = false);
          }
        } catch (e) {
          if (mounted) {
            AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
          }
        }
      },
    );
  }

  /// دفترُ الأستاذ مرشَّحاً على الحساب — وبمدى السنة التي قرأ اللوحُ
  /// أرصدتَها، كي يطابق الدفترُ ما رآه المستخدمُ للتوّ.
  void _openGeneralLedger(Account account, AccountInsight? insight) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GeneralLedgerPicPosScreen(
          initialAccountId: account.id,
          initialAccountLabel: '${account.code} - ${trData(account.name)}',
          initialFrom: insight?.from,
          initialTo: insight?.to,
        ),
      ),
    );
  }

  /// الفعلُ الأساسيّ — وحدَه في الترويسة.
  Widget _addAccountButton(BuildContext context) => ElevatedButton.icon(
        onPressed: () => _startCreate(),
        icon: const Icon(PhosphorIconsBold.plus, size: 16),
        label:  Text(tr('إضافة حساب رئيسي')),
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
        label: Text(_expandedAccounts.isEmpty ? tr('توسيع الكل') : tr('طي الكل')),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 34),
          textStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      OutlinedButton.icon(
        onPressed: () => _printChartOfAccounts(context),
        icon: const Icon(PhosphorIconsBold.printer, size: 15),
        label:  Text(tr('طباعة/PDF')),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 34),
          textStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      IconButton(
        onPressed: _handleExport,
        icon: const Icon(PhosphorIconsBold.microsoftExcelLogo, size: 18),
        tooltip: tr('تصدير الدليل (Excel)'),
      ),
      IconButton(
        onPressed: _handleImport,
        icon: const Icon(PhosphorIconsBold.fileArrowUp, size: 18),
        tooltip: tr('استيراد الدليل (Excel)'),
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
                  selectedAccountId: _creating ? null : _panelAccountId,
                  // نقرةُ الأب تطويه/تبسطه **وتختاره** — الأبُ حسابٌ له
                  // رصيدٌ وحركاتٌ تُعرَض كذلك.
                  onToggle: () => _handleAccountAction(account, '_toggle'),
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
          _creating = false;
          _createParentId = null;
          _editing = false;
          _panelAccountId = account.id;
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
        // التحريرُ داخلَ اللوح مباشرةً — لا حوار.
        _openPanelFor(account.id);
        setState(() => _editing = true);
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
        child: PicPosDialog(
          icon: PhosphorIconsBold.warningCircle,
          title: tr('أخطاء الاستيراد'),
          // ⚠️ العددُ الكاملُ في السطر الخافت: القائمةُ تعرض عشرةً فقط،
          //    فمن رأى عشرةً ظنّها كلَّ الأخطاء وأصلحها ثمّ فوجئ بالباقي.
          subtitle: errors.length > 10
              ? tr('أوّلُ ١٠ من {p0} خطأً', {'p0': errors.length})
              : tr('{p0} خطأ', {'p0': errors.length}),
          accent: AppColors.error,
          width: 520,
          onCancel: () => Navigator.pop(context),
          cancelLabel: tr('إغلاق'),
          body: [
            for (final e in errors.take(10)) Text('• $e'),
          ],
        ),
      ),
    );
  }
}
