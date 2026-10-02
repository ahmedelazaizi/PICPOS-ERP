import 'package:ural_erp/core/i18n/tr.dart';
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
import '../../screens/commercial_papers/deposit_papers_action.dart';
import '../../screens/commercial_papers/paper_status_actions.dart';
import '../../treasury_picpos/screens/cheque_books_picpos_screen.dart';
import '../../widgets/permission_guard.dart';
import 'cheques_picpos_deposit_dialog.dart';
import 'cheques_picpos_endorse_dialog.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_entity_card.dart' show PicPosBlockHeader;
import '../../picpos_shell/picpos_hub_kpi.dart';
import '../../picpos_shell/picpos_report_tabs.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../../core/navigation/screen_id.dart';
import '../../../data/providers/screen_navigation_provider.dart';

/// ملاحظاتُ التبويبات — نصوصُ `TABS.main[].note` حرفيّاً.
///
/// كلُّها قواعدُ محاسبةٍ تشرح سلوكاً قد يبدو خطأً: «الشيك الوارد لا يقلّل ذمة
/// العميل إلا عند التحصيل» تفسّر لماذا لم ينقص الرصيدُ بعد استلام الشيك.
List<String> get _tabNotes => [
  tr('الشيك الوارد لا يقلّل ذمة العميل إلا عند التحصيل'),
  tr('الشيك الصادر يُقيَّد كالتزام حتى يُخصم من البنك'),
  tr('الاستحقاق يُحسب من dueDate لا من تاريخ الإصدار'),
  tr('الارتجاع يعيد الذمة ويسجّل مصروف عمولة'),
  tr('كل انتقال حالة يُسجَّل بمن نفّذه — لا يُحذف'),
  tr('الشيك الصادر يُسحب رقمه من الدفتر في سند الصرف — لا حركة مالية هنا'),
];

/// الحالاتُ كما يكتبها الكودُ — لا كما يسمّيها التصميم.
///
/// ⚠️ **و«مودع» حالتان لا واحدة.** مقيسٌ في `commercial_papers_dao.dart`:
/// `updatePaperStatus(id,'deposited')` يكتب `deposited`، بينما
/// `depositForCollection()` يكتب `deposited_for_collection` — والمُبدِّلُ
/// المحاسبيُّ يعالجهما **معاً** كحالةٍ وسيطةٍ لا تلمس البنك (‏سطرا 392 و485).
/// فهما اسمان لشيءٍ واحد.
///
/// 🔴 وإسقاطُ الطويلة كان يُظهر السلسلةَ الإنجليزيّةَ خامّةً في رقاقة الحالة،
/// ويُسقط الورقةَ من شريحة «مودعة» — أيْ أنّ الإيداعَ ينجح والورقةُ تختفي.
Map<String, (String, Color)> get _statusLabels => <String, (String, Color)>{
  'pending': (tr('بالخزنة'), AppColors.warning),
  'in_portfolio': (tr('بالحافظة'), const Color(0xFF6366F1)),
  'deposited': (tr('مودع'), const Color(0xFF4A80E8)),
  'deposited_for_collection': (tr('برسم التحصيل'), const Color(0xFF4A80E8)),
  'partial_collected': (tr('محصَّل جزئيّاً'), const Color(0xFF14B8A6)),
  'cashed': (tr('محصَّل'), AppColors.success),
  'bounced': (tr('مرتجع'), AppColors.error),
  'endorsed': (tr('مظهَّر'), const Color(0xFF8B5CF6)),
  'cancelled': (tr('ملغى'), AppColors.textMuted),
};

/// الحالتان اللتان تعنيان «عند البنك تحت التحصيل».
///
/// ⚠️ اقرأها في كلّ ترشيحٍ بدل `== 'deposited'` — راجع [_statusLabels].
bool _isDeposited(String s) =>
    s == 'deposited' || s == 'deposited_for_collection';

/// الحالتان اللتان يقبلهما `depositForCollection` — حارسُ الـDAO حرفاً:
/// `if (!['pending','in_portfolio'].contains(paper.status)) throw`.
///
/// 🔴 فورقةٌ مرتجعةٌ تُلقي دائماً هنا، ومسارُها الصحيحُ
/// `updatePaperStatus(id,'deposited')` — وهو ما يفعله زرُّ «إعادة إيداع».
bool _canDeposit(String s) => s == 'pending' || s == 'in_portfolio';

Map<String, String> get _typeLabels => <String, String>{
  'cheque': tr('شيك'),
  'promissory_note': tr('كمبيالة'),
  'bill_of_exchange': tr('سند سحب'),
};

final _papersProvider =
    StreamProvider.autoDispose<List<CommercialPaperData>>((ref) {
  return ref.watch(commercialPapersRepositoryProvider).watchCommercialPapers();
});

