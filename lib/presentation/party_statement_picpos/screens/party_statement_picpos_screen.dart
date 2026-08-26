// كشفُ حساب العميل والمورد على هويّة PicPos.
//
// المصدر: «PicPos Customer Statement.dc.html» (١٤٨٢ سطراً) و«PicPos Supplier
// Statement.dc.html» (١٤٣٧ سطراً) — **تصميمان مستقلّان لا نسختان**: قِيس
// الفرقُ ٤٩٣ سطرَ diff، وتبويباتُهما تلتقي في ثلاثٍ وتفترق في اثنتين.
//
// ═══ لماذا شاشةٌ مخصّصةٌ لا فوركٌ ولا عارضٌ عامّ ═══
//
// `PartyStatementScreen` القائمةُ (١٢٢٤ سطراً في ثلاثة ملفّات) شاشةُ **كشفٍ
// واحدٍ** بلا تبويبات: تبويبةُ «الحركة والرصيد» وحدَها تقابلها، والأربعُ
// الباقياتُ لا وجودَ لهنّ فيها. ففوركُها كان سيحمل تخطيطَ UralCash كلَّه
// ليُحذَف بعدَ سطر.
//
// و`ReportViewPicposScreen` عارضٌ **بلا أفعالٍ ولا منتقي طرفٍ ولا لوحةِ
// حالات**، ويخدم سبعةَ تقاريرَ أخرى. فلَيُّه لكشفَين كان سيجعل كلَّ تعديلٍ
// لاحقٍ لهما يمسّ السبعة.
//
// وهي تستعمل لبناتِ `picpos_shell` نفسَها التي يستعملها العارض، فلا انحرافَ
// بصريّاً — الاختلافُ في التركيب لا في الشكل.
//
// ═══ القاعدةُ الحاكمة ═══
//
// ⚠️ **كلُّ رقمٍ هنا من استعلام.** التصميمُ يكتب أرقامَه نصّاً لأنّه صورة
// («٤٤,٢٠٠» و«٣٤ يوماً» و«٨٦٪»). ونقلُها كما هي كان سيُنتج كشفاً يبدو حيّاً
// ويكذب — وذلك أسوأُ من خانةٍ فارغةٍ تقول صراحةً إنّها بلا بيانة.
//
// ⚠️ **وما اختلف عن التصميم مذكورٌ بسببه** في تعليقٍ فوقَ موضعه.
//
// ⚠️ **وأزرارُ الصفوف محذوفةٌ لا معطَّلة** (أمرُ المالك 2026-08-26): التصميمُ
// يضع «تحصيل» و«سداد» و«مطالبة» في عمودِ إجراءٍ أخير، وهي أفعالٌ ماليّةٌ
// تكتب في الخزنة والذمّة ولم تُبنَ في هذه الجولة. وزرٌّ يظهر ولا يفعل أسوأُ
// من زرٍّ غائب — فحُذف العمودُ كلُّه من الجداول الأربعة، وبقي التصديرُ
// والطباعةُ وهما فعلان لهما كودٌ عاملٌ يُنقَل.
import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show Uint8List, ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:excel/excel.dart' hide Border;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_utils.dart' show fileUtils;
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
// `IPartiesRepository` لا يعبر عبر `providers.dart`: هو يُصدِّر **مزوِّداتِ**
// المستودعات لا **واجهاتِها**. والاستيرادُ من `domain/` مشروعٌ — الممنوعُ
// على طبقة العرض هو `data/database` وحدَه (حارسُ D4-001).
import '../../../domain/repositories/parties_repository.dart';
// `StatementItem` و`DocumentCompanyHeader` يصلان عبر هذا الاستيراد نفسِه.
import '../../../services/invoice_generator.dart';
import '../../picpos_shell/picpos_bar_list.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_hub_kpi.dart';
import '../../picpos_shell/picpos_report_bar.dart';
import '../../picpos_shell/picpos_report_tabs.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_status_board.dart';
import '../../picpos_shell/picpos_surface.dart';
// حوارا الخزينة القائمان — «تحصيل» و«سداد» في التصميم. يُعادان استعمالاً لا
// نسخاً: هما مسارُ المال الوحيدُ الذي يكتب في الخزنة والذمّة والقيد.
import '../../treasury/widgets/payment_voucher_dialog.dart';
import '../../treasury/widgets/receipt_voucher_dialog.dart';

