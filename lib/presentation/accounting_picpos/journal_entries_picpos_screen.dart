import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/permissions/permission_codes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/providers.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../domain/models/journal_balance.dart';
import '../../domain/models/journal_source_document.dart';
import '../../data/providers/screen_navigation_provider.dart';
import '../../core/navigation/screen_id.dart';
import '../../core/config/app_config.dart';
import '../../services/printing/report_pdf_generator.dart';
import '../picpos_shell/picpos_dialog.dart';
import '../picpos_shell/picpos_empty_state.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import '../picpos_shell/picpos_toolbar.dart';
import '../../services/excel_export_helper.dart';
import '../widgets/branch_chip.dart';
import '../widgets/compact_date_picker.dart';
import 'journal_entries_picpos_widgets.dart';
import 'journal_templates_picpos_screen.dart';
import '../picpos_shell/picpos_surface.dart';
import '../picpos_shell/picpos_attachments_panel.dart';

// ⚠️ حوارُ الإنشاء وودجتاتُ السطور **امتداداتٌ خاصّةٌ على حالة الشاشة** في
//    الأصل (‏`part of`)، فلا تُستورَد ولا تُستدعى من خارج مكتبتها. ولذلك
//    نُسخت الوحدةُ كاملةً — ١٩٠١ سطرٍ في ثلاثة ملفّات لا ١٠٥٩ في واحد.
part 'journal_entries_picpos_create_dialog.dart';


/// تنسيقُ المال على هذه الشاشة — **واحدٌ للشريط ولصفوف القيود**.
///
/// ⚠️ ورقمُ الخانات من [AppConstants.decimalPlaces] لا مكتوباً: العملةُ
/// الافتراضيّةُ هنا بثلاث خانات، وتثبيتُ اثنتَين يُخفي فلساً في كلّ سطر.
final journalMoney =
    NumberFormat('#,##0.${'0' * AppConstants.decimalPlaces}');

/// قيودُ اليومية بهويّة PicPos — تبويبُ `je` في حاويةِ الحسابات.
///
/// التصميمُ: شريطُ إجماليّاتٍ بأربع بطاقات (عدد القيود · إجمالي المدين ·
/// إجمالي الدائن · الفرق) ثمّ صفوفُ القيود بأعمدةِ رقمِ القيد · التاريخ ·
/// البيان · المصدر · الحالة · إجمالي المدين · إجمالي الدائن · الفرق ·
/// إجراءات، ويتوسّع الصفُّ إلى سطوره مع «الفرق» رقماً وشارةً، ثمّ تذييلٍ
/// فيه المنشئُ والمرجعُ وزرُّ المستند المصدر.
///
/// ⚠️ **ومجاميعُ الصفوف من استعلامٍ مُجمَّعٍ واحد** (`watchJournalEntryTotals`)
/// لا من قراءةِ سطورٍ لكلّ صفّ: تلك N+1 في كلّ إعادةِ بناء.
///
/// ⚠️ **حارسُ MJE-3 منقولٌ كما هو ولا يُسقَط.** عكسُ القيد يُنشئ قيداً
/// يدويّاً جديداً، وكان الفحصُ موجوداً على الخادم وحدَه — فأيُّ مستخدمٍ يعبر
/// كلمةَ سرِّ الشاشة (سرٌّ مشتركٌ لا حارسُ مستخدم) كان يرحّل قيوداً على
/// تنصيبةٍ مستقلّة. و[PermissionCodes.accountingJournal] هو ما يحرسه.
///
/// ⚠️ **وتحذيرُ MJE-2 باقٍ**: عكسُ قيدٍ آليٍّ يصلح الأستاذَ ولا يمسّ حالةَ
/// مستنده، فيفترقان — يُحذَّر ولا يُمنَع.
class JournalEntriesPicPosScreen extends ConsumerStatefulWidget {
  const JournalEntriesPicPosScreen({super.key});

  @override
  ConsumerState<JournalEntriesPicPosScreen> createState() =>
      _JournalEntriesPicPosScreenState();
}

