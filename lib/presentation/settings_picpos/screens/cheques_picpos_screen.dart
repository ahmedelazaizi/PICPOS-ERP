// «الشيكات والأوراق التجارية» — نسخةُ PicPos على «PicPos Cheques.dc.html».
//
// ملفُّ تصميمٍ **مستقلٌّ** (`MODULES = []`) بخمس تبويبات: الواردة · الصادرة ·
// جدول الاستحقاق · المرتجعة · سجل الحالات.
//
// ⚠️ **والميزةُ كاملةٌ في التطبيق باسمٍ آخر**: بحثٌ عن `class Cheques extends
// Table` يعطي **صفراً**، والجدولُ اسمُه `CommercialPapers` والمستودعُ
// والحواراتُ والـusecase كلُّها موجودة. صفرُ المطابقات نمطٌ غلطٌ قبل أن يكون
// غياباً.
//
// ═══ ما نُقل بقياس ═══
//
// • الحالاتُ الستُّ من الكود لا من التصميم: `pending`(بالخزنة) ·
//   `deposited`(مودع) · `cashed`(محصَّل) · `bounced`(مرتجع) ·
//   `endorsed`(مظهَّر) · `cancelled`(ملغى). التصميمُ يسمّي أربعاً، والكودُ
//   يكتب ستّاً — وإسقاطُ اثنتين يُخفي أوراقاً من كلّ الجداول بلا أثر.
//
// • «النوع» من `CommercialPapers.type`: شيك · كمبيالة · سند سحب.
//
// ⚠️ **وتبويبةُ «سجل الحالات» تعرض ورقةً واحدةً لا كلَّ الأوراق.**
// `watchPaperHistory` تأخذ **معرِّفَ ورقةٍ** واحدة، ولا واجهةَ تقرأ السجلَّ
// كلَّه. فبناءُ واحدةٍ تغييرٌ في طبقة البيانات؛ والمعروضُ ورقةٌ يختارها
// المشغّل. بندٌ في التسليم — وهو نفسُ حدِّ لوحة الزيارات في شاشة التوزيع.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/treasury_repository.dart' show SafeData;
import '../../screens/commercial_papers/create_paper_action.dart';
import '../../widgets/permission_guard.dart';
import 'cheques_picpos_create_dialog.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_entity_card.dart' show PicPosBlockHeader;
import '../../picpos_shell/picpos_hub_kpi.dart';
import '../../picpos_shell/picpos_report_tabs.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';

/// ملاحظاتُ التبويبات — نصوصُ `TABS.main[].note` حرفيّاً.
///
/// كلُّها قواعدُ محاسبةٍ تشرح سلوكاً قد يبدو خطأً: «الشيك الوارد لا يقلّل ذمة
/// العميل إلا عند التحصيل» تفسّر لماذا لم ينقص الرصيدُ بعد استلام الشيك.
const _tabNotes = [
  'الشيك الوارد لا يقلّل ذمة العميل إلا عند التحصيل',
  'الشيك الصادر يُقيَّد كالتزام حتى يُخصم من البنك',
  'الاستحقاق يُحسب من dueDate لا من تاريخ الإصدار',
  'الارتجاع يعيد الذمة ويسجّل مصروف عمولة',
  'كل انتقال حالة يُسجَّل بمن نفّذه — لا يُحذف',
];

/// الحالاتُ كما يكتبها الكودُ — لا كما يسمّيها التصميم.
const _statusLabels = <String, (String, Color)>{
  'pending': ('بالخزنة', AppColors.warning),
  'deposited': ('مودع', Color(0xFF4A80E8)),
  'cashed': ('محصَّل', AppColors.success),
  'bounced': ('مرتجع', AppColors.error),
  'endorsed': ('مظهَّر', Color(0xFF8B5CF6)),
  'cancelled': ('ملغى', AppColors.textMuted),
};

const _typeLabels = <String, String>{
  'cheque': 'شيك',
  'promissory_note': 'كمبيالة',
  'bill_of_exchange': 'سند سحب',
};

final _papersProvider =
    StreamProvider.autoDispose<List<CommercialPaperData>>((ref) {
  return ref.watch(commercialPapersRepositoryProvider).watchCommercialPapers();
});

final _historyProvider = StreamProvider.autoDispose
    .family<List<PaperStatusHistoryData>, int>((ref, paperId) {
  return ref.watch(commercialPapersRepositoryProvider).watchPaperHistory(paperId);
});