part 'party_statement_tabs_picpos.dart';
part 'party_statement_export_picpos.dart';

/// تبويبةٌ واحدة — تعريفٌ خالصٌ بلا حالة.
typedef _StatementTab = ({
  String id,
  String label,
  IconData icon,
  String note,
});

/// محتوى تبويبةٍ بعد التحميل.
///
/// **قائمةُ لبناتٍ مرتّبةٌ** لا خاناتٌ مسمّاة: التصميمُ يضع الرسمَ **فوقَ**
/// الجدول في تبويبةٍ و**تحته** في أخرى (‏«أعمار الدين» مقابلَ «المستحق
/// والاستحقاق»)، فخاناتٌ ثابتةٌ كانت ستفرض ترتيباً واحداً على الاثنتين.
class _TabData {
  const _TabData({this.blocks = const [], this.badge});

  final List<Widget> blocks;

  /// شارةُ العدد على رأس التبويبة — **مقيسةٌ من الصفوف المحمَّلة** لا مكتوبة،
  /// فلا تظهر قبل التحميل.
  final String? badge;

  bool get isEmpty => blocks.isEmpty;
}

class PartyStatementPicposScreen extends ConsumerStatefulWidget {
  const PartyStatementPicposScreen({
    super.key,
    this.partyId,
    this.partyName = '',
    this.isSupplier = false,
  });

  final int? partyId;
  final String partyName;

  /// `true` ⇒ كشفُ مورد. والشاشتان تختلفان في تبويبتين ومؤشّراتٍ وجداول.
  final bool isSupplier;

  @override
  ConsumerState<PartyStatementPicposScreen> createState() =>
      _PartyStatementPicposScreenState();
}

