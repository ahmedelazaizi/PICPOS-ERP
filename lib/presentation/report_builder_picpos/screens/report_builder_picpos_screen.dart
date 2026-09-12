// شاشةُ «التقارير المخصّصة» بهويّة PicPos — على تصميم
// `PicPos Custom Reports.dc.html`.
//
// ═══ إعادةُ تنسيقٍ لا بناء ═══
//
// `CustomReports` و`SavedReportRuns` مشحونان، و`report_builder_dao` يحمل
// المحرّكَ كاملاً: سجلَّ الحقول لكلّ كيان (`getAvailableFields`)، وعواملَ
// الفلتر مربوطةً بنوع الحقل (`getFilterOperators`)، وبناءَ الاستعلام وتنفيذَه
// مع حصر الفروع وسقفِ الصفوف. فلا جدولَ جديدَ هنا ولا `build_runner`.
//
// ═══ 🔴 وحارسٌ لزم قبل فتح لوحتَي التجميع والترتيب ═══
//
// `_buildReportQuery` يركّب `GROUP BY` و`ORDER BY` في نصّ الاستعلام
// **حرفيّاً** — ولا سبيلَ لغير ذلك (`GROUP BY ?` ليس SQL صالحاً). ولم يكن
// ذلك مبلوغاً لأنّ `createCustomReport` على المستودع لا تقبل العمودَين
// أصلاً، فهما `null` دائماً.
//
// وهذه الشاشةُ تفتح لوحتَي «تجميع حسب» و«الترتيب» كما في التصميم — أي تصير
// لهما كاتب. فأُضيف في المحرّك تصفيةٌ على **سجلّ الحقول المغلق** قبل أن
// يلمسا SQL، ويُرفَض التقريرُ كلُّه على أوّل حقلٍ مجهول أو اتّجاهٍ غيرِ
// `asc`/`desc`. والواجهةُ لا تكتب فيهما إلّا ما اختاره المستخدمُ من السجلّ
// نفسِه — فالحمايةُ طبقتان لا واحدة.
//
// ═══ ⚠️ وما لم يُنقَل من التصميم ═══
//
// ١) ~~الدوالُّ التجميعيّة~~ — **وُصِلت في §٣‑٤(ب)** (‏2026-08-31). كانت
//    `aggregates` تُحفَظ ولا يقرؤها `_buildReportQuery`، ومعها كان `GROUP BY`
//    يُركَّب فوق أعمدةٍ عاريةٍ فتُرجع SQLite **قيمةَ صفٍّ عشوائيٍّ** من داخل
//    المجموعة يقرؤها المستخدمُ مجموعاً فرعيّاً. صارت تُطبَّق، والرقميُّ بلا
//    دالّةٍ يُجمَع بـ`SUM` (قرارُ مالك) — **عند التجميع وحدَه**.
//
// ٢) **زمنُ التنفيذ وعددُ الصفوف** على بطاقة التقرير المحفوظ: يُقرآن من
//    `SavedReportRuns` لآخر تشغيلٍ فعليّ — لا من رقمٍ مكتوبٍ في التصميم.
//    والبطاقةُ تصمت حتّى يُشغَّل التقريرُ مرّةً.
//
// ٣) **صفوفُ المعاينة في التصميم** ثابتةٌ في `ENTITIES[..].rows`. وهنا
//    المعاينةُ ناتجُ `executeReport` الحقيقيّ، وتبقى فارغةً حتّى يُشغَّل.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/reporting_repository.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_surface.dart';

const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _err = Color(0xFFEF4444);
const _purple = Color(0xFF8B5CF6);
const _idle = Color(0xFF6B7280);

String _ar(Object n) =>
    '$n'.replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)]);

