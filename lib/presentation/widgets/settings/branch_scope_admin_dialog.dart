import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/database/extensions/branch_scope_cleanup_extension.dart';
import '../../../data/database/extensions/category_dedup_extension.dart';
import '../../../data/database/sync_interceptor.dart';
import '../../../data/providers/providers.dart';
import '../../../services/network_service.dart';

/// Phase 5C settings UI — admin-only diagnostic surface for the two
/// helpers shipped in Phase 5A.4 + 5B.7. Surfaces what's hidden from
/// the main UI:
///
///   * **حصر بيانات الفروع** — count cross-branch rows that landed
///     locally before the server-side filter (5A.1) was active, then
///     optionally delete them. Strong confirmation dialog gates the
///     destructive step (Stability Guarantee G2: dry-run + manual
///     confirmation; never auto-run).
///
///   * **تشخيص قيود اليومية** — find unbalanced JEs and JE lines
///     pointing to non-existent accounts (the silent failure modes
///     from 5B.3 / 5B.7). Read-only.
///
/// Both sections are no-ops for users without admin privileges. The
/// dialog itself can be opened from any settings entry via
/// [showBranchScopeAdminDialog].
void showBranchScopeAdminDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _BranchScopeAdminDialog(),
  );
}

class _BranchScopeAdminDialog extends ConsumerStatefulWidget {
  const _BranchScopeAdminDialog();

  @override
  ConsumerState<_BranchScopeAdminDialog> createState() =>
      _BranchScopeAdminDialogState();
}