class _PartyStatementPicposScreenState
    extends ConsumerState<PartyStatementPicposScreen>
    with
        SingleTickerProviderStateMixin,
        _StatementTabsMixin,
        _StatementExportMixin {
  late final TabController _tabs;
  late DateTimeRange _range;

  int? _partyId;
  Party? _party;
  List<Party> _parties = const [];
  bool _loadingParties = true;

  /// نتائجُ التحميل بمفتاحِ «التبويبة|الطرف|المدى» — بلا ذلك يُعاد الاستعلامُ
  /// مع كلّ إعادةِ بناء، وإعادةُ البناء تقع مع كلّ تبديلِ تبويبةٍ في
  /// `TabBarView`.
  final Map<String, Future<_TabData>> _futures = {};

  /// آخرُ محتوىً محمَّلٍ لكلّ تبويبة — مصدرُ الشارة وحدَه.
  final Map<String, _TabData> _loaded = {};

  final DateFormat _df = DateFormat('yyyy/MM/dd');

  final TextEditingController _searchCtrl = TextEditingController();

  /// نصُّ البحث — `HEADS.hint` في التصميم: «ابحث بمستند أو مبلغ داخل الكشف».
  ///
  /// ⚠️ **مُبلِّغٌ لا حقلُ حالة**، لأنّ لبناتِ التبويبة تُبنى داخلَ دالّةِ
  /// التحميل غيرِ المتزامنة وتُخزَّن في `_futures`. فقيمةٌ تُمرَّر وقتَ البناء
  /// تتجمّد عند لحظة التحميل ولا تتحرّك بعدها، و`setState` لا يُعيد بناءَها
  /// لأنّ المستقبلَ مخزَّن. والمُبلِّغُ ثابتٌ عبر عمر الشاشة فتسمعه اللبناتُ
  /// مهما قَدُم بناؤها.
  ///
  /// ⚠️ **والبحثُ لا يُعيد الاستعلام**: يُرشِّح المحمَّلَ في الذاكرة. فمفتاحُ
  /// `_futures` لا يحمله، وكتابةُ حرفٍ لا تضرب القاعدة.
  final ValueNotifier<String> _queryVN = ValueNotifier<String>('');

  @override
  ValueListenable<String> get query => _queryVN;

  @override
  bool get isSupplier => widget.isSupplier;

  @override
  int? get partyId => _partyId;

  @override
  Party? get party => _party;

  @override
  DateTimeRange get range => _range;

  @override
  DateFormat get df => _df;

  @override
  void initState() {
    super.initState();
    _partyId = widget.partyId;
    _tabs = TabController(length: _tabDefs.length, vsync: this);
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
    unawaited(_loadShell());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    _queryVN.dispose();
    super.dispose();
  }

  List<_StatementTab> get _tabDefs =>
      widget.isSupplier ? _supplierTabs : _customerTabs;

  String get _rangeKey =>
      '${_range.start.millisecondsSinceEpoch}-${_range.end.millisecondsSinceEpoch}';

  Future<_TabData> _future(_StatementTab tab) {
    final key = '${tab.id}|$_partyId|$_rangeKey';
    return _futures.putIfAbsent(key, () => loadTab(tab.id));
  }

  /// قائمةُ الأطراف للمنتقي، ثمّ بيانةُ الطرف المختار.
  ///
  /// ⚠️ **محصورةٌ بنطاق الفروع.** `watchAllParties()` غيرُ المحصورة كانت
  /// تعرض كلَّ عملاء الشركة وموردِيها — بالأسماء والأرصدة — لمستخدمٍ محصورٍ
  /// بفرع. والعقدُ: `null` = وصولٌ كاملٌ بلا حصر، `{ids}` = هذه الفروعُ
  /// والأطرافُ العامّة، `{}` = لا شيء.
  Future<void> _loadShell() async {
    try {
      final repo = ref.read(partiesRepositoryProvider);
      final scope = await ref.read(branchScopeProvider.future);
      final all =
          await repo.watchAllPartiesForBranches(scope.allowedBranchIds).first;
      final filtered = all
          .where((p) => widget.isSupplier ? p.isSupplier : p.isCustomer)
          .toList();

      Party? selected;
      if (_partyId != null) {
        selected = await repo.getPartyById(_partyId!);
        if (selected == null) {
          // العطبُ الميدانيُّ الذي بلّغ عنه المالكُ قبلاً: الترويسةُ تتحدّث
          // والجسمُ يبقى فارغاً بلا رسالة. تُسجَّل الحالةُ ويُعرَض نائبٌ صريح.
          unawaited(DiagnosticLogger.log(
            'PARTY-STATEMENT-PICPOS',
            '⚠ getPartyById عاد بـnull لـpartyId=$_partyId',
          ));
        }
      }

      if (!mounted) return;
      setState(() {
        _parties = filtered;
        _party = selected;
        _loadingParties = false;
      });
    } catch (e) {
      unawaited(DiagnosticLogger.log(
        'PARTY-STATEMENT-PICPOS',
        '❌ تعذّر تحميلُ قائمة الأطراف: $e',
      ));
      if (mounted) setState(() => _loadingParties = false);
    }
  }

  void _onRangeChanged(DateTime start, DateTime end) {
    setState(() {
      _range = DateTimeRange(start: start, end: end);
      // المفاتيحُ تحمل المدى فلا تُصفَّر الخريطة — لكنّ الشاراتِ المعروضةَ
      // صارت من مدىً آخر، وشارةٌ من مدىً سابقٍ رقمٌ يكذب.
      _loaded.clear();
    });
  }

  Future<void> _pickParty() async {
    final picked = await showDialog<Party>(
      context: context,
      builder: (_) => _PartyPickerDialog(
        parties: _parties,
        selectedId: _partyId,
        isSupplier: widget.isSupplier,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _partyId = picked.id;
      _party = picked;
      _loaded.clear();
      // مفاتيحُ التحميل تحمل معرِّفَ الطرف، فالخريطةُ لا تُصفَّر — والتبويبةُ
      // المفتوحةُ تُعيد الاستعلامَ وحدَها بمفتاحها الجديد.
    });
  }

  /// بعد سندِ قبضٍ أو صرفٍ: الرصيدُ والذمّةُ تحرّكا، فكلُّ تبويبةٍ محمَّلةٍ
  /// صارت قديمة. والمفتاحُ لا يحمل «حدَثَ فعلٍ»، فتُفرَغ الخريطةُ صراحةً.
  @override
  void reloadTabs() {
    if (!mounted) return;
    setState(() {
      _futures.clear();
      _loaded.clear();
    });
  }

  void _remember(String tabId, _TabData data) {
    if (!mounted) return;
    if (_loaded[tabId]?.badge == data.badge) return;
    // بعد الإطار — الشارةُ تغيّر شريطَ التبويبات وهو يُبنى في نفس الإطار.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _loaded[tabId] = data);
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.isSupplier ? 'مورد' : 'عميل';
    final name = _party?.name ?? widget.partyName;
    final hasParty = _partyId != null && _party != null;

    return PicPosScreenScaffold(
      title: 'كشف حساب $label',
      subtitle: hasParty
          ? '$name · ${_df.format(_range.start)} — ${_df.format(_range.end)}'
          : 'اختر $label لعرض كشف حسابه',
      icon: widget.isSupplier
          ? PhosphorIconsBold.truck
          : PhosphorIconsBold.userList,
      bodyPadding: EdgeInsets.zero,
      headerSearch: hasParty
          ? TextField(
              controller: _searchCtrl,
              onChanged: (v) => _queryVN.value = v,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'ابحث بمستند أو مبلغ داخل الكشف...',
                prefixIcon:
                    const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                suffixIcon: ValueListenableBuilder<String>(
                  valueListenable: _queryVN,
                  builder: (context, q, _) => q.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(PhosphorIconsBold.x, size: 14),
                          tooltip: 'امسح البحث',
                          onPressed: () {
                            _searchCtrl.clear();
                            _queryVN.value = '';
                          },
                        ),
                ),
              ),
            )
          : null,
      headerActions: [
        OutlinedButton.icon(
          onPressed: _loadingParties ? null : _pickParty,
          icon: Icon(
            widget.isSupplier
                ? PhosphorIconsBold.truck
                : PhosphorIconsBold.storefront,
            size: 18,
          ),
          // ⚠️ **اسمُ الطرف مقصوصٌ بسقف.** الحقلُ `name` طولُه ٢٠٠ حرفاً في
          // الجدول، واسمٌ طويلٌ في زرِّ ترويسةٍ يدفع بقيّةَ الأزرار خارجَ
          // الشاشة مهما اتّسعت — عطبٌ لا علاقةَ له بالعرض.
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              hasParty ? name : 'اختر $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor:
                widget.isSupplier ? AppColors.warning : AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: hasParty ? exportToExcel : null,
          icon: const Icon(PhosphorIconsBold.microsoftExcelLogo, size: 18),
          label: const Text('تصدير الكشف'),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.success),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: hasParty ? printStatement : null,
          icon: const Icon(PhosphorIconsBold.printer, size: 18),
          label: const Text('طباعة'),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
        ),
        const SizedBox(width: 8),
      ],
      subHeader: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PicPosReportFilterBar(
            selectedRange: _range,
            onRangeChanged: _onRangeChanged,
            trailing: const [],
          ),
          PicPosReportTabs(
            controller: _tabs,
            tabs: [
              for (final t in _tabDefs)
                (label: t.label, icon: t.icon, badge: _loaded[t.id]?.badge),
            ],
          ),
        ],
      ),
      body: hasParty
          ? TabBarView(
              controller: _tabs,
              children: [
                for (final t in _tabDefs)
                  _TabBody(tab: t, future: _future(t), onLoaded: _remember),
              ],
            )
          : _StatementMessage(
              icon: _loadingParties
                  ? PhosphorIconsBold.hourglass
                  : PhosphorIconsBold.userList,
              text: _loadingParties
                  ? 'جارٍ تحميل قائمة الأطراف…'
                  : (_partyId != null
                      ? 'الطرفُ المطلوب غيرُ موجود'
                      : 'لم يُختَر $label بعد'),
              sub: _loadingParties
                  ? ''
                  : (_partyId != null
                      ? 'قد يكون محذوفاً أو خارجَ نطاق فروعك — اختر طرفاً آخر'
                      : 'اضغط «اختر $label» في الترويسة'),
              tint: AppColors.primary,
            ),
    );
  }
}