class _JournalEntriesPicPosScreenState
    extends ConsumerState<JournalEntriesPicPosScreen> {
  DateTime _dateFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _dateTo = DateTime.now();
  String _filterType = 'all';

  /// «الحالة» في التصميم — مرشِّحٌ قائمٌ بذاته لا شارةٌ في بطاقة.
  ///
  /// 🔴 **وهو بديلُ بطاقةٍ سقطت**: شريطُ الإجماليّات كان يعدّ «بانتظار
  /// الاعتماد»، وقد حلّت محلَّه بطاقاتُ التصميم الأربع. وإسقاطُ العدّ بلا
  /// بديلٍ يترك القيودَ المنتظرةَ بلا ما يجمعها — والمرشِّحُ أقوى منه:
  /// يُظهرها لا يَعُدُّها.
  String _filterStatus = 'all';

  int? _filterBranchId;
  static const int _noBranchSentinel = -1;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _dateFormat = DateFormat('yyyy/MM/dd');
  final Set<int> _expanded = {};

  /// يُزيل لاحقةَ بصمةِ التدقيق من الوصف للعرض — والبصمةُ تبقى في القاعدة
  /// للتحقّق من السلامة (ICR-03).
  static String cleanDescription(String? desc) {
    if (desc == null || desc.isEmpty) return 'بدون وصف';
    return desc.replaceAll(RegExp(r'\s*\[HASH:[a-f0-9]{64}\]'), '').trim();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// حارسُ MJE-3 — راجع تعليقَ الصنف. يُرجع `false` ويُظهر رسالةً حين
  /// تنقص الصلاحية، ولا يجوز للمستدعي المتابعة.
  Future<bool> _requireAccountingJournalPermission() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) {
      if (mounted) {
        AppToast.show(context, 'يجب تسجيل الدخول لتنفيذ هذا الإجراء',
            type: ToastType.error);
      }
      return false;
    }

    final authRepo = ref.read(authRepositoryProvider);
    final allowed = await authRepo.userHasPermission(
        userId, PermissionCodes.accountingJournal);
    if (!allowed) {
      if (mounted) {
        AppToast.show(
            context, 'ليست لديك صلاحية إنشاء أو عكس القيود المحاسبية اليدوية',
            type: ToastType.error);
      }
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(accountingRepositoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: StreamBuilder<List<JournalEntryData>>(
        stream: repo.watchJournalEntries(from: _dateFrom, to: _dateTo),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <JournalEntryData>[];
          final shown = _applyFilters(all);

          return PicPosScreenScaffold(
            // الاسمُ من الثابت المشترك — وقياسُ 2026-09-19 وجد **ثمانيةَ**
            // مواضعَ تكتبه: أربعةُ أبوابٍ تؤدّي إلى الشاشة، وأربعةٌ يقرؤها
            // من وصل (العنوان · تبويبُ `je` · ورقةُ الطباعة · ملفُّ Excel).
            title: journalEntriesScreenLabel,
            subtitle: 'عرض القيود المحاسبية مع إمكانية البحث والتصفية',
            icon: PhosphorIconsBold.notebook,
            headerSearch: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'بحث برقم القيد أو البيان...',
                prefixIcon:
                    const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(PhosphorIconsBold.x, size: 14),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
            headerActions: [
              IconButton(
                tooltip: 'طباعة/PDF',
                icon: const Icon(PhosphorIconsBold.filePdf, size: 18),
                onPressed: () => _printAllEntries(repo),
              ),
              IconButton(
                tooltip: 'تصدير Excel',
                icon: const Icon(PhosphorIconsBold.fileXls, size: 18),
                onPressed: () => _exportAllEntriesToExcel(repo),
              ),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const JournalTemplatesPicPosScreen(),
                  ),
                ),
                icon: const Icon(PhosphorIconsBold.stack, size: 15),
                label: const Text('قوالب القيود'),
              ),
              OutlinedButton.icon(
                onPressed: () => showTemplateSelectionDialog(context, repo),
                icon: const Icon(PhosphorIconsBold.copy, size: 15),
                label: const Text('من قالب'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => showCreateEntryDialog(context),
                icon: const Icon(PhosphorIconsBold.notePencil, size: 16),
                label: const Text('قيد يدوي'),
              ),
            ],
            toolbar: _buildToolbar(),
            body: !snapshot.hasData
                ? const Center(child: CircularProgressIndicator())
                // ⚠️ **مجرىً ثانٍ بنفس المدى**: المجاميعُ في
                // `journal_entry_lines` لا على صفّ القيد، فلا يحملها
                // `watchJournalEntries`. وتُقرأ **مُجمَّعةً مرّةً واحدة** لا
                // بنداءٍ لكلّ صفّ.
                : StreamBuilder<Map<int, ({double debit, double credit})>>(
                    stream: repo.watchJournalEntryTotals(
                        from: _dateFrom, to: _dateTo),
                    builder: (context, totalsSnap) => _buildBody(
                      repo,
                      all,
                      shown,
                      totalsSnap.data ??
                          const <int, ({double debit, double credit})>{},
                    ),
                  ),
          );
        },
      ),
    );
  }

  List<JournalEntryData> _applyFilters(List<JournalEntryData> entries) {
    var out = entries;

    if (_filterType == 'auto') {
      out = out.where((e) => e.isAutoPosted).toList();
    } else if (_filterType == 'manual') {
      out = out.where((e) => !e.isAutoPosted).toList();
    }

    // «الحالة» — و`isPosted` هو الفاصل: أدخل الأستاذَ أم لا. وهو نفسُه ما
    // يحكم شارةَ الصفّ وزرَّ العكس، فلا يقول المرشِّحُ غيرَ ما تقوله الشارة.
    if (_filterStatus == 'posted') {
      out = out.where((e) => e.isPosted).toList();
    } else if (_filterStatus == 'pending') {
      out = out.where((e) => !e.isPosted).toList();
    }

    final branch = _filterBranchId;
    if (branch != null) {
      // ‏`-1` هو «بدون فرع» — قيودٌ قديمةٌ بـ`branchId == null`، وهي ليست
      // «كلَّ الفروع». خلطُهما يُخفي القيودَ القديمةَ أو يُظهرها بلا داعٍ.
      out = branch == _noBranchSentinel
          ? out.where((e) => e.branchId == null).toList()
          : out.where((e) => e.branchId == branch).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      out = out.where((e) {
        return e.entryNumber.toLowerCase().contains(q) ||
            cleanDescription(e.description).toLowerCase().contains(q);
      }).toList();
    }

    return out;
  }

  Widget _buildToolbar() {
    return PicPosToolbar(
      children: [
        _Chip(
          icon: PhosphorIconsBold.calendarBlank,
          label: '${_dateFormat.format(_dateFrom)} — '
              '${_dateFormat.format(_dateTo)}',
          active: true,
          onTap: _pickDateRange,
        ),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'all', label: Text('الكل')),
            ButtonSegment(value: 'auto', label: Text('آلي')),
            ButtonSegment(value: 'manual', label: Text('يدوي')),
          ],
          selected: {_filterType},
          onSelectionChanged: (s) => setState(() => _filterType = s.first),
        ),
        // «الحالة» في التصميم — ويحلّ محلَّ بطاقة «بانتظار الاعتماد» التي
        // أخلت مكانَها لبطاقات الإجماليّات الأربع.
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'all', label: Text('كل الحالات')),
            ButtonSegment(value: 'posted', label: Text('مرحّل')),
            ButtonSegment(value: 'pending', label: Text('بانتظار الاعتماد')),
          ],
          selected: {_filterStatus},
          onSelectionChanged: (s) => setState(() => _filterStatus = s.first),
        ),
        Consumer(
          builder: (context, ref, _) {
            // نفسُ مزوِّدِ الفروع الذي تقرأ منه الطباعةُ — مصدرٌ واحدٌ فلا
            // يختلف اسمُ الفرع على الشاشة عن اسمِه على الورقة.
            final branches = ref.watch(allBranchesProvider);
            return branches.maybeWhen(
              data: (list) {
                if (list.isEmpty) return const SizedBox.shrink();
                final label = switch (_filterBranchId) {
                  null => 'كل الفروع',
                  _noBranchSentinel => 'بدون فرع',
                  final id => list
                          .where((b) => b.id == id)
                          .map((b) => b.name)
                          .firstOrNull ??
                      'الفرع',
                };
                return _Chip(
                  icon: PhosphorIconsBold.buildings,
                  label: label,
                  active: _filterBranchId != null,
                  onTap: () => _pickBranch(list),
                );
              },
              orElse: () => const SizedBox.shrink(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBody(
    IAccountingRepository repo,
    List<JournalEntryData> all,
    List<JournalEntryData> shown,
    Map<int, ({double debit, double credit})> totals,
  ) {
    if (all.isEmpty) {
      return const PicPosEmptyState(
        icon: PhosphorIconsBold.notebook,
        title: 'لا قيودَ في هذه الفترة',
        hint: 'وسّع المدى الزمنيَّ أو أنشئ قيداً يدويّاً.',
      );
    }
    if (shown.isEmpty) {
      return PicPosEmptyState(
        icon: PhosphorIconsBold.funnel,
        title: 'لا قيدَ يطابق الترشيح',
        hint: 'من ${all.length} قيداً في الفترة.',
        action: TextButton.icon(
          onPressed: () {
            _searchController.clear();
            setState(() {
              _searchQuery = '';
              _filterType = 'all';
              _filterStatus = 'all';
              _filterBranchId = null;
            });
          },
          icon: const Icon(PhosphorIconsBold.x, size: 14),
          label: const Text('امسح المرشِّحات'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TotalsBar(entries: shown, totals: totals),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final entry = shown[i];
              return _EntryCard(
                entry: entry,
                repo: repo,
                balance: JournalBalance(
                  debit: totals[entry.id]?.debit ?? 0,
                  credit: totals[entry.id]?.credit ?? 0,
                ),
                dateFormat: _dateFormat,
                expanded: _expanded.contains(entry.id),
                onToggle: () => setState(() {
                  if (!_expanded.remove(entry.id)) _expanded.add(entry.id);
                }),
                onPrint: (lines) => _printEntry(entry, lines),
                onReverse: () => _confirmReverseEntry(entry),
                onApprove: () => _approveEntry(repo, entry),
                // 🔴 **الفتحُ عبر القناة لا مباشرةً**: مالكُ التابات وحدَه
                // يعرف الصلاحيّاتِ وتاريخَ الرجوع وسقفَ التابات.
                onOpenSource: (target) => ref
                    .read(screenNavigationProvider.notifier)
                    .open(target.screenId.navigationIndex),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
      initialEntryMode: DatePickerEntryMode.input,
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 380),
            child: child!,
          ),
        ),
      ),
    );
    if (range == null) return;
    setState(() {
      _dateFrom = range.start;
      _dateTo = range.end;
    });
  }

  Future<void> _pickBranch(List<Branche> branches) async {
    final picked = await showDialog<(int?,)>(
      context: context,
      builder: (ctx) => PicPosDialog(
        icon: PhosphorIconsBold.buildings,
        title: 'الفرع',
        width: 460,
        onCancel: () => Navigator.pop(ctx),
        body: [
          ListTile(
            dense: true,
            title: const Text('كل الفروع'),
            onTap: () => Navigator.pop(ctx, (null,)),
          ),
          ListTile(
            dense: true,
            title: const Text('بدون فرع'),
            subtitle: const Text('قيود قديمة بلا فرع مسجَّل',
                style: TextStyle(fontSize: 11)),
            onTap: () => Navigator.pop(ctx, (_noBranchSentinel,)),
          ),
          const Divider(height: 1),
          for (final b in branches)
            ListTile(
              dense: true,
              title: Text(b.name, style: const TextStyle(fontSize: 13)),
              onTap: () => Navigator.pop(ctx, (b.id,)),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _filterBranchId = picked.$1);
  }

  /// ملخّصُ القيد في حوارَي الاعتماد والعكس — أسطرُ التصميم الأربعة.
  ///
  /// ⚠️ **القيمةُ مجموعُ المدين لا مجموعُ الطرفَين.** القيدُ متوازنٌ بحكم
  /// تعريفه، فجمعُ المدين والدائن معاً يضاعف الرقمَ المعروضَ فيقرأ
  /// المشغّلُ ضِعفَ ما سيعتمد.
  Future<List<PicPosDialogSummary>> _entrySummary(
    IAccountingRepository repo,
    JournalEntryData entry,
  ) async {
    double total = 0;
    try {
      final lines = await repo.getJournalEntryLinesWithAccounts(entry.id);
      for (final l in lines) {
        total += (l['debit'] as num?)?.toDouble() ?? 0;
      }
    } catch (_) {
      // تعذُّرُ جلبِ الأسطر لا يمنع الحوار — تُعرض «—» مكانَ القيمة.
      total = -1;
    }

    return [
      PicPosDialogSummary(
        rows: [
          (label: 'رقم القيد', value: entry.entryNumber, color: null),
          (
            label: 'البيان',
            value: cleanDescription(entry.description),
            color: null,
          ),
          (
            label: 'التاريخ',
            value: _dateFormat.format(entry.entryDate),
            color: null,
          ),
          (
            label: 'القيمة',
            value: total < 0
                ? '—'
                : '${total.toStringAsFixed(AppConstants.decimalPlaces)} '
                    '${AppConstants.currencySymbol}',
            color: null,
          ),
        ],
      ),
    ];
  }

  Future<void> _approveEntry(
    IAccountingRepository repo,
    JournalEntryData entry,
  ) async {
    final details = await _entrySummary(repo, entry);
    if (!mounted) return;

    final confirmed = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.checkCircle,
      title: 'اعتماد القيد',
      subtitle: '${entry.entryNumber} · ${_dateFormat.format(entry.entryDate)}',
      accent: AppColors.success,
      message: 'بعد الاعتماد يصبح القيدُ مؤثّراً على أرصدة الحسابات ولا يمكن '
          'تعديله — يمكن عكسُه بقيدٍ مضادٍّ فقط.',
      confirmLabel: 'تأكيد الاعتماد',
      details: details,
    );
    if (!confirmed || !mounted) return;

    try {
      // المعتمِدُ يُسجَّل مع الاعتماد — أثرُ تدقيقٍ لا معاملٌ تجميليّ.
      final approverId = ref.read(authProvider).user?.id ?? 0;
      await repo.approveJournalEntry(entry.id, approverId);
      if (mounted) {
        AppToast.show(context, 'تم اعتماد القيد بنجاح',
            type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في اعتماد القيد: $e',
            type: ToastType.error);
      }
    }
  }

  Future<void> _printEntry(
    JournalEntryData entry,
    List<Map<String, dynamic>> lines,
  ) async {
    // ⚠️ اسمُ الفرع ولونُه يُمرَّران للطباعة كي تحمل الورقةُ نفسَ الهويّة
    //    البصريّة التي على الشاشة (‏Feature 004). إسقاطُهما يطبع قيداً بلا
    //    فرعٍ على تنصيبةٍ متعدّدة الفروع.
    String? branchName;
    int? branchColorHex;
    final id = entry.branchId;
    if (id != null) {
      final branch = ref
          .read(allBranchesProvider)
          .value
          ?.where((b) => b.id == id)
          .firstOrNull;
      if (branch != null) {
        branchName = branch.name;
        branchColorHex = BranchChip.colorFor(id).toARGB32();
      }
    }

    await ReportPdfGenerator.printJournalEntry(
      entryNumber: entry.entryNumber,
      entryDate: entry.entryDate,
      description: cleanDescription(entry.description),
      referenceType: entry.referenceType,
      isAutoPosted: entry.isAutoPosted,
      lines: lines,
      branchName: branchName,
      branchColorHex: branchColorHex,
    );
  }

  Future<void> _printAllEntries(IAccountingRepository repo) async {
    try {
      final entries = _applyFilters(
        await repo.getJournalEntries(from: _dateFrom, to: _dateTo),
      );
      if (entries.isEmpty) {
        if (mounted) {
          AppToast.show(context, 'لا توجد قيود للطباعة في هذه الفترة',
              type: ToastType.warning);
        }
        return;
      }

      final data = <Map<String, dynamic>>[];
      for (final entry in entries) {
        final lines = await repo.getJournalEntryLinesWithAccounts(entry.id);
        for (final line in lines) {
          data.add({
            'entry_date': entry.entryDate,
            'entry_number': entry.entryNumber,
            'description': line['description']?.toString() ??
                cleanDescription(entry.description),
            'account_name': line['account_name']?.toString() ?? '',
            'debit': (line['debit'] as num?)?.toDouble() ?? 0,
            'credit': (line['credit'] as num?)?.toDouble() ?? 0,
            'balance': 0.0,
          });
        }
      }

      await ReportPdfGenerator.printGeneralLedger(
        accountName: journalEntriesScreenLabel,
        data: data,
        fromDate: _dateFrom,
        toDate: _dateTo,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _exportAllEntriesToExcel(IAccountingRepository repo) async {
    try {
      final entries = _applyFilters(
        await repo.getJournalEntries(from: _dateFrom, to: _dateTo),
      );
      if (entries.isEmpty) {
        if (mounted) {
          AppToast.show(context, 'لا توجد قيود للتصدير في هذه الفترة',
              type: ToastType.warning);
        }
        return;
      }

      final rows = <List<dynamic>>[];
      for (final entry in entries) {
        final lines = await repo.getJournalEntryLinesWithAccounts(entry.id);
        rows.add([
          entry.entryNumber,
          _dateFormat.format(entry.entryDate),
          cleanDescription(entry.description),
          entry.isAutoPosted ? 'آلي' : 'يدوي',
          '',
          '',
        ]);
        for (final line in lines) {
          rows.add([
            '',
            '',
            line['account_code']?.toString() ?? '',
            line['account_name']?.toString() ?? '',
            (line['debit'] as num?)?.toDouble() ?? 0,
            (line['credit'] as num?)?.toDouble() ?? 0,
          ]);
        }
      }

      if (!mounted) return;
      await ExcelExportHelper.export(
        context: context,
        title: journalEntriesScreenLabel,
        headers: const [
          'رقم القيد',
          'التاريخ',
          'رمز الحساب',
          'اسم الحساب / البيان',
          'مدين',
          'دائن',
        ],
        rows: rows,
        fromDate: _dateFrom,
        toDate: _dateTo,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في التصدير: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _confirmReverseEntry(JournalEntryData entry) async {
    final details = await _entrySummary(
      ref.read(accountingRepositoryProvider),
      entry,
    );
    if (!mounted) return;

    final confirmed = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.arrowUUpLeft,
      title: 'عكس القيد',
      subtitle: '${entry.entryNumber} · ${_dateFormat.format(entry.entryDate)}',
      accent: AppColors.warning,
      message: [
        'هل أنت متأكد من عكس هذا القيد؟',
        'سيُنشأ قيدٌ عكسيٌّ بمبالغَ معكوسة (المدين يصبح دائناً والعكس).',
        // ⚠️ تحذيرُ MJE-2 — يُحذَّر ولا يُمنَع.
        if (entry.isAutoPosted)
          'هذا قيدٌ آليّ — الأفضل عكسُه من المستند المصدر '
              '(الفاتورة/السند)، وإلّا افترق الأستاذُ عن حالة المستند.',
      ].join('\n\n'),
      confirmLabel: 'تأكيد العكس',
      details: details,
    );
    if (!confirmed || !mounted) return;

    // ⚠️ حارسُ MJE-3 — بعد التأكيد وقبل الكتابة.
    if (!await _requireAccountingJournalPermission() || !mounted) return;

    try {
      final service = ref.read(accountingServiceProvider);
      // ‏F-02 (MJE-1/MJE-2): العكسُ بالمفتاح الأساسيِّ للقيد نفسِه لا
      // بـ(referenceType, referenceId) — راجع توثيقَ الدالّة.
      final newEntryId = await service.reverseJournalEntryById(
        entryId: entry.id,
        descriptionPrefix: 'عكس قيد: ${entry.entryNumber}',
      );
      if (!mounted) return;
      if (newEntryId > 0) {
        AppToast.show(context, 'تم عكس القيد بنجاح', type: ToastType.success);
      } else {
        AppToast.show(context, 'القيد معكوس بالفعل أو تعذّر العكس',
            type: ToastType.warning);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في عكس القيد: $e', type: ToastType.error);
      }
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.06)
              : Colors.transparent,
          border:
              Border.all(color: active ? AppColors.primary : context.picposHairline),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active ? AppColors.primary : AppColors.textMuted),
            const SizedBox(width: 8),
            Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: active
                        ? AppColors.primary
                        : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// شريطُ إجماليّات الصفحة — **عدد القيود · إجمالي المدين · إجمالي الدائن ·
/// الفرق**، كما في التصميم حرفاً.
///
/// ⚠️ **ومقيسٌ من القيود المعروضة** لا من كلّ ما في المدى: الشريطُ يصف ما تحته.
///
/// ═══ 🔴 ولماذا الشارةُ تقرأ [JournalBalance.worstOf] لا فرقَ المجموع ═══
///
/// قيدان أحدُهما مدينُه زائدٌ مئةً والآخرُ دائنُه زائدٌ مئةً يعطيان مجموعاً
/// **فرقُه صفر**. فشريطٌ يلوّن نفسَه بفرق المجموع يقول «متوازن» وفي الصفحة
/// قيدان مكسوران — وهي الحالةُ التي يُبنى الشريطُ لكشفها.
///
/// فالرقمُ المعروضُ فرقُ المجموع (وإلّا لم يطابق طرحَ العمودَين بجانبه)،
/// **واللونُ والتنبيهُ من أسوأِ قيدٍ منفرد**.
class _TotalsBar extends StatelessWidget {
  const _TotalsBar({required this.entries, required this.totals});

  final List<JournalEntryData> entries;
  final Map<int, ({double debit, double credit})> totals;

  @override
  Widget build(BuildContext context) {
    final parts = [
      for (final e in entries)
        JournalBalance(
          debit: totals[e.id]?.debit ?? 0,
          credit: totals[e.id]?.credit ?? 0,
        ),
    ];
    final page = JournalBalance.sum(parts);
    final worst = JournalBalance.worstOf(parts);
    final anyBroken = !JournalBalance(debit: worst, credit: 0).isBalanced;

    return Row(
      children: [
        Expanded(
          child: _TotalCard(
            label: 'عدد القيود',
            value: '${entries.length}',
            tint: AppColors.primary,
            icon: PhosphorIconsBold.notebook,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TotalCard(
            label: 'إجمالي المدين',
            value: journalMoney.format(page.debit),
            tint: AppColors.info,
            icon: PhosphorIconsBold.arrowDownLeft,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TotalCard(
            label: 'إجمالي الدائن',
            value: journalMoney.format(page.credit),
            tint: AppColors.info,
            icon: PhosphorIconsBold.arrowUpRight,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TotalCard(
            label: 'الفرق',
            value: journalMoney.format(page.difference),
            tint: (page.isBalanced && !anyBroken)
                ? AppColors.success
                : AppColors.error,
            icon: PhosphorIconsBold.scales,
            // 🔴 المجموعُ متّزنٌ وفي الصفحة قيدٌ مكسور — الحالةُ التي يُخفيها
            //    الرقمُ وحدَه، فتُقال نصّاً لا لوناً فقط.
            hint: (page.isBalanced && anyBroken)
                ? 'بينها قيدٌ غيرُ متوازن'
                : null,
          ),
        ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.value,
    required this.tint,
    required this.icon,
    this.hint,
  });

  final String label;
  final String value;
  final Color tint;
  final IconData icon;

  /// سطرٌ صغيرٌ تحت القيمة — يُقال حين لا يكفي الرقمُ وحدَه.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.06),
        border: Border.all(color: tint.withValues(alpha: 0.20)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: text.labelSmall
                        ?.copyWith(color: AppColors.textMuted)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(
                        color: tint, fontWeight: FontWeight.w800)),
                if (hint != null)
                  Text(hint!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(color: AppColors.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقةُ قيدٍ واحدة — تتوسّع إلى سطورها عند النقر.
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.repo,
    required this.balance,
    required this.dateFormat,
    required this.expanded,
    required this.onToggle,
    required this.onPrint,
    required this.onReverse,
    required this.onApprove,
    required this.onOpenSource,
  });

  final JournalEntryData entry;
  final IAccountingRepository repo;

  /// مجموعا سطور القيد — من الاستعلام المُجمَّع، لا بقراءةٍ لكلّ صفّ.
  final JournalBalance balance;

  final DateFormat dateFormat;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<List<Map<String, dynamic>>> onPrint;
  final VoidCallback onReverse;
  final VoidCallback onApprove;

  /// يفتح المستندَ المصدر — قرارُ المالك 2026-09-18.
  final void Function(JournalSourceTarget target) onOpenSource;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final auto = entry.isAutoPosted;
    final tint = auto ? AppColors.info : AppColors.warning;

    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      auto
                          ? PhosphorIconsBold.lightning
                          : PhosphorIconsBold.notePencil,
                      size: 16,
                      color: tint,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 120,
                    child: Text(entry.entryNumber,
                        style: text.labelLarge?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800)),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(dateFormat.format(entry.entryDate),
                        style: text.labelMedium
                            ?.copyWith(color: AppColors.textSecondary)),
                  ),
                  Expanded(
                    child: Text(
                      _JournalEntriesPicPosScreenState.cleanDescription(
                          entry.description),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _Badge(
                    label: auto ? 'آلي' : 'يدوي',
                    tint: tint,
                  ),
                  const SizedBox(width: 6),
                  // «الحالة» — و«مرحّل» تُقال صراحةً لا بغياب شارة: الفرقُ
                  // بين «دخل الأستاذَ» و«ينتظر» هو ما يحكم زرَّ العكس تحته.
                  _Badge(
                    label: entry.isPosted ? 'مرحّل' : 'بانتظار الاعتماد',
                    tint: entry.isPosted ? AppColors.success : AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  // ثلاثةُ أعمدةِ التصميم — من الاستعلام المُجمَّع.
                  _NumCell(value: balance.debit, tint: AppColors.textPrimary),
                  _NumCell(value: balance.credit, tint: AppColors.textPrimary),
                  _NumCell(
                    value: balance.difference,
                    tint: balance.isBalanced
                        ? AppColors.textMuted
                        : AppColors.error,
                    bold: !balance.isBalanced,
                  ),
                  const SizedBox(width: 6),
                  // فعلُ الاعتماد لا يظهر إلّا لقيدٍ ينتظره — وإسقاطُه كان
                  // سيُخفي الفعلَ كلَّه من الشاشة المفروكة.
                  if (entry.needsApproval)
                    IconButton(
                      tooltip: 'اعتماد القيد',
                      iconSize: 15,
                      visualDensity: VisualDensity.compact,
                      color: AppColors.success,
                      icon: const Icon(PhosphorIconsBold.checkCircle),
                      onPressed: onApprove,
                    ),
                  // 🔴 **ولا يُعكَس إلّا ما رُحِّل** — والزرُّ معطَّلٌ بسببٍ
                  // ظاهرٍ لا مخفيّ. والقاعدةُ نفسُها محروسةٌ في الـDAO،
                  // فالتعطيلُ هنا تحسينُ تجربةٍ لا حارسٌ (المسارُ يُبلَغ من
                  // الشاشة الأصليّة ومن أيّ سكربت).
                  IconButton(
                    tooltip: entry.isPosted
                        ? 'عكس القيد'
                        : 'مسودة لم تُرحَّل — تُعتمَد أو تُعدَّل، ولا تُعكَس',
                    iconSize: 15,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(PhosphorIconsBold.arrowUUpLeft),
                    onPressed: entry.isPosted ? onReverse : null,
                  ),
                  Icon(
                    expanded
                        ? PhosphorIconsBold.caretUp
                        : PhosphorIconsBold.caretDown,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            FutureBuilder<List<Map<String, dynamic>>>(
              future: repo.getJournalEntryLinesWithAccounts(entry.id),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LinesTable(
                      lines: snap.data!,
                      onPrint: () => onPrint(snap.data!),
                    ),
                    _EntryFooter(entry: entry, repo: repo, onOpenSource: onOpenSource),
                    // v176 / §٨ — مستندُ القيد الورقيّ.
                    //
                    // ⚠️ **داخلَ الموسَّع لا في الرأس**: قائمةُ القيود قد
                    //    تحمل مئاتٍ، ولوحٌ لكلٍّ منها يعني مئةَ استعلامٍ
                    //    عند أوّل رسم.
                    //
                    // 🔴 **والترحيلُ لا يُقفل المرفقات.** القفلُ في هذا
                    //    النظام على **المبالغ**: قيدٌ مُرحَّلٌ لا تُبدَّل
                    //    أرقامُه. والمرفقُ ورقةٌ لا رقم — وأكثرُ ما
                    //    يُرفَق يصل **بعد** الترحيل (صورةُ الإيصال،
                    //    كشفُ البنك، إقرارُ المراجع). فقفلُه بالترحيل
                    //    يمنع الورقةَ في اللحظة التي تأتي فيها.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                      child: PicPosAttachmentsPanel(
                        entityType: 'journal_entry',
                        entityId: entry.id,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// تذييلُ القيد الموسَّع — «المنشئ» و«المرجع» وزرُّ «المستند المصدر».
///
/// ═══ قراراتُ المالك 2026-09-18 المُنفَّذةُ هنا ═══
///
/// ‏• **«المنشئ» يُعرَض** — ومصدرُه `journal_entries.created_by`، وهو الحقيقةُ
///   المخزَّنةُ على الصفّ نفسِه ويقرؤها ضابطُ «لا يعتمد القيدَ منشئُه».
/// ‏• **و«ملاحظات» تُسقَط** — الحقلُ لا وجودَ له على القيد أصلاً، والتصميمُ
///   يرسمه صفّاً فارغاً بشَرطة. فلا يُبنى: صفٌّ لا يحمل شيئاً أبداً ضجيجٌ.
/// ‏• **وزرُّ «المستند المصدر»** لا يُعرَض إلّا حين يكون له **أينَ يذهب**.
///
/// ⚠️ **و«لا يُعرَف» تُعرَض «—» لا اسماً مخمَّناً**: القيدُ الآليُّ بلا منشئٍ
/// بشريٍّ أصلاً، والقيدُ الأقدمُ من العمود لا سبيلَ لمعرفة منشئه. وكتابةُ
/// «النظام» مكانَهما تُخفي الفرقَ بين «آليٌّ» و«لا نعرف».
class _EntryFooter extends StatelessWidget {
  const _EntryFooter({
    required this.entry,
    required this.repo,
    required this.onOpenSource,
  });

  final JournalEntryData entry;
  final IAccountingRepository repo;
  final void Function(JournalSourceTarget target) onOpenSource;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const muted = AppColors.textMuted;
    final target = resolveJournalSourceTarget(
      referenceType: entry.referenceType,
      referenceId: entry.referenceId,
      allowedScreenIds: AppConfig.allowedScreenIds.toSet(),
    );

    Widget field(String label, Widget value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: text.labelSmall?.copyWith(color: muted)),
              const SizedBox(height: 2),
              value,
            ],
          ),
        );

    Widget plain(String v) => Text(
          v,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        );

    return Container(
      color: context.picposField,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          field(
            'المنشئ',
            FutureBuilder<String?>(
              future: repo.getJournalEntryCreator(entry.id),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return plain('…');
                }
                final name = snap.data;
                if (name != null) return plain(name);
                // آليٌّ ⇒ يُسمّى آليّاً؛ ويدويٌّ بلا منشئٍ ⇒ «—» لا اسمٌ.
                return Text(
                  entry.isAutoPosted ? 'ترحيل آلي' : '—',
                  style: text.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: muted),
                );
              },
            ),
          ),
          field(
            'المرجع',
            plain((entry.reference?.trim().isNotEmpty ?? false)
                ? entry.reference!.trim()
                : '—'),
          ),
          if (target != null)
            OutlinedButton.icon(
              onPressed: () => onOpenSource(target),
              icon: const Icon(PhosphorIconsBold.fileText, size: 14),
              label: Text(target.label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
        ],
      ),
    );
  }
}

/// خانةُ رقمٍ في صفّ القيد — عرضٌ ثابتٌ كي تصطفَّ الأعمدةُ رأسيّاً.
///
/// ⚠️ **ولا تنكمش**: عرضٌ مرنٌ يجعل الأرقامَ تتزحزح مع طول البيان فتُقرأ
/// الأعمدةُ الثلاثةُ ملتويةً — وهي أرقامٌ تُقارَن بالعين.
class _NumCell extends StatelessWidget {
  const _NumCell({required this.value, required this.tint, this.bold = false});

  final double value;
  final Color tint;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: Text(
        journalMoney.format(value),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.left,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: tint,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: tint, fontWeight: FontWeight.w800)),
    );
  }
}

/// سطورُ القيد وإجمالياته — وشارةُ «متوازن» تُقاس من الفرق لا تُفترض.
class _LinesTable extends StatelessWidget {
  const _LinesTable({required this.lines, required this.onPrint});

  final List<Map<String, dynamic>> lines;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // 🔴 **كانت `< 0.005` هنا — أشدَّ من مُصادِق المزامنة.** فقيدٌ يصل بفرق
    // ٠٫٠٠٧ يقبله `journal_sync_strategy` ويكتبه، ثمّ تعرضه هذه الشاشةُ
    // «غير متوازن» — ولا يملك المستخدمُ ما يصلحه به. والسماحيّةُ الآن
    // سماحيّةُ النظام: يقرؤها العرضُ كما يقرؤها الكاتب.
    final balance = JournalBalance.of([
      for (final l in lines)
        (
          debit: (l['debit'] as num?)?.toDouble() ?? 0,
          credit: (l['credit'] as num?)?.toDouble() ?? 0,
        ),
    ]);
    final totalDebit = balance.debit;
    final totalCredit = balance.credit;
    final balanced = balance.isBalanced;

    Widget cell(String v, {bool head = false, TextAlign align = TextAlign.start}) =>
        Text(
          v,
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (head ? text.labelSmall : text.labelMedium)?.copyWith(
            color: head ? AppColors.textMuted : context.picposText,
            fontWeight: head ? FontWeight.w800 : FontWeight.w600,
          ),
        );

    return Container(
      color: context.picposField,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 90, child: cell('رمز الحساب', head: true)),
                Expanded(child: cell('اسم الحساب', head: true)),
                Expanded(child: cell('البيان', head: true)),
                SizedBox(
                    width: 110,
                    child: cell('مدين', head: true, align: TextAlign.end)),
                SizedBox(
                    width: 110,
                    child: cell('دائن', head: true, align: TextAlign.end)),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                      width: 90,
                      child: cell(line['account_code']?.toString() ?? '')),
                  Expanded(
                      child: cell(line['account_name']?.toString() ?? '')),
                  Expanded(
                      child: cell(line['description']?.toString() ?? '')),
                  SizedBox(
                    width: 110,
                    child: cell(
                      _money(line['debit']),
                      align: TextAlign.end,
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: cell(
                      _money(line['credit']),
                      align: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                _Badge(
                  label: balanced ? 'متوازن' : 'غير متوازن',
                  tint: balanced ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 8),
                // «الفرق» **رقماً وشارةً معاً** — قرارُ المالك 2026-09-18.
                //
                // 🔴 **والشارةُ وحدَها لا تكفي**: «غير متوازن» لا تقول
                // بكم ولا في أيّ اتّجاه، فلا يُعرَف أهو ضجيجُ تقريبٍ أم
                // سطرٌ ناقص. والرقمُ **بإشارته**: موجبٌ مدينٌ زائد.
                Text('الفرق', style: text.labelSmall
                    ?.copyWith(color: AppColors.textMuted)),
                const SizedBox(width: 5),
                Text(
                  balance.difference
                      .toStringAsFixed(AppConstants.decimalPlaces),
                  style: text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: balanced ? AppColors.success : AppColors.error,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                Text('الإجمالي',
                    style: text.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: Text(
                    totalDebit.toStringAsFixed(AppConstants.decimalPlaces),
                    textAlign: TextAlign.end,
                    style: text.labelMedium?.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    totalCredit.toStringAsFixed(AppConstants.decimalPlaces),
                    textAlign: TextAlign.end,
                    style: text.labelMedium?.copyWith(
                        color: AppColors.error, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'طباعة القيد',
                  iconSize: 15,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(PhosphorIconsBold.printer),
                  onPressed: onPrint,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _money(Object? v) {
    final d = (v as num?)?.toDouble() ?? 0;
    return d > 0 ? d.toStringAsFixed(AppConstants.decimalPlaces) : '';
  }
}