/// الكياناتُ السبعةُ — نفسُ الرموز التي يقبلها `sourceEntity` في المحرّك.
const Map<String, ({String label, IconData icon, Color tint})> _kEntities = {
  'products': (
    label: 'الأصناف',
    icon: PhosphorIconsBold.package,
    tint: AppColors.primary
  ),
  'sales_invoices': (
    label: 'فواتير البيع',
    icon: PhosphorIconsBold.receipt,
    tint: _ok
  ),
  'purchase_invoices': (
    label: 'فواتير الشراء',
    icon: PhosphorIconsBold.truck,
    tint: _purple
  ),
  'parties': (
    label: 'العملاء والموردون',
    icon: PhosphorIconsBold.usersThree,
    tint: _warn
  ),
  'inventory_balances': (
    label: 'أرصدة المخازن',
    icon: PhosphorIconsBold.warehouse,
    tint: AppColors.primary
  ),
  'journal_entries': (
    label: 'القيود المحاسبية',
    icon: PhosphorIconsBold.bookOpen,
    tint: _idle
  ),
  'employees': (
    label: 'الموظفون',
    icon: PhosphorIconsBold.identificationBadge,
    tint: _err
  ),
};

/// الدوالُّ الخمسُ التي يعرضها التصميم.
///
/// ⚠️ تُحفَظ في التعريف ولا تغيّر الناتج — راجع شرحَ الرأس.
const _kFunctions = ['SUM', 'AVG', 'COUNT', 'MIN', 'MAX'];

final _reportsProvider =
    FutureProvider.autoDispose<List<CustomReportData>>((ref) =>
        ref.watch(reportingRepositoryProvider).getCustomReports());

class ReportBuilderPicposScreen extends ConsumerStatefulWidget {
  const ReportBuilderPicposScreen({super.key});

  @override
  ConsumerState<ReportBuilderPicposScreen> createState() =>
      _ReportBuilderPicposScreenState();
}