/// جسمُ تبويبةٍ واحدة — تحميلٌ ثمّ لبناتٌ مرتّبة.
class _TabBody extends StatelessWidget {
  const _TabBody({
    required this.tab,
    required this.future,
    required this.onLoaded,
  });

  final _StatementTab tab;
  final Future<_TabData> future;
  final void Function(String tabId, _TabData data) onLoaded;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_TabData>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
        }
        if (snap.hasError) {
          // ⚠️ رمْيُ SQL يُبتلَع في بطاقةٍ إن لم يُعرَض — فيبدو التقريرُ
          //    عاملاً وهو ليس كذلك.
          return _StatementMessage(
            icon: PhosphorIconsBold.warningCircle,
            text: 'تعذّر حسابُ هذه التبويبة',
            sub: '${snap.error}',
            tint: Theme.of(context).colorScheme.error,
          );
        }
        final data = snap.data ?? const _TabData();
        onLoaded(tab.id, data);
        if (data.isEmpty) {
          return _StatementMessage(
            icon: PhosphorIconsBold.chartBar,
            text: 'لا بيانات في هذه الفترة',
            sub: 'غيّرِ المدى من الشريط أعلاه',
            tint: context.picposMuted,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tab.note.isNotEmpty)
              PicPosTabNote(note: tab.note, icon: tab.icon),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 18, 26, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < data.blocks.length; i++) ...[
                      if (i > 0) const SizedBox(height: 14),
                      data.blocks[i],
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatementMessage extends StatelessWidget {
  const _StatementMessage({
    required this.icon,
    required this.text,
    required this.sub,
    required this.tint,
  });

  final IconData icon;
  final String text;
  final String sub;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: tint),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: context.picposText,
              ),
            ),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                sub,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.picposMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// منتقي الطرف — بحثٌ بالاسم والكود والهاتف على القائمة المحصورة بالفروع.