class ChequesPicposScreen extends ConsumerStatefulWidget {
  const ChequesPicposScreen({super.key});

  @override
  ConsumerState<ChequesPicposScreen> createState() =>
      _ChequesPicposScreenState();
}

class _ChequesPicposScreenState extends ConsumerState<ChequesPicposScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Map<int, int> _chip = {};
  int? _historyPaperId;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTab);
  }

  void _onTab() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _hit(String? s) =>
      _query.isEmpty || (s ?? '').toLowerCase().contains(_query);

  String _partyName(List<Party> parties, int id) =>
      parties.where((p) => p.id == id).firstOrNull?.name ?? 'طرف #$id';

  static String _d(DateTime x) =>
      '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';

  /// «ورقة جديدة» — الفعلُ الأوّلُ في رأس التصميم.
  ///
  /// ⚠️ الاتّجاهُ الابتدائيُّ يتبع **التبويبةَ المفتوحة**: مَن يقف على
  /// «الصادرة» يريد صادرةً غالباً. والتبويباتُ الثلاثُ الأخرى ليست
  /// اتّجاهاً، فتُقرأ واردة.
  Future<void> _createPaper(List<Party> parties) async {
    final safes = await ref.read(treasuryRepositoryProvider).getSafesList();
    if (!mounted) return;
    final banks =
        safes.where((s) => s.safeType == 'bank' && s.isActive).toList();

    final form = await showChequePicposCreateDialog(
      context,
      direction: _tabs.index == 1 ? 'issued' : 'received',
      parties: parties,
      bankSafes: banks,
    );
    if (form == null || !mounted) return;

    try {
      // ⚠️ الدالّةُ **مشتركةٌ** مع الشاشة القديمة: سَكُّ `globalId` مرّةً ثمّ
      //    كتابتان به. نسختان تنحرفان بأوّل تعديل — راجع تعليقَها.
      await createCommercialPaper(
        repo: ref.read(commercialPapersRepositoryProvider),
        // ⚠️ من **النموذج** لا من التبويبة: الحوارُ يسمح بتبديل الاتّجاه.
        direction: form['direction'] as String,
        form: form,
      );
      if (!mounted) return;
      ref.invalidate(_papersProvider);
      _snack('أُنشئت الورقة');
    } catch (e) {
      if (!mounted) return;
      _snack('تعذّر الإنشاء: $e');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final List<CommercialPaperData> papers =
        ref.watch(_papersProvider).value ?? const [];
    final List<Party> parties = ref.watch(allPartiesProvider).value ?? const [];

    final incoming = papers.where((p) => p.direction == 'received').toList();
    final outgoing = papers.where((p) => p.direction == 'issued').toList();
    final bounced = papers.where((p) => p.status == 'bounced').toList();

    return PicPosScreenScaffold(
      title: 'الشيكات والأوراق التجارية',
      subtitle: 'الوارد والصادر والاستحقاق والتجيير والارتجاع',
      icon: PhosphorIconsBold.note,
      // ⚠️ **رأسُ التصميم فعلان، وكان الفوركُ بلا أيٍّ منهما.** فالشاشةُ
      //    تعرض الأوراقَ ولا تُنشئ ورقةً — والمستخدمُ يرجع إلى الشاشة
      //    القديمة ليضيف شيكاً ثمّ يعود ليراه هنا.
      //
      // 🔴 وحارسُ الصلاحيّة واجبٌ: إنشاءُ ورقةٍ يفتح ذمّةً ويكتب على
      //    الخادم في وضع العميل. وحصرُ التنقّل يفتح الشاشةَ للقراءة.
      headerActions: [
        PermissionGuard(
          permission: PermissionCodes.commercialPapersManage,
          child: FilledButton.icon(
            onPressed: () => _createPaper(parties),
            icon: const Icon(PhosphorIconsBold.plus, size: 15),
            label: const Text('ورقة جديدة'),
          ),
        ),
      ],
      headerSearch: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'ابحث برقم الشيك أو الطرف...',
          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(PhosphorIconsBold.x, size: 14),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
        ),
      ),
      subHeader: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PicPosReportTabs(
            controller: _tabs,
            tabs: [
              (
                label: 'الواردة',
                icon: PhosphorIconsBold.arrowCircleDown,
                badge: '${incoming.length}'
              ),
              (
                label: 'الصادرة',
                icon: PhosphorIconsBold.arrowCircleUp,
                badge: '${outgoing.length}'
              ),
              (
                label: 'جدول الاستحقاق',
                icon: PhosphorIconsBold.calendarCheck,
                badge: null
              ),
              (
                label: 'المرتجعة',
                icon: PhosphorIconsBold.warningOctagon,
                badge: '${bounced.length}'
              ),
              (
                label: 'سجل الحالات',
                icon: PhosphorIconsBold.clockCounterClockwise,
                badge: null
              ),
            ],
          ),
          PicPosTabNote(note: _tabNotes[_tabs.index]),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: TabBarView(
        controller: _tabs,
        children: [
          _scroll(_directionTab(context, incoming, parties, 0, 'الواردة',
              'من العملاء — تُودع بالبنك ثمّ تُحصَّل')),
          _scroll(_directionTab(context, outgoing, parties, 1, 'الصادرة',
              'للموردين — التزامٌ حتّى يُخصم من البنك')),
          _scroll(_dueTab(context, papers, parties)),
          _scroll(_bouncedTab(context, bounced, parties)),
          _scroll(_historyTab(context, papers, parties)),
        ],
      ),
    );
  }

  Widget _scroll(Widget child) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
        child: child,
      );

  List<PicPosTableColumn> get _paperCols => const [
        PicPosTableColumn('رقم الورقة', flex: 1.3),
        PicPosTableColumn('الطرف', flex: 1.7),
        PicPosTableColumn('البنك', flex: 1.4),
        PicPosTableColumn('الإصدار', flex: 1.2),
        PicPosTableColumn('الاستحقاق', flex: 1.2),
        PicPosTableColumn('المبلغ', flex: 1.2, align: PicPosCellAlign.end),
        PicPosTableColumn('الحالة', flex: 1.2),
      ];

  List<PicPosTableRow> _paperRows(
    List<CommercialPaperData> papers,
    List<Party> parties,
  ) =>
      [
        for (final p in papers)
          PicPosTableRow(
            cells: [
              PicPosTextCell(
                p.paperNumber,
                sub: _typeLabels[p.type] ?? p.type,
                icon: p.type == 'promissory_note'
                    ? PhosphorIconsBold.scroll
                    : PhosphorIconsBold.note,
                tint: _statusLabels[p.status]?.$2 ?? AppColors.primary,
              ),
              PicPosTextCell(_partyName(parties, p.partyId)),
              PicPosTextCell(
                p.bankName ?? '—',
                sub: p.bankBranch,
              ),
              PicPosTextCell(_d(p.issueDate)),
              PicPosTextCell(_d(p.dueDate)),
              PicPosTextCell(p.amount.toStringAsFixed(0)),
              PicPosPillCell(
                _statusLabels[p.status]?.$1 ?? p.status,
                _statusLabels[p.status]?.$2 ?? AppColors.textMuted,
              ),
            ],
          ),
      ];

  double _sum(List<CommercialPaperData> l) =>
      l.fold<double>(0, (s, p) => s + p.amount);

  // ── الواردة / الصادرة ──────────────────────────────────────────────────

  Widget _directionTab(
    BuildContext context,
    List<CommercialPaperData> papers,
    List<Party> parties,
    int tabIndex,
    String title,
    String subtitle,
  ) {
    // شرائحُ الترشيح — وعدّادُ كلٍّ منها **محسوبٌ** من نفس القائمة.
    final chipDefs = <(String, bool Function(CommercialPaperData))>[
      ('الكل', (p) => true),
      ('بالخزنة', (p) => p.status == 'pending'),
      ('مودعة', (p) => p.status == 'deposited'),
      ('محصَّلة', (p) => p.status == 'cashed'),
      ('مرتجعة', (p) => p.status == 'bounced'),
    ];
    final pick = _chip[tabIndex] ?? 0;
    final shown = papers
        .where((p) =>
            chipDefs[pick].$2(p) &&
            (_hit(p.paperNumber) || _hit(_partyName(parties, p.partyId))))
        .toList();

    final week = DateTime.now().add(const Duration(days: 7));
    final dueSoon = papers
        .where((p) =>
            (p.status == 'pending' || p.status == 'deposited') &&
            p.dueDate.isBefore(week))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: PhosphorIconsBold.note,
              label: 'عددُ الأوراق',
              value: '${papers.length}',
              tint: AppColors.primary,
              vs: '${papers.where((p) => p.status == 'pending').length} '
                  'بالخزنة',
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.currencyCircleDollar,
              label: 'قيمتها',
              value: _sum(papers).toStringAsFixed(0),
              tint: AppColors.success,
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.vault,
              label: 'مودعة بالبنك',
              value:
                  '${papers.where((p) => p.status == 'deposited').length}',
              tint: const Color(0xFF4A80E8),
              vs: _sum(papers.where((p) => p.status == 'deposited').toList())
                  .toStringAsFixed(0),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.hourglass,
              label: 'تستحقّ خلال أسبوع',
              value: '${dueSoon.length}',
              tint: AppColors.warning,
              up: false,
              vs: _sum(dueSoon).toStringAsFixed(0),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PicPosDataTable(
          title: title,
          subtitle: subtitle,
          emptyLabel: 'لا أوراقَ مطابقة',
          columns: _paperCols,
          chips: [
            for (var i = 0; i < chipDefs.length; i++)
              PicPosTableChip(
                label: chipDefs[i].$1,
                count: '${papers.where(chipDefs[i].$2).length}',
                onTap: () => setState(() => _chip[tabIndex] = i),
              ),
          ],
          selectedChip: pick,
          rows: _paperRows(shown, parties),
          totals: [
            '${shown.length} ورقة',
            '',
            '',
            '',
            '',
            _sum(shown).toStringAsFixed(0),
            '',
          ],
        ),
      ],
    );
  }

  // ── جدول الاستحقاق ─────────────────────────────────────────────────────

  Widget _dueTab(
    BuildContext context,
    List<CommercialPaperData> papers,
    List<Party> parties,
  ) {
    // ⚠️ **المفتوحةُ وحدَها**: ورقةٌ محصَّلةٌ أو ملغاةٌ لا استحقاقَ لها،
    //    وإدراجُها يجعل الجدولَ يعِد بمطالباتٍ انتهت.
    final open = papers
        .where((p) => p.status == 'pending' || p.status == 'deposited')
        .where((p) =>
            _hit(p.paperNumber) || _hit(_partyName(parties, p.partyId)))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    final now = DateTime.now();
    final overdue = open.where((p) => p.dueDate.isBefore(now)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: PhosphorIconsBold.calendarCheck,
              label: 'أوراقٌ مفتوحة',
              value: '${open.length}',
              tint: AppColors.primary,
              vs: _sum(open).toStringAsFixed(0),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.warningOctagon,
              label: 'تجاوزت الاستحقاق',
              value: '${overdue.length}',
              tint: AppColors.error,
              up: false,
              vs: _sum(overdue).toStringAsFixed(0),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PicPosDataTable(
          title: 'جدول الاستحقاق',
          subtitle: 'الاستحقاق يُحسب من dueDate لا من تاريخ الإصدار',
          emptyLabel: 'لا أوراقَ مفتوحة',
          columns: const [
            PicPosTableColumn('رقم الورقة', flex: 1.3),
            PicPosTableColumn('الطرف', flex: 1.7),
            PicPosTableColumn('الاتّجاه', flex: 1.1),
            PicPosTableColumn('الاستحقاق', flex: 1.3),
            PicPosTableColumn('المبلغ', flex: 1.2,
                align: PicPosCellAlign.end),
            PicPosTableColumn('الحالة', flex: 1.2),
          ],
          rows: [
            for (final p in open)
              PicPosTableRow(
                cells: [
                  PicPosTextCell(
                    p.paperNumber,
                    sub: _typeLabels[p.type] ?? p.type,
                    icon: PhosphorIconsBold.note,
                    tint: p.dueDate.isBefore(now)
                        ? AppColors.error
                        : AppColors.primary,
                  ),
                  PicPosTextCell(_partyName(parties, p.partyId)),
                  PicPosPillCell(
                    p.direction == 'received' ? 'وارد' : 'صادر',
                    p.direction == 'received'
                        ? AppColors.success
                        : const Color(0xFF8B5CF6),
                  ),
                  PicPosTextCell(
                    _d(p.dueDate),
                    // ⚠️ السطرُ الخافتُ يقول «متأخّرة» لا يلوّن التاريخَ
                    //    وحدَه: اللونُ لا يُقرَأ في طباعةٍ أو لعينٍ لا تميّزه.
                    // ⚠️ نصٌّ **مختلفٌ** عن تسمية المؤشّر أعلاه («تجاوزت
                    //    الاستحقاق»): تطابقُهما يجعل أيَّ فحصٍ على النصّ
                    //    يعدّ الاثنين، ويجعل المشغّلَ يظنّ العنوانَ صفّاً.
                    sub: p.dueDate.isBefore(now) ? 'متأخّرة عن موعدها' : null,
                  ),
                  PicPosTextCell(p.amount.toStringAsFixed(0)),
                  PicPosPillCell(
                    _statusLabels[p.status]?.$1 ?? p.status,
                    _statusLabels[p.status]?.$2 ?? AppColors.textMuted,
                  ),
                ],
              ),
          ],
          totals: [
            '${open.length} ورقة',
            '',
            '',
            '',
            _sum(open).toStringAsFixed(0),
            '',
          ],
        ),
      ],
    );
  }

  // ── المرتجعة ───────────────────────────────────────────────────────────

  Widget _bouncedTab(
    BuildContext context,
    List<CommercialPaperData> bounced,
    List<Party> parties,
  ) {
    final shown = bounced
        .where((p) =>
            _hit(p.paperNumber) || _hit(_partyName(parties, p.partyId)))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: PhosphorIconsBold.warningOctagon,
              label: 'أوراقٌ مرتجعة',
              value: '${bounced.length}',
              tint: AppColors.error,
              up: false,
              vs: _sum(bounced).toStringAsFixed(0),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PicPosDataTable(
          title: 'الأوراق المرتجعة',
          subtitle: 'الارتجاع يعيد الذمة ويسجّل مصروف عمولة',
          emptyLabel: 'لا أوراقَ مرتجعة',
          columns: _paperCols,
          rows: _paperRows(shown, parties),
        ),
      ],
    );
  }

  // ── سجل الحالات ────────────────────────────────────────────────────────

  Widget _historyTab(
    BuildContext context,
    List<CommercialPaperData> papers,
    List<Party> parties,
  ) {
    if (papers.isEmpty) {
      return _empty(context, 'لا أوراقَ بعد — سجلُّ الحالات يظهر بعد أوّل ورقة');
    }
    final id = _historyPaperId ?? papers.first.id;
    final history = ref.watch(_historyProvider(id)).value ?? const [];
    final paper = papers.where((p) => p.id == id).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ⚠️ منتقي الورقة **ليس زينة**: `watchPaperHistory` تقرأ ورقةً واحدة،
        //    ولا واجهةَ تقرأ السجلَّ كلَّه. فالمشغّلُ يختار.
        PicPosBlockHeader(
          title: 'سجل الحالات',
          subtitle: paper == null
              ? null
              : 'الورقةُ المعروضة: ${paper.paperNumber}',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in papers.take(12))
              ChoiceChip(
                label: Text(p.paperNumber),
                selected: p.id == id,
                onSelected: (_) => setState(() => _historyPaperId = p.id),
              ),
          ],
        ),
        const SizedBox(height: 14),
        PicPosDataTable(
          title: 'انتقالات الحالة',
          subtitle: 'كل انتقال حالة يُسجَّل بمن نفّذه — لا يُحذف',
          emptyLabel: 'لا انتقالاتٍ مسجَّلةٍ لهذه الورقة',
          columns: const [
            PicPosTableColumn('من', flex: 1.2),
            PicPosTableColumn('إلى', flex: 1.2),
            PicPosTableColumn('التاريخ', flex: 1.4),
            PicPosTableColumn('ملاحظات', flex: 2.2),
          ],
          rows: [
            for (final h in history)
              PicPosTableRow(
                cells: [
                  PicPosPillCell(
                    _statusLabels[h.fromStatus]?.$1 ?? h.fromStatus,
                    _statusLabels[h.fromStatus]?.$2 ?? AppColors.textMuted,
                  ),
                  PicPosPillCell(
                    _statusLabels[h.toStatus]?.$1 ?? h.toStatus,
                    _statusLabels[h.toStatus]?.$2 ?? AppColors.textMuted,
                  ),
                  PicPosTextCell(_d(h.changedAt)),
                  PicPosTextCell(h.notes ?? '—'),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _empty(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: context.picposMuted,
            ),
          ),
        ),
      );
}