/// E-fix ٢ (v186) — ساحبُ كلِّ ورقةٍ (وارد) / مستفيدُها (صادر)، يتجدّد مع
/// قائمة الأوراق. وفشلُ قراءته لا يُخفي القائمة: عرضٌ إضافيٌّ لا شرط.
final _drawersProvider = FutureProvider.autoDispose<
    Map<int, ({int? accountId, String? name})>>((ref) async {
  ref.watch(_papersProvider);
  try {
    return await ref
        .watch(commercialPapersRepositoryProvider)
        .getPaperDrawers();
  } catch (_) {
    return const {};
  }
});

/// «الساحب: …» / «المستفيد: …» — أو `null` حين لا ساحبَ مسجَّلاً.
String? _drawerLabel(
    CommercialPaperData p, Map<int, ({int? accountId, String? name})> all) {
  final name = all[p.id]?.name;
  if (name == null || name.isEmpty) return null;
  return p.direction == 'issued'
      ? tr('المستفيد: {p0}', {'p0': trData(name)})
      : tr('الساحب: {p0}', {'p0': trData(name)});
}

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
  // E4 — التبويبُ السادس «دفتر الشيكات» (نُقل من شاشته المستقلّة).
  late final TabController _tabs = TabController(length: 6, vsync: this);
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Map<int, int> _chip = {};
  int? _historyPaperId;

  /// مرشِّحُ **النوع** — قرارُ المالك: يُظهر الكمبيالةَ وسندَ السحب.
  ///
  /// 🔴 **والنوعان كانا مخفيَّين**: `_typeLabels` تعرفهما منذ زمنٍ وتُظهرهما
  /// سطراً خافتاً تحت رقم الورقة، ولا سبيلَ لعزلهما. فمن عنده كمبيالاتٌ
  /// يقلّب الصفحاتِ كلَّها ليجدها بين الشيكات.
  String _typeFilter = 'all';

  /// الورقةُ المختارة — **واحدةٌ** بحكم زرّ الراديو.
  ///
  /// ⚠️ **مفردٌ لا متعدّد**: شريطُ الإجراءات تحت الجدول يخصّ ورقةً بعينها
  /// (سندُها · إيداعُها · عرضُ سندها)، فمربّعُ تعليمٍ كان يَعِد بتعدّدٍ لا
  /// يقع. والإيداعُ الجماعيُّ زرٌّ مستقلٌّ في الرأس وله حوارُه.
  int? _selectedPaperId;

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
      parties.where((p) => p.id == id).firstOrNull?.name ?? tr('طرف #{id}', {'id': id});

  static String _d(DateTime x) =>
      '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';

  /// «ورقة جديدة» — الفعلُ الأوّلُ في رأس التصميم.
  ///
  /// ⚠️ الاتّجاهُ الابتدائيُّ يتبع **التبويبةَ المفتوحة**: مَن يقف على
  /// «الصادرة» يريد صادرةً غالباً. والتبويباتُ الثلاثُ الأخرى ليست
  /// اتّجاهاً، فتُقرأ واردة.
  ///
  /// ═══ E4 (قرارُ المالك، الخيار ب) — أُزيل الإنشاءُ من هذه الشاشة ═══
  ///
  /// «إدارة الشيكات» صارت **استعلاماً** للإنشاء: الشيكُ يُنشأ من سند
  /// القبض/الصرف بطريقة «شيكات» وحدَه (رقمُه وبنكُه واستحقاقُه وساحبُه،
  /// والصادرُ من دفتر الشيكات). وما كان هنا:
  ///   ⚠️ الدالّةُ **مشتركةٌ** مع الشاشة القديمة: سَكُّ `globalId` مرّةً ثمّ
  ///      كتابتان به. نسختان تنحرفان بأوّل تعديل — راجع تعليقَها.
  ///   ⚠️ من **النموذج** لا من التبويبة: الحوارُ يسمح بتبديل الاتّجاه.
  /// وإجراءاتُ الحالة (إيداع · تحصيل · ارتجاع · تجيير · إعادة) باقيةٌ هنا.

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// «إيداع دفعة شيكات» — الفعلُ الثاني في رأس التصميم (`HEADS.main.alt`).
  ///
  /// ⚠️ **المرشَّحون [_canDeposit] وحدَهم.** حارسُ الـDAO يرفض ما عداهما،
  /// وعرضُ ورقةٍ مرتجعةٍ في الرقاقات يعني زرَّ إيداعٍ يُلقي دائماً.
  ///
  /// و[only] تُمرَّر من زرِّ الصفّ ليُفتَح الحوارُ على ورقتها معلَّمةً.
  Future<void> _depositBatch(
    List<CommercialPaperData> papers,
    List<Party> parties, {
    int? only,
  }) async {
    final safes = await ref.read(treasuryRepositoryProvider).getSafesList();
    if (!mounted) return;
    final banks =
        safes.where((s) => s.safeType == 'bank' && s.isActive).toList();

    final candidates = [
      for (final p in papers.where((p) => _canDeposit(p.status)))
        DepositCandidate(
          id: p.id,
          paperNumber: p.paperNumber,
          amount: p.amount,
          dueDate: p.dueDate,
          partyName: _partyName(parties, p.partyId),
        ),
    ];

    final form = await showChequesPicposDepositDialog(
      context,
      candidates: candidates,
      bankSafes: banks,
      preselected: only == null ? const {} : {only},
    );
    if (form == null || !mounted) return;

    final userId = ref.read(authProvider).user?.id;
    final voucher = form.voucherNumber;
    final result = await depositPapersForCollection(
      repo: ref.read(commercialPapersRepositoryProvider),
      paperIds: form.paperIds,
      bankSafeId: form.bankSafeId,
      changedBy: userId,
      // رقمُ القسيمة يخصّ الدفعةَ كلَّها فيُكتَب على كلّ ورقةٍ فيها.
      notes: voucher.isEmpty ? null : tr('إيداع برسم التحصيل — قسيمة {voucher}', {'voucher': voucher}),
    );
    if (!mounted) return;

    ref.invalidate(_papersProvider);
    // ⚠️ **يُقال الرقمُ لا «تمّ»**: دفعةٌ نجح ثلاثةٌ من خمسةٍ فيها تُبلَّغ
    //    «تمّ الإيداع» فيظنّ المشغّلُ القسيمةَ كاملةً وهي ناقصة.
    _snack(
      result.allSucceeded
          ? tr('أُودعت {p0} ورقة', {'p0': result.count})
          : tr('أُودعت {p0} من {p1} — تعذّر: {p2}', {'p0': result.count, 'p1': form.paperIds.length, 'p2': result.failed.keys.join(tr('، '))}),
    );
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
      // الاسمُ من الثابت المشترك — راجع [chequesScreenLabel] لِمَ موضعٌ واحد.
      title: chequesScreenLabel,
      subtitle: tr('الوارد والصادر والاستحقاق والتجيير والارتجاع'),
      icon: PhosphorIconsBold.note,
      // ⚠️ **رأسُ التصميم فعلان، وكان الفوركُ بلا أيٍّ منهما.** فالشاشةُ
      //    تعرض الأوراقَ ولا تُنشئ ورقةً — والمستخدمُ يرجع إلى الشاشة
      //    القديمة ليضيف شيكاً ثمّ يعود ليراه هنا.
      //
      // 🔴 وحارسُ الصلاحيّة واجبٌ: إنشاءُ ورقةٍ يفتح ذمّةً ويكتب على
      //    الخادم في وضع العميل. وحصرُ التنقّل يفتح الشاشةَ للقراءة.
      headerActions: [
        // الفعلُ الثاني (`HEADS.main.alt`) — ثانويٌّ بصريّاً كما في التصميم.
        PermissionGuard(
          permission: PermissionCodes.commercialPapersManage,
          child: OutlinedButton.icon(
            onPressed: () => _depositBatch(papers, parties),
            icon: const Icon(PhosphorIconsBold.vault, size: 15),
            label:  Text(tr('إيداع دفعة شيكات')),
          ),
        ),
        // E4 — لا زرَّ «ورقة جديدة»: الإنشاءُ من سندَي القبض والصرف وحدَهما.
      ],
      headerSearch: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        decoration: InputDecoration(
          isDense: true,
          hintText: tr('ابحث برقم الشيك أو الطرف...'),
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
                label: tr('الواردة'),
                icon: PhosphorIconsBold.arrowCircleDown,
                badge: '${incoming.length}'
              ),
              (
                label: tr('الصادرة'),
                icon: PhosphorIconsBold.arrowCircleUp,
                badge: '${outgoing.length}'
              ),
              (
                label: tr('جدول الاستحقاق'),
                icon: PhosphorIconsBold.calendarCheck,
                badge: null
              ),
              (
                label: tr('المرتجعة'),
                icon: PhosphorIconsBold.warningOctagon,
                badge: '${bounced.length}'
              ),
              (
                label: tr('سجل الحالات'),
                icon: PhosphorIconsBold.clockCounterClockwise,
                badge: null
              ),
              (
                label: tr('دفتر الشيكات'),
                icon: PhosphorIconsBold.checkSquareOffset,
                badge: null
              ),
            ],
          ),
          // مرشِّحُ النوع — قرارُ المالك 2026-09-18. والعدّادُ على كلّ شريحةٍ
          // **محسوبٌ** من نفس القائمة، فشريحةٌ بصفرٍ تقول «لا كمبيالاتِ
          // عندك» بدل أن تفتح جدولاً فارغاً بلا تفسير.
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.funnel,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    ButtonSegment(
                        value: 'all', label: Text(tr('الكل ({p0})', {'p0': papers.length}))),
                    for (final e in _typeLabels.entries)
                      ButtonSegment(
                        value: e.key,
                        label: Text('${e.value} '
                            '(${papers.where((p) => p.type == e.key).length})'),
                      ),
                  ],
                  selected: {_typeFilter},
                  onSelectionChanged: (s) => setState(() {
                    _typeFilter = s.first;
                    // ⚠️ الاختيارُ يسقط مع الترشيح: ورقةٌ اختيرت ثمّ أُخفيت
                    //    تترك شريطَ إجراءاتٍ يعمل على ما لا يُرى.
                    _selectedPaperId = null;
                  }),
                ),
              ],
            ),
          ),
          PicPosTabNote(note: _tabNotes[_tabs.index]),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: TabBarView(
        controller: _tabs,
        children: [
          _scroll(_directionTab(context, incoming, parties, 0, tr('الواردة'),
              tr('من العملاء — تُودع بالبنك ثمّ تُحصَّل'))),
          _scroll(_directionTab(context, outgoing, parties, 1, tr('الصادرة'),
              tr('للموردين — التزامٌ حتّى يُخصم من البنك'))),
          _scroll(_dueTab(context, papers, parties)),
          _scroll(_bouncedTab(context, bounced, parties)),
          _scroll(_historyTab(context, papers, parties)),
          // E4 — شاشةُ الدفتر كما هي (صلاحيّتُها ومنطقُها)، ولا حركةَ مال فيها.
          const ChequeBooksPicposScreen(key: Key('cheques_cheque_book_tab')),
        ],
      ),
    );
  }

  Widget _scroll(Widget child) => SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 26),
        child: child,
      );

  /// أعمدةُ الجدول **مع** خانةِ الاختيار — والعرضُ ضيّقٌ مقصود: زرُّ راديو
  /// لا نصّ. وطولُ [PicPosDataTable.totals] يجب أن يطابقها خانةً بخانة.
  List<PicPosTableColumn> get _selectableCols =>  [
        const PicPosTableColumn('', flex: 0.35),
        PicPosTableColumn(tr('رقم الورقة'), flex: 1.3),
        PicPosTableColumn(tr('الطرف'), flex: 1.7),
        PicPosTableColumn(tr('البنك'), flex: 1.4),
        PicPosTableColumn(tr('الإصدار'), flex: 1.2),
        PicPosTableColumn(tr('الاستحقاق'), flex: 1.2),
        PicPosTableColumn(tr('المبلغ'), flex: 1.2, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('الحالة'), flex: 1.2),
        PicPosTableColumn(tr('إجراء'), flex: 1.3),
      ];

  List<PicPosTableColumn> get _paperCols =>  [
        PicPosTableColumn(tr('رقم الورقة'), flex: 1.3),
        PicPosTableColumn(tr('الطرف'), flex: 1.7),
        PicPosTableColumn(tr('البنك'), flex: 1.4),
        PicPosTableColumn(tr('الإصدار'), flex: 1.2),
        PicPosTableColumn(tr('الاستحقاق'), flex: 1.2),
        PicPosTableColumn(tr('المبلغ'), flex: 1.2, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('الحالة'), flex: 1.2),
        PicPosTableColumn(tr('إجراء'), flex: 1.3),
      ];

  /// صفوفُ الجدول **باختيارٍ مفرد**.
  ///
  /// ⚠️ **والنقرُ على الصفّ كلِّه يختار**: زرُّ الراديو هدفٌ صغير، وإلزامُ
  /// المستخدم بإصابته يجعل الاختيارَ عملاً. والنقرةُ الثانيةُ تُلغي
  /// الاختيارَ — فلا يبقى شريطُ إجراءاتٍ مفتوحاً بلا سبيلٍ لإغلاقه.
  List<PicPosTableRow> _selectableRows(
    List<CommercialPaperData> papers,
    List<Party> parties,
  ) =>
      [
        for (final p in papers)
          PicPosTableRow(
            selected: p.id == _selectedPaperId,
            onTap: () => setState(() =>
                _selectedPaperId = _selectedPaperId == p.id ? null : p.id),
            cells: [
              PicPosRadioCell(
                selected: p.id == _selectedPaperId,
                onSelect: () => setState(() =>
                    _selectedPaperId = _selectedPaperId == p.id ? null : p.id),
              ),
              ..._paperCells(p, parties),
            ],
          ),
      ];

  List<PicPosTableRow> _paperRows(
    List<CommercialPaperData> papers,
    List<Party> parties,
  ) =>
      [
        for (final p in papers)
          PicPosTableRow(
            cells: _paperCells(p, parties),
          ),
      ];

  /// خلايا الورقة بلا خانةِ الاختيار — يقرؤها الجدولان المفردُ والعاديّ،
  /// فلا يفترق ما يُعرَض في تبويبةٍ عمّا يُعرَض في أخرى.
  List<PicPosCell> _paperCells(CommercialPaperData p, List<Party> parties) => [
        PicPosTextCell(
          p.paperNumber,
          sub: _typeLabels[p.type] ?? p.type,
          icon: p.type == 'promissory_note'
              ? PhosphorIconsBold.scroll
              : PhosphorIconsBold.note,
          tint: _statusLabels[p.status]?.$2 ?? AppColors.primary,
        ),
        PicPosTextCell(_partyName(parties, p.partyId),
            sub: _drawerLabel(
                p, ref.watch(_drawersProvider).value ?? const {})),
        PicPosTextCell(p.bankName ?? '—', sub: p.bankBranch),
        PicPosTextCell(_d(p.issueDate)),
        PicPosTextCell(_d(p.dueDate)),
        PicPosTextCell(p.amount.toStringAsFixed(0)),
        PicPosPillCell(
          _statusLabels[p.status]?.$1 ?? p.status,
          _statusLabels[p.status]?.$2 ?? AppColors.textMuted,
        ),
        _actionCell(p, parties),
      ];

  /// عمودُ «إجراء» — زرٌّ لكلّ صفٍّ **يتبع حالتَه**، كما في التصميم.
  ///
  /// ⚠️ **كلُّ فرعٍ هنا مقيسٌ على نداءٍ يقبله الـDAO**، لا على ما يبدو
  /// منطقيّاً. تحديداً:
  ///
  /// • «إيداع» يمرّ بـ`depositForCollection` ويقبل `pending`/`in_portfolio`
  ///   وحدَهما.
  /// • «إعادة إيداع» للمرتجعة تمرّ بـ`updatePaperStatus(id,'deposited')` —
  ///   لأنّ حارسَ الإيداع يرفض المرتجعةَ دائماً.
  /// • «تجيير» نداءٌ ثالثٌ يحتاج الطرفَ المُجيَّرَ إليه.
  ///
  /// 🔴 والصادرةُ **لا تُودَع**: `depositForCollection` تنقل ورقةً إلى
  /// «تحت التحصيل» عندنا، وهو معنًى لا وجودَ له في ورقةٍ نحن مَن أصدرها.
  /// فعلُها الوحيدُ «تسجيل خصم» حين يخصمها البنك.
  PicPosCell _actionCell(CommercialPaperData p, List<Party> parties) {
    // ⚠️ `hasPermissionProvider` لا `PermissionBuilder`: الأوّلُ يمرّ بـ
    //    `userHasPermission` الذي فيه **تجاوزُ مدير النظام** بنفس استثناء
    //    العمليات الماليّة الحرجة الذي في `PermissionGuard._checkPermission`،
    //    والثاني `contains` نضيفٌ بلا تجاوز. وسجلُّ سبب٠٨٦ يوثّق إخفاءَ
    //    إجراءٍ عن مدير النظام بهذا الخطأ بالضبط.
    //
    //    و`?? false` احتياطاً: قبل أن تُحسَم الصلاحيّةُ لا تُعرَض كتابة.
    final canWrite = ref
            .watch(hasPermissionProvider(PermissionCodes.commercialPapersManage))
            .value ??
        false;

    PicPosCell view() => PicPosButtonCell(
          tr('عرض'),
          icon: PhosphorIconsBold.eye,
          tint: AppColors.textMuted,
          onPressed: () => _showHistoryOf(p.id),
        );

    // القراءةُ متاحةٌ دائماً؛ والكتابةُ وحدَها خلفَ الصلاحيّة.
    if (!canWrite) return view();

    if (p.status == 'bounced') {
      return PicPosButtonCell(
        tr('إعادة إيداع'),
        icon: PhosphorIconsBold.arrowClockwise,
        tint: AppColors.warning,
        onPressed: () => _redeposit(p),
      );
    }

    if (_isDeposited(p.status) || p.status == 'partial_collected') {
      return PicPosButtonCell(
        p.direction == 'issued' ? tr('تسجيل خصم') : tr('تحصيل'),
        icon: p.direction == 'issued'
            ? PhosphorIconsBold.bank
            : PhosphorIconsBold.checkCircle,
        tint: AppColors.success,
        onPressed: () => _markCashed(p),
      );
    }

    if (_canDeposit(p.status)) {
      // الصادرةُ لا تُودَع — تُخصَم. راجع تعليقَ الرأس.
      if (p.direction == 'issued') {
        return PicPosButtonCell(
          tr('تسجيل خصم'),
          icon: PhosphorIconsBold.bank,
          tint: AppColors.primary,
          onPressed: () => _markCashed(p),
        );
      }
      // كمبيالةٌ بلا بنك: التصميمُ يعطيها «تجيير» لا «إيداع» — وهو الصحيح،
      // فالإيداعُ البنكيُّ لورقةٍ لا بنكَ لها بلا معنى.
      if (p.type == 'promissory_note') {
        return PicPosButtonCell(
          tr('تجيير'),
          icon: PhosphorIconsBold.arrowBendUpLeft,
          tint: const Color(0xFF8B5CF6),
          onPressed: () => _endorse(p, parties),
        );
      }
      return PicPosButtonCell(
        tr('إيداع'),
        icon: PhosphorIconsBold.vault,
        tint: AppColors.primary,
        onPressed: () => _depositBatch(
          ref.read(_papersProvider).value ?? const [],
          parties,
          only: p.id,
        ),
      );
    }

    // محصَّلةٌ · مظهَّرةٌ · ملغاةٌ — لا انتقالَ بعدها، فالفعلُ عرضٌ.
    return view();
  }

  /// «عرض» — ينقل إلى تبويبة «سجل الحالات» على هذه الورقة.
  ///
  /// السجلُّ يقرأ **ورقةً واحدةً** (`watchPaperHistory` تأخذ معرِّفاً)، فهذا
  /// هو أقربُ ما في الشاشة إلى عرضِ ورقةٍ بعينها.
  void _showHistoryOf(int paperId) {
    setState(() => _historyPaperId = paperId);
    _tabs.animateTo(4);
  }

  int? get _userId => ref.read(authProvider).user?.id;

  /// يلفّ كتابةً ماليّةً برسالةِ نجاحٍ أو فشلٍ ويُبطل مزوِّدَ الأوراق.
  ///
  /// ⚠️ **الفشلُ يُقال ولا يُبتلَع**: حرّاسُ الـDAO تُلقي بنصٍّ عربيٍّ مفيد
  /// («يجب أن تكون الورقة معلقة أو في الحافظة»)، وابتلاعُه يترك المشغّلَ
  /// يضغط زرّاً ولا يرى شيئاً.
  Future<void> _write(Future<void> Function() body, String done) async {
    try {
      await body();
      if (!mounted) return;
      ref.invalidate(_papersProvider);
      _snack(done);
    } catch (e) {
      if (!mounted) return;
      _snack(tr('تعذّر التنفيذ: {e}', {'e': e}));
    }
  }

  Future<void> _redeposit(CommercialPaperData p) => _write(
        () => redepositBouncedPaper(
          repo: ref.read(commercialPapersRepositoryProvider),
          paperId: p.id,
          changedBy: _userId,
        ),
        tr('أُعيد إيداعُ {p0}', {'p0': p.paperNumber}),
      );

  Future<void> _markCashed(CommercialPaperData p) => _write(
        () => markPaperCashed(
          repo: ref.read(commercialPapersRepositoryProvider),
          paperId: p.id,
          changedBy: _userId,
        ),
        p.direction == 'issued'
            ? tr('سُجّل خصمُ {p0}', {'p0': p.paperNumber})
            : tr('حُصّلت {p0}', {'p0': p.paperNumber}),
      );

  Future<void> _endorse(CommercialPaperData p, List<Party> parties) async {
    // المُجيَّرُ إليه **غيرُ** الطرف الأصليّ — تجييرُ ورقةٍ لصاحبها بلا معنى.
    final targets = [
      for (final q in parties.where((q) => q.id != p.partyId))
        (id: q.id, name: q.name),
    ];

    final form = await showChequesPicposEndorseDialog(
      context,
      paperNumber: p.paperNumber,
      paperTypeLabel: _typeLabels[p.type] ?? p.type,
      fromPartyName: _partyName(parties, p.partyId),
      amount: p.amount,
      dueDate: p.dueDate,
      parties: targets,
    );
    if (form == null || !mounted) return;

    await _write(
      () => endorsePaperTo(
        repo: ref.read(commercialPapersRepositoryProvider),
        paperId: p.id,
        toPartyId: form.toPartyId,
        changedBy: _userId,
        notes: form.notes.isEmpty ? null : form.notes,
      ),
      tr('جُيّرت {p0}', {'p0': p.paperNumber}),
    );
  }

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
      (tr('الكل'), (p) => true),
      (tr('بالخزنة'), (p) => p.status == 'pending'),
      (tr('مودعة'), (p) => _isDeposited(p.status)),
      (tr('محصَّلة'), (p) => p.status == 'cashed'),
      (tr('مرتجعة'), (p) => p.status == 'bounced'),
    ];
    final pick = _chip[tabIndex] ?? 0;
    final shown = papers
        .where((p) =>
            chipDefs[pick].$2(p) &&
            // مرشِّحُ النوع — قرارُ المالك: الكمبيالةُ وسندُ السحب يُعزَلان.
            (_typeFilter == 'all' || p.type == _typeFilter) &&
            (_hit(p.paperNumber) || _hit(_partyName(parties, p.partyId))))
        .toList();

    // ⚠️ **الاختيارُ يُقرأ من المعروض لا من الذاكرة**: ورقةٌ اختيرت ثمّ
    //    أخفاها ترشيحٌ أو تغيّرت حالتُها تترك شريطَ إجراءاتٍ يعمل على ما لا
    //    يُرى — وهو أسوأُ من زرٍّ لا يفعل.
    final selected =
        shown.where((p) => p.id == _selectedPaperId).firstOrNull;

    final week = DateTime.now().add(const Duration(days: 7));
    final dueSoon = papers
        .where((p) =>
            (p.status == 'pending' || _isDeposited(p.status)) &&
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
              label: tr('عددُ الأوراق'),
              value: '${papers.length}',
              tint: AppColors.primary,
              vs: tr('{count} بالخزنة', {
                'count': papers.where((p) => p.status == 'pending').length,
              }),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.currencyCircleDollar,
              label: tr('قيمتها'),
              value: _sum(papers).toStringAsFixed(0),
              tint: AppColors.success,
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.vault,
              label: tr('مودعة بالبنك'),
              value:
                  '${papers.where((p) => _isDeposited(p.status)).length}',
              tint: const Color(0xFF4A80E8),
              vs: _sum(papers.where((p) => _isDeposited(p.status)).toList())
                  .toStringAsFixed(0),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.hourglass,
              label: tr('تستحقّ خلال أسبوع'),
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
          emptyLabel: tr('لا أوراقَ مطابقة'),
          columns: _selectableCols,
          chips: [
            for (var i = 0; i < chipDefs.length; i++)
              PicPosTableChip(
                label: chipDefs[i].$1,
                count: '${papers.where(chipDefs[i].$2).length}',
                onTap: () => setState(() {
                  _chip[tabIndex] = i;
                  _selectedPaperId = null;
                }),
              ),
          ],
          selectedChip: pick,
          rows: _selectableRows(shown, parties),
          // ⚠️ طولُها = عددُ الأعمدة. وخانةُ الاختيار عمودٌ تاسعٌ، فإسقاطُ
          //    خانتِها هنا يُزيح الإجماليَّ عموداً كاملاً تحت «الاستحقاق».
          totals: [
            '',
            tr('{p0} ورقة', {'p0': shown.length}),
            '',
            '',
            '',
            '',
            _sum(shown).toStringAsFixed(0),
            '',
            '',
          ],
        ),
        if (selected != null) ...[
          const SizedBox(height: 10),
          _SelectionBar(
            paper: selected,
            canDeposit: _canDeposit(selected.status),
            onDeposit: () => _depositBatch(papers, parties, only: selected.id),
            onOpenVoucher: () => ref
                .read(screenNavigationProvider.notifier)
                .open(ScreenId.treasury.navigationIndex),
          ),
        ],
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
        .where((p) => p.status == 'pending' || _isDeposited(p.status))
        .where((p) =>
            _hit(p.paperNumber) || _hit(_partyName(parties, p.partyId)))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    // 🔴 **التأخّرُ يُقاس باليوم لا باللحظة.**
    //
    // كان الشرطُ `dueDate.isBefore(DateTime.now())`. و`dueDate` يُخزَّن عند
    // منتصف الليل (منتقي التاريخ يعيد يوماً بلا وقت)، فورقةٌ مستحقّةٌ **اليومَ**
    // تصير «قبل الآن» بعد أوّل دقيقةٍ من اليوم — فتُعَدّ متأخّرةً طوالَ يومِ
    // استحقاقها. والبنكُ يقبلها في ذلك اليوم.
    //
    // فالمقارنةُ على **بداية اليوم**: المستحقُّ اليومَ ليس متأخّراً، والمستحقُّ
    // أمسِ متأخّر.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final overdue = open.where((p) => p.dueDate.isBefore(today)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: PhosphorIconsBold.calendarCheck,
              label: tr('أوراقٌ مفتوحة'),
              value: '${open.length}',
              tint: AppColors.primary,
              vs: _sum(open).toStringAsFixed(0),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.warningOctagon,
              label: tr('تجاوزت الاستحقاق'),
              value: '${overdue.length}',
              tint: AppColors.error,
              up: false,
              vs: _sum(overdue).toStringAsFixed(0),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PicPosDataTable(
          title: tr('جدول الاستحقاق'),
          subtitle: tr('الاستحقاق يُحسب من dueDate لا من تاريخ الإصدار'),
          emptyLabel: tr('لا أوراقَ مفتوحة'),
          columns:  [
            PicPosTableColumn(tr('رقم الورقة'), flex: 1.3),
            PicPosTableColumn(tr('الطرف'), flex: 1.7),
            PicPosTableColumn(tr('الاتّجاه'), flex: 1.1),
            PicPosTableColumn(tr('الاستحقاق'), flex: 1.3),
            PicPosTableColumn(tr('المبلغ'), flex: 1.2,
                align: PicPosCellAlign.end),
            PicPosTableColumn(tr('الحالة'), flex: 1.2),
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
                    p.direction == 'received' ? tr('وارد') : tr('صادر'),
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
                    // نفسُ حدِّ بطاقة المؤشّر أعلاه — `today` لا `now`. ولو
                    // افترقا لقالت البطاقةُ عدداً والجدولُ تحتها آخر.
                    sub: p.dueDate.isBefore(today) ? tr('متأخّرة عن موعدها') : null,
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
            tr('{p0} ورقة', {'p0': open.length}),
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
              label: tr('أوراقٌ مرتجعة'),
              value: '${bounced.length}',
              tint: AppColors.error,
              up: false,
              vs: _sum(bounced).toStringAsFixed(0),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PicPosDataTable(
          title: tr('الأوراق المرتجعة'),
          subtitle: tr('الارتجاع يعيد الذمة ويسجّل مصروف عمولة'),
          emptyLabel: tr('لا أوراقَ مرتجعة'),
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
      return _empty(context, tr('لا أوراقَ بعد — سجلُّ الحالات يظهر بعد أوّل ورقة'));
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
          title: tr('سجل الحالات'),
          subtitle: paper == null
              ? null
              : tr('الورقةُ المعروضة: {p0}', {'p0': paper.paperNumber}),
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
          title: tr('انتقالات الحالة'),
          subtitle: tr('كل انتقال حالة يُسجَّل بمن نفّذه — لا يُحذف'),
          emptyLabel: tr('لا انتقالاتٍ مسجَّلةٍ لهذه الورقة'),
          columns:  [
            PicPosTableColumn(tr('من'), flex: 1.2),
            PicPosTableColumn(tr('إلى'), flex: 1.2),
            PicPosTableColumn(tr('التاريخ'), flex: 1.4),
            PicPosTableColumn(tr('ملاحظات'), flex: 2.2),
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

/// شريطُ الورقة المختارة — الشيكُ وسندُه وفعلاه، كما يرسمه التصميم تحت
/// الجدول.
///
/// ═══ 🔴 «سند القبض» — ولماذا قد يقول «—» ═══
///
/// السندُ يُقرأ من `commercial_papers.sourceVoucherId`، وهو عمودٌ مشحونٌ منذ
/// v174 **كان بلا كاتبٍ ولا قارئ**. وقياسُ المسار وجد أنّ سندَ القبض بشيكٍ
/// **لم يكن يُكتَب أصلاً** (‏مواصفة ١٣٣: `skipSafeTransaction`)، فالرابطُ
/// الوحيدُ كان نصّاً عربيّاً حرّاً في `notes` يحمل رقماً يولّده الحوارُ في
/// ذاكرته ولا يُخزَّن قطّ.
///
/// فيُعرَض «—» في ثلاث حالاتٍ **كلُّها حقيقيّةٌ لا أعطاب**:
///   ‏١) ورقةٌ أُنشئت يدويّاً من هذه الشاشة — لا سندَ لها أصلاً؛
///   ‏٢) ورقةٌ أقدمُ من العمود؛
///   ‏٣) وفي وضع العميل: الكتابةُ على الخادم فلا معرّفَ محلّيّ.
///
/// ⚠️ **وزرُّ «عرض السند» يتبع وجودَ السند** لا وجودَ الورقة: زرٌّ يُعرَض
/// ولا يقفز أسوأُ من غيابه.
class _SelectionBar extends ConsumerWidget {
  const _SelectionBar({
    required this.paper,
    required this.canDeposit,
    required this.onDeposit,
    required this.onOpenVoucher,
  });

  final CommercialPaperData paper;
  final bool canDeposit;
  final VoidCallback onDeposit;
  final VoidCallback onOpenVoucher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final voucherId = paper.sourceVoucherId;
    final drawer =
        _drawerLabel(paper, ref.watch(_drawersProvider).value ?? const {});

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(tr('الشيك'),
              style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
          const SizedBox(width: 8),
          Text(paper.paperNumber,
              style: text.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(width: 18),
          Container(width: 1, height: 22, color: context.picposHairline),
          const SizedBox(width: 18),
          Text(
            paper.direction == 'issued' ? tr('سند الصرف') : tr('سند القبض'),
            style: text.labelSmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(width: 8),
          if (voucherId == null)
            Text('—',
                style: text.labelLarge?.copyWith(color: AppColors.textMuted))
          else
            FutureBuilder<String?>(
              future: ref
                  .read(treasuryRepositoryProvider)
                  .getVoucherNumberById(voucherId),
              builder: (context, snap) => Text(
                snap.data ?? '—',
                style: text.labelLarge?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          // E-fix ٢ — ساحبُ الشيك / مستفيدُه من عموده (v186).
          if (drawer != null) ...[
            const SizedBox(width: 18),
            Container(width: 1, height: 22, color: context.picposHairline),
            const SizedBox(width: 18),
            Flexible(
              child: Text(
                drawer,
                key: const Key('cheque_selection_drawer'),
                overflow: TextOverflow.ellipsis,
                style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
          const Spacer(),
          if (canDeposit)
            FilledButton.icon(
              onPressed: onDeposit,
              icon: const Icon(PhosphorIconsBold.vault, size: 15),
              label:  Text(tr('إيداع للتحصيل')),
            ),
          if (voucherId != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onOpenVoucher,
              icon: const Icon(PhosphorIconsBold.arrowSquareOut, size: 15),
              label:  Text(tr('عرض السند')),
            ),
          ],
        ],
      ),
    );
  }
}