class _PartyPickerDialog extends StatefulWidget {
  const _PartyPickerDialog({
    required this.parties,
    required this.selectedId,
    required this.isSupplier,
  });

  final List<Party> parties;
  final int? selectedId;
  final bool isSupplier;

  @override
  State<_PartyPickerDialog> createState() => _PartyPickerDialogState();
}

class _PartyPickerDialogState extends State<_PartyPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final rows = q.isEmpty
        ? widget.parties
        : widget.parties.where((p) {
            return p.name.toLowerCase().contains(q) ||
                (p.code ?? '').toLowerCase().contains(q) ||
                (p.phone ?? '').contains(q);
          }).toList();
    final label = widget.isSupplier ? 'مورد' : 'عميل';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: context.picposCard,
        title: Text(
          'اختر $label',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: context.picposText,
          ),
        ),
        content: SizedBox(
          width: 420,
          height: 440,
          child: Column(
            children: [
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم أو الكود أو الهاتف…',
                  prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass,
                      size: 18),
                  filled: true,
                  fillColor: context.picposField,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11),
                    borderSide: BorderSide(color: context.picposHairline),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(
                          'لا $label يطابق البحث',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: context.picposMuted,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final p = rows[i];
                          final on = p.id == widget.selectedId;
                          return ListTile(
                            dense: true,
                            selected: on,
                            leading: Icon(
                              widget.isSupplier
                                  ? PhosphorIconsBold.truck
                                  : PhosphorIconsBold.storefront,
                              size: 18,
                              color: on
                                  ? AppColors.primary
                                  : context.picposMuted,
                            ),
                            title: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: context.picposText,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if ((p.code ?? '').isNotEmpty) p.code!,
                                if ((p.phone ?? '').isNotEmpty) p.phone!,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: context.picposMuted,
                              ),
                            ),
                            onTap: () => Navigator.pop(context, p),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }
}