class _ReportBuilderPicposScreenState
    extends ConsumerState<ReportBuilderPicposScreen> {
  // ── تعريفُ التقرير الجاري بناؤه ──────────────────────────────────────
  String _entity = 'products';
  final _columns = <String>[];
  final _filters = <({String field, String op, String value})>[];
  final _groupBy = <String>[];
  final _aggregates = <String, String>{};
  String? _sortField;
  bool _sortDesc = false;

  int? _selectedReportId;
  List<Map<String, dynamic>> _results = const [];
  bool _running = false;
  String? _truncatedNote;

  List<Map<String, String>> get _fields =>
      ref.read(reportingRepositoryProvider).getAvailableFields(_entity);

  String? _typeOf(String key) {
    for (final f in _fields) {
      if (f['key'] == key) return f['type'];
    }
    return null;
  }

  String _labelOf(String key) {
    for (final f in _fields) {
      if (f['key'] == key) return f['label'] ?? key;
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(_reportsProvider);

    return PicPosScreenScaffold(
      title: 'اعداد وتصميم التقارير',
      subtitle:
          'ابنِ تقريرك باختيار جهة البيانات وأعمدتها وشروطها — ثم شغّله واحفظه',
      icon: PhosphorIconsBold.chartBar,
      headerActions: [
        OutlinedButton.icon(
          onPressed: _columns.isEmpty ? null : _saveReport,
          icon: const Icon(PhosphorIconsBold.floppyDisk, size: 15),
          label: const Text('حفظ التعريف'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _running || _selectedReportId == null
              ? null
              : () => _run(_selectedReportId!),
          icon: const Icon(PhosphorIconsBold.play, size: 15),
          label: const Text('تشغيل'),
        ),
      ],
      bodyPadding: EdgeInsets.zero,
      body: LayoutBuilder(builder: (context, box) {
        // ثلاثةُ أعمدةٍ فوقَ ١٥٠٠ (‏محفوظات + بانٍ + معاينة)، وعمودان دونَه،
        // وواحدٌ متمرّرٌ دونَ ١٠٥٠. والحدودُ مقيسةٌ لا مذوقة: البانِي وحدَه
        // يحتاج ٤٢٠ ليقرأ، والمعاينةُ ٤٨٠.
        final wide = box.maxWidth >= 1500;
        final medium = box.maxWidth >= 1050;

        final saved = _savedPane(reports);
        final builder = _builderPane();
        final preview = _previewPane();

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: saved),
              _divider(),
              SizedBox(width: 420, child: builder),
              _divider(),
              Expanded(child: preview),
            ],
          );
        }
        if (medium) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 380, child: builder),
              _divider(),
              Expanded(child: preview),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            SizedBox(height: 300, child: saved),
            const SizedBox(height: 12),
            builder,
            const SizedBox(height: 12),
            SizedBox(height: 420, child: preview),
          ],
        );
      }),
    );
  }

  Widget _divider() => Container(width: 1, color: context.picposHairline);

  // ═════════════════════════════════════════════════════════════════════════
  // التقاريرُ المحفوظة
  // ═════════════════════════════════════════════════════════════════════════

  Widget _savedPane(AsyncValue<List<CustomReportData>> reports) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: context.picposCard,
            border: Border(bottom: BorderSide(color: context.picposHairline)),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsBold.folders,
                  size: 16, color: context.picposBrandInk),
              const SizedBox(width: 9),
              const Text('التقارير المحفوظة',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        Expanded(
          child: reports.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => PicPosEmptyState(
              icon: PhosphorIconsBold.warningOctagon,
              title: 'تعذّرت قراءةُ التقارير',
              hint: '$e',
            ),
            data: (list) => list.isEmpty
                ? const PicPosEmptyState(
                    icon: PhosphorIconsBold.folders,
                    title: 'لا تقاريرَ محفوظةً بعد',
                    hint: 'ابنِ تقريراً من اللوحة المجاورة ثمّ احفظْ تعريفَه.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: list.length,
                    itemBuilder: (context, i) => _savedCard(list[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _savedCard(CustomReportData r) {
    final meta = _kEntities[r.sourceEntity];
    final on = _selectedReportId == r.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => _loadReport(r),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: on
                ? context.picposBrandInk.withValues(alpha: 0.06)
                : context.picposCard,
            border: Border.all(
                color: on ? context.picposBrandInk : context.picposHairline,
                width: 1.5),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (meta?.tint ?? _idle).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(meta?.icon ?? PhosphorIconsBold.fileText,
                    size: 16, color: meta?.tint ?? _idle),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(r.name,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (r.isShared) ...[
                          const SizedBox(width: 6),
                          Icon(PhosphorIconsBold.users,
                              size: 12, color: context.picposMuted),
                        ],
                      ],
                    ),
                    Text(
                      r.description?.trim().isNotEmpty == true
                          ? r.description!
                          : (meta?.label ?? r.sourceEntity),
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: context.picposMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'حذف',
                icon: const Icon(PhosphorIconsBold.trash, size: 14),
                onPressed: () => _deleteReport(r),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // البانِي
  // ═════════════════════════════════════════════════════════════════════════

  Widget _builderPane() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _entityPanel(),
        const SizedBox(height: 12),
        _columnsPanel(),
        const SizedBox(height: 12),
        _filtersPanel(),
        const SizedBox(height: 12),
        _groupPanel(),
        const SizedBox(height: 12),
        _aggregatesPanel(),
        const SizedBox(height: 12),
        _sortPanel(),
      ],
    );
  }

  Widget _entityPanel() {
    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PicPosSectionHeader(
            title: 'جهة البيانات',
            subtitle: 'تغييرها يمسح الأعمدة والشروط — الحقول تختلف',
            icon: PhosphorIconsBold.database,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _kEntities.entries)
                ChoiceChip(
                  selected: _entity == e.key,
                  avatar: Icon(e.value.icon, size: 14),
                  label: Text(e.value.label),
                  // ⚠️ التبديلُ يمسح كلَّ ما بُني: حقولُ الكيان الجديد غيرُ
                  //    حقول القديم، فإبقاءُ عمودٍ قديمٍ يبني تقريراً يُرفَض
                  //    عند التنفيذ — أو أسوأ، يُنفَّذ على حقلٍ يحمل نفسَ
                  //    الاسم ويعني شيئاً آخر.
                  onSelected: (_) => setState(() {
                    _entity = e.key;
                    _columns.clear();
                    _filters.clear();
                    _groupBy.clear();
                    _aggregates.clear();
                    _sortField = null;
                    _results = const [];
                    _selectedReportId = null;
                    _truncatedNote = null;
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _columnsPanel() {
    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PicPosSectionHeader(
            title: 'الأعمدة',
            subtitle: _columns.isEmpty
                ? 'اختر عموداً واحداً على الأقل'
                : '${_ar(_columns.length)} من ${_ar(_fields.length)}',
            icon: PhosphorIconsBold.columns,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in _fields)
                FilterChip(
                  selected: _columns.contains(f['key']),
                  label: Text(f['label'] ?? f['key']!),
                  onSelected: (on) => setState(() {
                    final key = f['key']!;
                    if (on) {
                      _columns.add(key);
                    } else {
                      _columns.remove(key);
                    }
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filtersPanel() {
    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PicPosSectionHeader(
            title: 'الشروط',
            subtitle: 'العوامل المتاحة تتبع نوع الحقل',
            icon: PhosphorIconsBold.funnel,
            actions: [
              IconButton(
                tooltip: 'شرط جديد',
                icon: const Icon(PhosphorIconsBold.plus, size: 15),
                onPressed: _fields.isEmpty ? null : _addFilter,
              ),
            ],
          ),
          if (_filters.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('بلا شروط — التقرير يقرأ كلَّ الصفوف',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: context.picposMuted)),
            )
          else
            for (var i = 0; i < _filters.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_labelOf(_filters[i].field)} '
                        '${_filters[i].op} ${_filters[i].value}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(PhosphorIconsBold.x, size: 13),
                      onPressed: () => setState(() => _filters.removeAt(i)),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _groupPanel() {
    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PicPosSectionHeader(
            title: 'تجميع حسب',
            subtitle: 'الحقول من سجلّ الكيان وحدَه',
            icon: PhosphorIconsBold.stackSimple,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in _fields)
                FilterChip(
                  selected: _groupBy.contains(f['key']),
                  label: Text(f['label'] ?? f['key']!),
                  onSelected: (on) => setState(() {
                    final key = f['key']!;
                    if (on) {
                      _groupBy.add(key);
                    } else {
                      _groupBy.remove(key);
                    }
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// لوحةُ الدوالّ التجميعيّة.
  ///
  /// ⚠️ **تُحفَظ ولا تغيّر الناتج** — `_buildReportQuery` لا يقرأ عمودَ
  /// `aggregates` ولا يبني `SUM(col)` في `SELECT`. والعنوانُ الفرعيُّ يقول
  /// ذلك للمستخدم بدل أن يظنّ أنّ الرقمَ تغيّر.
  Widget _aggregatesPanel() {
    final numeric =
        _fields.where((f) => f['type'] == 'number').toList();
    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PicPosSectionHeader(
            title: 'الدوال التجميعية',
            // ⚠️ الوسمُ يتبع الحال: صارت تُطبَّق فعلاً، لكن **عند التجميع
            // وحدَه** — بلا «تجميع حسب» لا مجموعاتِ لتُجمَع، فيبقى التقريرُ
            // سرداً للصفوف. والعنوانُ يقول ذلك بدل أن يَعِد بما لا يقع.
            subtitle: _groupBy.isEmpty
                ? 'تُطبَّق عند اختيار «تجميع حسب» — وبدونه سردُ صفوف'
                : 'تُطبَّق على الناتج · والرقميُّ بلا دالّةٍ يُجمَع بـSUM',
            icon: PhosphorIconsBold.sigma,
          ),
          if (numeric.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('لا حقولَ رقميّةً في هذا الكيان',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: context.picposMuted)),
            )
          else
            for (final f in numeric)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(f['label'] ?? f['key']!,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis),
                    ),
                    DropdownButton<String?>(
                      value: _aggregates[f['key']],
                      hint: const Text('—', style: TextStyle(fontSize: 12)),
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('—')),
                        for (final fn in _kFunctions)
                          DropdownMenuItem<String?>(
                              value: fn, child: Text(fn)),
                      ],
                      onChanged: (v) => setState(() {
                        if (v == null) {
                          _aggregates.remove(f['key']);
                        } else {
                          _aggregates[f['key']!] = v;
                        }
                      }),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _sortPanel() {
    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PicPosSectionHeader(
            title: 'الترتيب',
            icon: PhosphorIconsBold.sortAscending,
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButton<String?>(
                  value: _sortField,
                  isExpanded: true,
                  hint: const Text('بلا ترتيب',
                      style: TextStyle(fontSize: 12)),
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('بلا ترتيب')),
                    for (final f in _fields)
                      DropdownMenuItem<String?>(
                          value: f['key'], child: Text(f['label'] ?? f['key']!)),
                  ],
                  onChanged: (v) => setState(() => _sortField = v),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('تصاعدي')),
                  ButtonSegment(value: true, label: Text('تنازلي')),
                ],
                selected: {_sortDesc},
                onSelectionChanged: _sortField == null
                    ? null
                    : (s) => setState(() => _sortDesc = s.first),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // المعاينة
  // ═════════════════════════════════════════════════════════════════════════

  Widget _previewPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: context.picposCard,
            border: Border(bottom: BorderSide(color: context.picposHairline)),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsBold.table,
                  size: 16, color: context.picposBrandInk),
              const SizedBox(width: 9),
              const Text('المعاينة',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _results.isEmpty
                      ? 'شغّلْ تقريراً محفوظاً لترى نتيجته'
                      : '${_ar(_results.length)} صفّاً',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.picposMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // 🔴 الاقتطاعُ يُقال صراحةً: قارئُ تقريرٍ مقتطعٍ يجمع أعمدتَه ويظنّها
        //    كاملة. والـDAO يبلّغ عبر `onRowLimitReached`، فيُعرَض هنا.
        if (_truncatedNote != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            color: _warn.withValues(alpha: 0.12),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.warning, size: 15, color: _warn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_truncatedNote!,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _warn)),
                ),
              ],
            ),
          ),
        Expanded(
          child: _running
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty
                  ? const PicPosEmptyState(
                      icon: PhosphorIconsBold.table,
                      title: 'لا نتيجةَ بعد',
                      hint: 'اختر تقريراً محفوظاً من القائمة ثمّ اضغط «تشغيل» '
                          '— أو ابنِ تعريفاً جديداً واحفظْه أوّلاً.',
                    )
                  : _resultTable(),
        ),
      ],
    );
  }

  Widget _resultTable() {
    final keys = _results.first.keys.toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: PicPosDataTable(
        title: 'نتيجة التشغيل',
        subtitle: 'مقروءةٌ من المحرّك — لا صفوفَ نموذجيّة',
        minWidth: 120.0 * keys.length + 60,
        columns: [
          for (final k in keys) PicPosTableColumn(_labelOf(k), flex: 1.2),
        ],
        rows: [
          for (final row in _results)
            PicPosTableRow(cells: [
              for (final k in keys) PicPosTextCell('${row[k] ?? '—'}'),
            ]),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // الأفعال
  // ═════════════════════════════════════════════════════════════════════════

  void _loadReport(CustomReportData r) {
    setState(() {
      _selectedReportId = r.id;
      _entity = r.sourceEntity;
      _columns
        ..clear()
        ..addAll(r.columns.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty));
      _groupBy
        ..clear()
        ..addAll((r.groupBy ?? '')
            .split(',')
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty));
      _results = const [];
      _truncatedNote = null;
    });
  }

  Future<void> _addFilter() async {
    final repo = ref.read(reportingRepositoryProvider);
    var field = _fields.first['key']!;
    // `getFilterOperators` تعيد `{op, label}` — الرمزُ للمحرّك والتسميةُ
    // للمستخدم. والمحفوظُ هو الرمزُ وحدَه.
    var op = repo.getFilterOperators(_typeOf(field) ?? 'text').first['op']!;
    final valueCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          // ⚠️ العواملُ تُقرأ لنوع الحقل المختار **في كلّ إعادة بناء**: قائمةٌ
          //    مغلقةٌ في المحرّك، فلا يُعرَض عاملٌ سيُرفض عند التنفيذ.
          final ops = repo.getFilterOperators(_typeOf(field) ?? 'text');
          // تبديلُ الحقل قد يُسقط العاملَ المختار (‏«يحتوي» لا يصلح لرقم)،
          // فيُعاد لأوّل عاملٍ مسموحٍ بدل أن يبقى مختاراً ثمّ يُرفض.
          if (!ops.any((o) => o['op'] == op)) op = ops.first['op']!;
          return AlertDialog(
            title: const Text('شرط جديد'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: field,
                    decoration: const InputDecoration(labelText: 'الحقل'),
                    items: [
                      for (final f in _fields)
                        DropdownMenuItem(
                            value: f['key'], child: Text(f['label'] ?? f['key']!)),
                    ],
                    onChanged: (v) => setDialog(() => field = v ?? field),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: op,
                    decoration: const InputDecoration(labelText: 'العامل'),
                    items: [
                      for (final o in ops)
                        DropdownMenuItem(
                            value: o['op'], child: Text(o['label']!)),
                    ],
                    onChanged: (v) => setDialog(() => op = v ?? op),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valueCtrl,
                    decoration: const InputDecoration(labelText: 'القيمة'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('إضافة')),
            ],
          );
        },
      ),
    );

    final value = valueCtrl.text.trim();
    valueCtrl.dispose();
    if (ok != true || value.isEmpty || !mounted) return;
    setState(() => _filters.add((field: field, op: op, value: value)));
  }

  Future<void> _saveReport() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var shared = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('حفظ تعريف التقرير'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'اسم التقرير'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'الوصف'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: shared,
                  onChanged: (v) => setDialog(() => shared = v),
                  title: const Text('مشترك مع بقية المستخدمين'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حفظ')),
          ],
        ),
      ),
    );

    final name = nameCtrl.text.trim();
    final desc = descCtrl.text.trim();
    nameCtrl.dispose();
    descCtrl.dispose();
    if (ok != true || !mounted) return;
    if (name.isEmpty) {
      _toast('اسمُ التقرير مطلوب');
      return;
    }

    try {
      await ref.read(reportingRepositoryProvider).createCustomReport(
            name: name,
            sourceEntity: _entity,
            columns: _columns.join(','),
            description: desc.isEmpty ? null : desc,
            filters: _filters.isEmpty
                ? null
                : jsonEncode([
                    for (final f in _filters)
                      {'field': f.field, 'op': f.op, 'value': f.value}
                  ]),
            groupBy: _groupBy.isEmpty ? null : _groupBy.join(','),
            sortBy: _sortField == null
                ? null
                : '$_sortField ${_sortDesc ? 'desc' : 'asc'}',
            aggregates:
                _aggregates.isEmpty ? null : jsonEncode(_aggregates),
            isShared: shared,
          );
      if (!mounted) return;
      ref.invalidate(_reportsProvider);
      _toast('حُفظ تعريفُ «$name»');
    } catch (e) {
      if (!mounted) return;
      _toast('تعذّر الحفظ: $e');
    }
  }

  Future<void> _run(int reportId) async {
    setState(() {
      _running = true;
      _truncatedNote = null;
    });
    try {
      final rows =
          await ref.read(reportingRepositoryProvider).executeReport(
                reportId,
                onRowLimitReached: (limit) {
                  _truncatedNote = 'الناتجُ مقتطعٌ عند ${_ar(limit)} صفّاً — '
                      'ضيِّقِ الشروطَ فالمجاميعُ أدناه ناقصة.';
                },
              );
      if (!mounted) return;
      setState(() {
        _results = rows;
        _running = false;
      });
      if (rows.isEmpty) _toast('لا صفوفَ تطابق شروطَ التقرير');
    } catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      _toast('تعذّر تشغيلُ التقرير: $e');
    }
  }

  Future<void> _deleteReport(CustomReportData r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(PhosphorIconsBold.trash, color: _err),
        title: Text('حذف «${r.name}»'),
        content: const Text('يُحذف التعريفُ وسجلُّ تشغيلاته. ولا رجوع.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _err),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(reportingRepositoryProvider).deleteCustomReport(r.id);
      if (!mounted) return;
      if (_selectedReportId == r.id) {
        setState(() {
          _selectedReportId = null;
          _results = const [];
        });
      }
      ref.invalidate(_reportsProvider);
      _toast('حُذف «${r.name}»');
    } catch (e) {
      if (!mounted) return;
      _toast('تعذّر الحذف: $e');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