class _BranchScopeAdminDialogState
    extends ConsumerState<_BranchScopeAdminDialog> {
  Map<String, int>? _foreignCounts;
  bool _scanningForeign = false;
  bool _wiping = false;

  List<Map<String, dynamic>>? _orphans;
  bool _scanningOrphans = false;

  List<Map<String, dynamic>>? _dupCategories;
  bool _scanningDupCategories = false;
  bool _mergingDupCategories = false;

  // Spec 084c — server-side branches dedup (visible only in server mode)
  List<DuplicateBranchGroup>? _branchDupGroups;
  bool _scanningBranchDups = false;
  bool _repairingBranchDups = false;

  // Spec 084d — server-side parties dedup (visible only in server mode)
  List<DuplicatePartyGroup>? _partyDupGroups;
  bool _scanningPartyDups = false;
  bool _repairingPartyDups = false;

  // Spec 114 — repair parties without a linked COA sub-account
  bool _repairingPartySubAccounts = false;
  Map<String, int>? _partySubAccountResult;

  // Spec 114b — re-post invoices whose auto-posted JE is missing
  bool _repairingInvoiceJEs = false;
  Map<String, int>? _invoiceJEResult;

  // Spec 114c — rewire existing JE lines from parent control account to
  // each party's sub-account
  bool _rewiringJELines = false;
  Map<String, int>? _rewireResult;

  // Spec 115b — stranded outbox cleanup
  int? _strandedCount;
  bool _scanningStranded = false;
  bool _clearingStranded = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                const Divider(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _branchCleanupSection(),
                        const SizedBox(height: 24),
                        _orphanDiagnosticSection(),
                        const SizedBox(height: 24),
                        _categoryDedupSection(),
                        if (NetworkService.instance.isServerRunning) ...[
                          const SizedBox(height: 24),
                          _branchServerDedupSection(),
                        ],
                        // Spec 088 USR-3 — surface the parties dedup tool
                        // on mirror too. The repair runs entirely on the
                        // local DB inside one Drift transaction (party_dao
                        // `repairDuplicateParties`) and emits NO writes to
                        // the server (the server's parties table is
                        // already canonical; the mirror simply collapses
                        // its own duplicate rows). FR-301 / FR-304.
                        if (NetworkService.instance.isServerRunning ||
                            SyncInterceptor.isMirrorMode) ...[
                          const SizedBox(height: 24),
                          _partyServerDedupSection(),
                        ],
                        // Spec 114 — repair parties without a sub-account
                        const SizedBox(height: 24),
                        _partySubAccountRepairSection(),
                        // Spec 114c — move historical JE lines from the
                        // parent control account to the now-existing
                        // sub-account. Without this step, ledger views
                        // for the freshly-minted sub-accounts stay empty.
                        const SizedBox(height: 24),
                        _rewireJELinesSection(),
                        // Spec 114b — re-post auto-posted JEs for invoices
                        // whose JE went missing entirely.
                        const SizedBox(height: 24),
                        _invoiceJERepairSection(),
                        // Spec 115b — clear stranded outbox rows left over
                        // from a paired-client → standalone/server flip.
                        const SizedBox(height: 24),
                        _strandedOutboxSection(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إغلاق'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return const Row(
      children: [
        Icon(PhosphorIconsBold.shield,
            color: AppColors.primary, size: 22),
        SizedBox(width: 10),
        Text(
          'أدوات صيانة المسؤول',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Spacer(),
      ],
    );
  }

  // ── Section 1: branch-scope cleanup ───────────────────────────────────
  Widget _branchCleanupSection() {
    final counts = _foreignCounts;
    final hasForeign = counts != null && counts.isNotEmpty;
    final totalForeign = counts == null
        ? 0
        : counts.values.fold<int>(0, (s, v) => s + v);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(PhosphorIconsBold.broom,
                    color: AppColors.warning, size: 20),
                SizedBox(width: 8),
                Text('حصر بيانات الفروع',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'فحص الصفوف التابعة لفروع أخرى التي بقيت محلياً قبل تفعيل '
              'الحصر من السيرفر. التنظيف الفعلي اختياري ويتم بعد عرض '
              'الأعداد لكل جدول.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: _scanningForeign
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                  label: const Text('فحص'),
                  onPressed: _scanningForeign ? null : _scanForeign,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: _wiping
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(PhosphorIconsBold.trash, size: 16),
                  label: Text(hasForeign
                      ? 'تنظيف ($totalForeign صف)'
                      : 'تنظيف'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        hasForeign ? AppColors.error : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                  onPressed:
                      (!hasForeign || _wiping) ? null : _confirmAndWipe,
                ),
              ],
            ),
            if (counts != null) ...[
              const SizedBox(height: 12),
              if (counts.isEmpty)
                const Text('✓ لا توجد صفوف من فروع أخرى محلياً.',
                    style: TextStyle(color: AppColors.success))
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الصفوف الموجودة لفروع غير مسموحة:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      ...counts.entries.map((e) => Text(
                          '  • ${e.key}: ${e.value}',
                          style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _scanForeign() async {
    setState(() {
      _scanningForeign = true;
      _foreignCounts = null;
    });
    try {
      final scope = await ref.read(branchScopeProvider.future);
      final allowed = scope.hasFullAccess
          ? <int>{} // empty == admin == nothing to clean
          : scope.allowedBranchIds!;
      final db = ref.read(databaseProvider);
      final result = await db.dryRunForeignBranchCounts(allowed);
      if (!mounted) return;
      setState(() => _foreignCounts = result);
    } catch (e) {
      if (mounted) AppToast.show(context, 'فشل الفحص: $e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _scanningForeign = false);
    }
  }

  Future<void> _confirmAndWipe() async {
    final counts = _foreignCounts!;
    final total = counts.values.fold<int>(0, (s, v) => s + v);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.warning, color: AppColors.error),
              SizedBox(width: 8),
              Text('تأكيد التنظيف'),
            ],
          ),
          content: Text(
            'سيتم حذف $total صف من قاعدة البيانات المحلية '
            'لأنها تتبع فروع غير مسموحة لهذا الجهاز.\n\n'
            'هذا الإجراء لا يمكن التراجع عنه.\n\n'
            'تأكد من وجود نسخة احتياطية حديثة قبل المتابعة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('تأكيد الحذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _wiping = true);
    try {
      final scope = await ref.read(branchScopeProvider.future);
      final allowed = scope.hasFullAccess ? <int>{} : scope.allowedBranchIds!;
      final db = ref.read(databaseProvider);
      final deleted = await db.wipeForeignBranchData(allowed);
      if (!mounted) return;
      setState(() {
        _foreignCounts = const {};
      });
      final deletedTotal = deleted.values.fold<int>(0, (s, v) => s + v);
      AppToast.show(context, 'تم حذف $deletedTotal صف بنجاح',
          type: ToastType.success);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل التنظيف: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _wiping = false);
    }
  }

  // ── Section 2: orphan-JE diagnostic ───────────────────────────────────
  Widget _orphanDiagnosticSection() {
    final orphans = _orphans;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(PhosphorIconsBold.stethoscope,
                    color: AppColors.info, size: 20),
                SizedBox(width: 8),
                Text('تشخيص قيود اليومية',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'فحص قيود غير متوازنة أو سطور تشير لحسابات غير موجودة. '
              'إجراء قراءة فقط — لا يعدّل أي بيانات.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: _scanningOrphans
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
              label: const Text('فحص'),
              onPressed: _scanningOrphans ? null : _scanOrphans,
            ),
            if (orphans != null) ...[
              const SizedBox(height: 12),
              if (orphans.isEmpty)
                const Text('✓ لا توجد قيود معطوبة.',
                    style: TextStyle(color: AppColors.success))
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('عدد المشاكل: ${orphans.length}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      ...orphans.take(20).map((o) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '  • قيد ${o['entryNumber']} '
                              '(${o['issue']}): ${o['detail']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          )),
                      if (orphans.length > 20)
                        Text('  … و ${orphans.length - 20} مشكلة أخرى',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _scanOrphans() async {
    setState(() {
      _scanningOrphans = true;
      _orphans = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final result = await db.findOrphanedJournalEntries();
      if (!mounted) return;
      setState(() => _orphans = result);
    } catch (e) {
      if (mounted) AppToast.show(context, 'فشل الفحص: $e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _scanningOrphans = false);
    }
  }

  // ── Section 3: duplicate-category dedup (Phase 6 T7) ──────────────────
  Widget _categoryDedupSection() {
    final groups = _dupCategories;
    final hasDups = groups != null && groups.isNotEmpty;
    final totalExtra = groups == null
        ? 0
        : groups.fold<int>(0, (s, g) => s + ((g['count'] as int? ?? 1) - 1));

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(PhosphorIconsBold.copy,
                    color: AppColors.warning, size: 20),
                SizedBox(width: 8),
                Text('دمج التصنيفات المكرَّرة',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'البحث عن التصنيفات التي تشترك في نفس الاسم بعد إزالة '
              'الفراغات وتوحيد حالة الأحرف. الدمج يبقي أقدم صف ويُعيد '
              'ربط المنتجات والفروع به ثم يحذف المكرَّر.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: _scanningDupCategories
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                  label: const Text('فحص'),
                  onPressed: _scanningDupCategories ? null : _scanDupCategories,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: _mergingDupCategories
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(PhosphorIconsBold.gitMerge, size: 16),
                  label: Text(hasDups ? 'دمج ($totalExtra صف)' : 'دمج'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasDups ? AppColors.error : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: (!hasDups || _mergingDupCategories)
                      ? null
                      : _confirmAndMergeDupCategories,
                ),
              ],
            ),
            if (groups != null) ...[
              const SizedBox(height: 12),
              if (groups.isEmpty)
                const Text('✓ لا توجد تصنيفات مكرَّرة.',
                    style: TextStyle(color: AppColors.success))
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('عدد المجموعات المكرَّرة: ${groups.length}',
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      ...groups.take(20).map((g) {
                        final ids = (g['ids'] as List).cast<int>();
                        final names = (g['names'] as List).cast<String>();
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '  • ${names.join(" / ")} — ids: ${ids.join(",")}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }),
                      if (groups.length > 20)
                        Text('  … و ${groups.length - 20} مجموعة أخرى',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _scanDupCategories() async {
    setState(() {
      _scanningDupCategories = true;
      _dupCategories = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final result = await db.dryRunDuplicateCategoryGroups();
      if (!mounted) return;
      setState(() => _dupCategories = result);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل الفحص: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _scanningDupCategories = false);
    }
  }

  Future<void> _confirmAndMergeDupCategories() async {
    final groups = _dupCategories!;
    final totalExtra =
        groups.fold<int>(0, (s, g) => s + ((g['count'] as int? ?? 1) - 1));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.warning, color: AppColors.error),
              SizedBox(width: 8),
              Text('تأكيد الدمج'),
            ],
          ),
          content: Text(
            'سيتم دمج $totalExtra صف من التصنيفات المكرَّرة في الصفوف '
            'الأقدم وإعادة ربط المنتجات والفروع بها.\n\n'
            'هذا الإجراء لا يمكن التراجع عنه.\n\n'
            'تأكد من وجود نسخة احتياطية حديثة قبل المتابعة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('تأكيد الدمج'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _mergingDupCategories = true);
    try {
      final db = ref.read(databaseProvider);
      final merged = await db.mergeDuplicateCategories();
      if (!mounted) return;
      setState(() => _dupCategories = const []);
      AppToast.show(context, 'تم دمج $merged تصنيف مكرَّر بنجاح',
          type: ToastType.success);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل الدمج: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _mergingDupCategories = false);
    }
  }

  // ── Section 4: server-side branches dedup (Spec 084c) ─────────────────
  // Cleans the pre-v131 ghost branch rows on the canonical PG server.
  // Server-mode only; the section is hidden in standalone/client/mirror.
  Widget _branchServerDedupSection() {
    final groups = _branchDupGroups;
    final hasDups = groups != null && groups.any((g) => g.hasDuplicates);
    final totalDups = groups == null
        ? 0
        : groups.fold<int>(0, (s, g) => s + g.duplicates.length);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(PhosphorIconsBold.buildings,
                    color: AppColors.warning, size: 20),
                SizedBox(width: 8),
                Text('إصلاح الفروع المكررة (السيرفر)',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'فحص ودمج الفروع التي لها نفس الاسم على السيرفر. '
              'الدمج يُعيد ربط صلاحيات المستخدمين بالفرع الأساسي '
              '(الأكثر استخدامًا) ثم يُلغي تفعيل المكرر. الفروع التي '
              'لها فواتير أو ورديات يتم تجاوزها — استخدم نافذة حذف '
              'الفرع لدمج بياناتها يدويًا أولاً.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: _scanningBranchDups
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                  label: const Text('فحص'),
                  onPressed: _scanningBranchDups ? null : _scanBranchDups,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: _repairingBranchDups
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(PhosphorIconsBold.gitMerge, size: 16),
                  label: Text(hasDups ? 'دمج ($totalDups صف)' : 'دمج'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasDups ? AppColors.error : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: (!hasDups || _repairingBranchDups)
                      ? null
                      : _confirmAndRepairBranchDups,
                ),
              ],
            ),
            if (groups != null) ...[
              const SizedBox(height: 12),
              if (groups.isEmpty)
                const Text('✓ لا توجد فروع مكررة على السيرفر.',
                    style: TextStyle(color: AppColors.success))
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('عدد المجموعات: ${groups.length}',
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      ...groups.map((g) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '• "${g.name}"',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13),
                              ),
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                    start: 16, top: 2),
                                child: Text(
                                  '  أساسي: id=${g.canonical.id} '
                                  '(refs=${g.canonical.refCount})',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.success),
                                ),
                              ),
                              ...g.duplicates.map((d) => Padding(
                                    padding: const EdgeInsetsDirectional
                                        .only(start: 16, top: 2),
                                    child: Text(
                                      '  مكرر: id=${d.id} '
                                      '(refs=${d.refCount}'
                                      '${d.attachedTxnRefs > 0
                                          ? ", فواتير/ورديات=${d.attachedTxnRefs} — سيتم تخطيه"
                                          : ""})',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: d.attachedTxnRefs > 0
                                              ? AppColors.textMuted
                                              : AppColors.error),
                                    ),
                                  )),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _scanBranchDups() async {
    setState(() {
      _scanningBranchDups = true;
      _branchDupGroups = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final result = await db.auditDuplicateBranches();
      if (!mounted) return;
      setState(() => _branchDupGroups = result);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل الفحص: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _scanningBranchDups = false);
    }
  }

  Future<void> _confirmAndRepairBranchDups() async {
    final groups = _branchDupGroups!.where((g) => g.hasDuplicates).toList();
    if (groups.isEmpty) return;

    // Build the type-to-confirm guard against the first group's name —
    // typical field case is a single repeating name (e.g. "الفرع الرئيسي").
    final expectedName = groups.first.name;
    final controller = TextEditingController();
    final isMatch = ValueNotifier<bool>(false);
    controller.addListener(() {
      isMatch.value = controller.text.trim() == expectedName;
    });

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.warning, color: AppColors.error),
              SizedBox(width: 8),
              Text('تأكيد الإصلاح'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سيتم دمج الفروع المكررة في الفرع الأساسي وإلغاء تفعيل '
                'المكرر. الفروع التي لها فواتير أو ورديات سيتم تخطيها.\n\n'
                'هذا الإجراء يعمل على السيرفر مباشرة — لا يمكن التراجع. '
                'تأكد من وجود نسخة احتياطية حديثة.\n\n'
                'اكتب اسم الفرع للتأكيد: "$expectedName"',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'اسم الفرع',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: isMatch,
              builder: (_, match, _) => ElevatedButton(
                onPressed: match ? () => Navigator.pop(ctx, true) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                child: const Text('تأكيد الإصلاح'),
              ),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    if (confirmed != true) return;

    setState(() => _repairingBranchDups = true);
    try {
      final db = ref.read(databaseProvider);
      final result = await db.repairDuplicateBranches();
      if (!mounted) return;
      // Re-audit so the section reflects the new state.
      final refreshed = await db.auditDuplicateBranches();
      if (!mounted) return;
      setState(() => _branchDupGroups = refreshed);
      final msg = result.hasSkipped
          ? 'تم دمج ${result.mergedCount} فرع، تخطي ${result.skippedCount} لوجود فواتير/ورديات'
          : 'تم دمج ${result.mergedCount} فرع بنجاح';
      AppToast.show(context, msg,
          type: result.hasSkipped ? ToastType.info : ToastType.success);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل الإصلاح: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _repairingBranchDups = false);
    }
  }

  // ── Section 5: parties dedup (Spec 084d + Spec 088 USR-3) ─────────────
  // Field smoke V148 showed delivery-company parties duplicated 2-3 times
  // on the canonical PG server (only first row had balance > 0). Same
  // pattern as the branches dedup above. Originally server-mode only
  // (Spec 084d); Spec 088 USR-3 extends visibility to mirror because the
  // V151 field smoke showed the same duplicates surfacing on a mirror's
  // local DB while the server's was clean — operators can't fix the
  // mirror by running the tool on the server. The repair operates
  // exclusively on the local DB inside one Drift transaction and emits
  // no server writes.
  Widget _partyServerDedupSection() {
    final groups = _partyDupGroups;
    final hasDups = groups != null && groups.any((g) => g.hasDuplicates);
    final totalDups = groups == null
        ? 0
        : groups.fold<int>(0, (s, g) => s + g.duplicates.length);
    final mergeable = groups == null
        ? 0
        : groups.fold<int>(
            0,
            (s, g) => s +
                g.duplicates.where((d) => d.attachedTxnRefs == 0).length);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(PhosphorIconsBold.users,
                    color: AppColors.warning, size: 20),
                SizedBox(width: 8),
                Text('إصلاح العملاء/الموردين المكررين (السيرفر)',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'فحص ودمج العملاء أو الموردين الذين يتشاركون نفس الاسم على '
              'السيرفر. يتم إلغاء تفعيل المكررات الفارغة (التي لا تملك أي '
              'فواتير/سندات/أوراق تجارية). المكررات التي لها معاملات يتم '
              'تخطيها — استخدم أداة دمج الطرف يدويًا قبل الإصلاح.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: _scanningPartyDups
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                  label: const Text('فحص'),
                  onPressed: _scanningPartyDups ? null : _scanPartyDups,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: _repairingPartyDups
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(PhosphorIconsBold.gitMerge, size: 16),
                  label: Text(hasDups
                      ? 'دمج ($mergeable من $totalDups)'
                      : 'دمج'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        mergeable > 0 ? AppColors.error : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: (mergeable == 0 || _repairingPartyDups)
                      ? null
                      : _confirmAndRepairPartyDups,
                ),
              ],
            ),
            if (groups != null) ...[
              const SizedBox(height: 12),
              if (groups.isEmpty)
                const Text('✓ لا توجد أطراف مكررة على السيرفر.',
                    style: TextStyle(color: AppColors.success))
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('عدد المجموعات: ${groups.length}',
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      ...groups.map((g) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '• "${g.name}"'
                                '${g.canonical.phone != null && g.canonical.phone!.isNotEmpty
                                    ? " (${g.canonical.phone})"
                                    : ""}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13),
                              ),
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                    start: 16, top: 2),
                                child: Text(
                                  '  أساسي: id=${g.canonical.id} '
                                  '(refs=${g.canonical.refCount}, '
                                  'رصيد=${g.canonical.balance.toStringAsFixed(3)})',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.success),
                                ),
                              ),
                              ...g.duplicates.map((d) => Padding(
                                    padding: const EdgeInsetsDirectional
                                        .only(start: 16, top: 2),
                                    child: Text(
                                      '  مكرر: id=${d.id} '
                                      '(refs=${d.refCount}, رصيد=${d.balance.toStringAsFixed(3)}'
                                      '${d.attachedTxnRefs > 0
                                          ? ", معاملات=${d.attachedTxnRefs} — سيتم تخطيه"
                                          : ""})',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: d.attachedTxnRefs > 0
                                              ? AppColors.textMuted
                                              : AppColors.error),
                                    ),
                                  )),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _scanPartyDups() async {
    setState(() {
      _scanningPartyDups = true;
      _partyDupGroups = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final result = await db.auditDuplicateParties();
      if (!mounted) return;
      setState(() => _partyDupGroups = result);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل الفحص: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _scanningPartyDups = false);
    }
  }

  Future<void> _confirmAndRepairPartyDups() async {
    final groups = _partyDupGroups!.where((g) => g.hasDuplicates).toList();
    if (groups.isEmpty) return;

    final expectedName = groups.first.name;
    final controller = TextEditingController();
    final isMatch = ValueNotifier<bool>(false);
    controller.addListener(() {
      isMatch.value = controller.text.trim() == expectedName;
    });

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.warning, color: AppColors.error),
              SizedBox(width: 8),
              Text('تأكيد الإصلاح'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سيتم إلغاء تفعيل الأطراف المكررة الفارغة (بدون فواتير '
                'أو سندات). الأطراف التي لها معاملات سيتم تخطيها — '
                'استخدم أداة دمج الطرف يدويًا أولًا.\n\n'
                'هذا الإجراء يعمل على قاعدة بيانات هذا الجهاز '
                'مباشرة — لا يمكن التراجع. تأكد من وجود نسخة احتياطية حديثة.\n\n'
                'اكتب اسم الطرف للتأكيد: "$expectedName"',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'اسم الطرف',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: isMatch,
              builder: (_, match, _) => ElevatedButton(
                onPressed: match ? () => Navigator.pop(ctx, true) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                child: const Text('تأكيد الإصلاح'),
              ),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    if (confirmed != true) return;

    setState(() => _repairingPartyDups = true);
    try {
      final db = ref.read(databaseProvider);
      final result = await db.repairDuplicateParties();
      if (!mounted) return;
      final refreshed = await db.auditDuplicateParties();
      if (!mounted) return;
      setState(() => _partyDupGroups = refreshed);
      final msg = result.hasSkipped
          ? 'تم دمج ${result.mergedCount} طرف، تخطي ${result.skippedCount} لوجود معاملات'
          : 'تم دمج ${result.mergedCount} طرف بنجاح';
      AppToast.show(context, msg,
          type: result.hasSkipped ? ToastType.info : ToastType.success);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل الإصلاح: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _repairingPartyDups = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Spec 114 — Party sub-account repair
  // ─────────────────────────────────────────────────────────────────────
  Widget _partySubAccountRepairSection() {
    final r = _partySubAccountResult;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(PhosphorIconsBold.wrench,
                    color: AppColors.warning, size: 20),
                SizedBox(width: 8),
                Text('إصلاح حسابات الموردين والعملاء المفقودة',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'إنشاء حساب فرعي في دليل الحسابات لكل مورد/عميل تنقصه ربط. '
              'يتم تشغيلها مرة واحدة عند ظهور خطأ "حساب رئيسي" في القيود.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: _repairingPartySubAccounts
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(PhosphorIconsBold.play, size: 16),
              label: const Text('تشغيل الإصلاح'),
              onPressed: _repairingPartySubAccounts
                  ? null
                  : _runRepairPartySubAccounts,
            ),
            if (r != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ((r['failed'] ?? 0) > 0
                          ? AppColors.error
                          : AppColors.success)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'تم: ${r['repaired']} | تخطي: ${r['skipped']} | '
                  'فشل: ${r['failed']} | الإجمالي: ${r['total']}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runRepairPartySubAccounts() async {
    setState(() {
      _repairingPartySubAccounts = true;
      _partySubAccountResult = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final result = await db.repairMissingPartySubAccounts();
      if (!mounted) return;
      setState(() => _partySubAccountResult = result);
      final msg = 'تم: ${result['repaired']} | '
          'تخطي: ${result['skipped']} | '
          'فشل: ${result['failed']}';
      AppToast.show(
        context,
        msg,
        type: (result['failed'] ?? 0) > 0
            ? ToastType.error
            : ToastType.success,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _repairingPartySubAccounts = false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Spec 114b — Re-post missing invoice JEs
  // ─────────────────────────────────────────────────────────────────────
  Widget _invoiceJERepairSection() {
    final r = _invoiceJEResult;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(PhosphorIconsBold.notebook,
                    color: AppColors.warning, size: 20),
                SizedBox(width: 8),
                Text('إعادة ترحيل قيود اليومية للفواتير المفقودة',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'إعادة ترحيل القيود المحاسبية لكل فاتورة (مبيعات / مشتريات) '
              'لم يتم ترحيلها سابقاً. شغّل أداة إصلاح الحسابات أولاً.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: _repairingInvoiceJEs
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(PhosphorIconsBold.play, size: 16),
              label: const Text('تشغيل إعادة الترحيل'),
              onPressed:
                  _repairingInvoiceJEs ? null : _runRepairInvoiceJEs,
            ),
            if (r != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (((r['salesFailed'] ?? 0) +
                              (r['purchasesFailed'] ?? 0)) >
                          0
                      ? AppColors.error
                      : AppColors.success).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مبيعات — تم: ${r['salesRepaired']} | '
                      'تخطي: ${r['salesSkipped']} | '
                      'فشل: ${r['salesFailed']}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'مشتريات — تم: ${r['purchasesRepaired']} | '
                      'تخطي: ${r['purchasesSkipped']} | '
                      'فشل: ${r['purchasesFailed']}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'الإجمالي المفحوص: ${r['totalScanned']}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Spec 114c — Rewire JE lines from parent control → party sub-account
  // ─────────────────────────────────────────────────────────────────────
  Widget _rewireJELinesSection() {
    final r = _rewireResult;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(PhosphorIconsBold.shuffle,
                    color: AppColors.info, size: 20),
                SizedBox(width: 8),
                Text('نقل القيود إلى الحسابات الفرعية',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'بعد إنشاء الحسابات الفرعية للأطراف، تُنقَل القيود التاريخية '
              'من حسابات الذمم الرئيسية (1121 / 2111) إلى الحسابات الفرعية '
              'المُنشأة. يجعل كشف دفتر الأستاذ لكل طرف يعرض حركاته الفعلية.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: _rewiringJELines
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(PhosphorIconsBold.play, size: 16),
              label: const Text('تشغيل النقل'),
              onPressed: _rewiringJELines ? null : _runRewireJELines,
            ),
            if (r != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ((r['failed'] ?? 0) > 0
                          ? AppColors.error
                          : AppColors.success)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'سطور تم نقلها: ${r['linesMoved']} | '
                  'أطراف مفحوصة: ${r['partiesScanned']} | '
                  'فشل: ${r['failed']}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runRewireJELines() async {
    setState(() {
      _rewiringJELines = true;
      _rewireResult = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final result = await db.rewireJELinesToPartySubAccounts();
      if (!mounted) return;
      setState(() => _rewireResult = result);
      AppToast.show(
        context,
        'تم نقل ${result['linesMoved']} سطر قيد إلى الحسابات الفرعية',
        type: (result['failed'] ?? 0) > 0
            ? ToastType.error
            : ToastType.success,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _rewiringJELines = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Spec 115b — Stranded outbox cleanup
  // ─────────────────────────────────────────────────────────────────────
  Widget _strandedOutboxSection() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(PhosphorIconsBold.cloudSlash,
                    color: AppColors.warning, size: 20),
                SizedBox(width: 8),
                Text('تنظيف صفوف المزامنة العالقة (Outbox)',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'إذا تم تحويل جهاز عميل سابق إلى مستقل/سيرفر بعد كتابات لم تُرسل، '
              'تبقى تلك الصفوف عالقة في outbox ولن تُرسل أبداً. هذه الأداة '
              'تحصرها ثم تختمها (mark as synced) لإسكات تحذير SYNC-WARN.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: _scanningStranded
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                  label: const Text('فحص'),
                  onPressed:
                      _scanningStranded ? null : _scanStrandedOutbox,
                ),
                const SizedBox(width: 8),
                if (_strandedCount != null && _strandedCount! > 0)
                  ElevatedButton.icon(
                    icon: _clearingStranded
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(PhosphorIconsBold.broom, size: 16),
                    label: Text('تصفية ($_strandedCount)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      foregroundColor: Colors.white,
                    ),
                    onPressed:
                        _clearingStranded ? null : _clearStrandedOutbox,
                  ),
              ],
            ),
            if (_strandedCount != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (_strandedCount! == 0
                          ? AppColors.success
                          : AppColors.warning)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _strandedCount! == 0
                      ? '✓ لا توجد صفوف مزامنة عالقة.'
                      : 'الصفوف العالقة: $_strandedCount',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _scanStrandedOutbox() async {
    setState(() {
      _scanningStranded = true;
      _strandedCount = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final pending = await db.getPendingSyncItems(limit: 10000);
      if (!mounted) return;
      setState(() => _strandedCount = pending.length);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل الفحص: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _scanningStranded = false);
    }
  }

  Future<void> _clearStrandedOutbox() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد التصفية'),
          content: Text(
              'سيتم ختم $_strandedCount صف(صفوف) كـ "مُسوّاة يدوياً". '
              'هذه العملية لا تُرسل البيانات للسيرفر — فقط تُسكت التحذير. '
              'لا يمكن التراجع. هل أنت متأكد؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('نعم، تصفية'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    setState(() => _clearingStranded = true);
    try {
      final db = ref.read(databaseProvider);
      final affected = await db.markAllAsSyncedReconciled();
      if (!mounted) return;
      setState(() => _strandedCount = 0);
      AppToast.show(
        context,
        'تم تصفية $affected صف(صفوف) عالقة',
        type: ToastType.success,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _clearingStranded = false);
    }
  }

  Future<void> _runRepairInvoiceJEs() async {
    setState(() {
      _repairingInvoiceJEs = true;
      _invoiceJEResult = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final result = await db.repairAllMissingInvoiceJEs();
      if (!mounted) return;
      setState(() => _invoiceJEResult = result);
      final salesR = result['salesRepaired'] ?? 0;
      final salesF = result['salesFailed'] ?? 0;
      final purchR = result['purchasesRepaired'] ?? 0;
      final purchF = result['purchasesFailed'] ?? 0;
      AppToast.show(
        context,
        'مبيعات: $salesR/${salesF == 0 ? "نجح" : "$salesF فشل"} | '
            'مشتريات: $purchR/${purchF == 0 ? "نجح" : "$purchF فشل"}',
        type: (salesF + purchF) > 0 ? ToastType.error : ToastType.success,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _repairingInvoiceJEs = false);
    }
  }
}
