// عارضُ التقرير الواحد — الشكلُ الذي يعمل به التصميم.
//
// ═══ لماذا عارضٌ واحدٌ لا سبعُ شاشات ═══
//
// مركزُ التقارير اليومَ يُبحر إلى **شاشاتٍ قائمة**، وسبعةُ مداخلَ لا شاشةَ
// لها فوُصلت بأقربِ عامّةٍ موجودة — وهو عينُ ما بلّغ عنه المالكُ بالصور:
// «بدون ظهور نمط تصميم يوضح التقرير المطلوب».
//
// والتصميمُ يعمل بنموذجٍ آخرَ تماماً: `REPORTS` في «PicPos Reports.dc.html»
// **تعريفٌ لكلّ تقرير** (ترويسةٌ · تبويباتٌ · مؤشّراتٌ · رسمٌ · جدول)،
// والشاشةُ **عارضٌ واحدٌ** يقرأ التعريف. فسبعُ شاشاتٍ متطابقةِ الهيكل كانت
// ستنحرف عن بعضها بأوّل تعديل.
//
// ═══ الفرقُ الجوهريُّ عن التصميم ═══
//
// ⚠️ التصميمُ يكتب كلَّ رقمٍ نصّاً — لأنّه صورة. وهنا **كلُّ رقمٍ يُحمَّل**:
// [PicPosReportTabDef.load] تُنادى بمدى التاريخ وتعود بمحتوى التبويبة من
// الاستعلام. ونقلُ أرقام التصميم كما هي كان سيُنتج تقريراً يبدو حيّاً ويكذب
// — وهو أسوأُ من مدخلٍ نائبٍ يقول صراحةً إنّه غيرُ جاهز.
//
// ⚠️ **والشارةُ لا تظهر قبل التحميل.** التصميمُ يضع على التبويبة شارةَ عددٍ
// (‏«٥» على أوامر الشراء). والعددُ لا يُعرَف إلّا بعد الاستعلام، فيبقى مكانُ
// الشارة فارغاً حتى تُفتَح التبويبة. رقمٌ يُكتب قبل قياسه رقمٌ يكذب.
//
// ⚠️ **والتحميلُ يُخزَّن بمفتاحِ (تبويبة، مدى).** بلا ذلك يُعاد الاستعلامُ
// عند كلّ إعادةِ بناء — وإعادةُ البناء تقع مع كلّ تبديلِ تبويبةٍ في
// `TabBarView`.
//
// ⚠️ **وكلُّ التبويبات تُحمَّل عند الفتح لا عند تبديلها** — وهذا مقصود:
// التصميمُ يضع الشارةَ على تبويبةٍ **لم تُفتَح** بعد، والشارةُ لا تكون
// صادقةً إلّا إن قِيست. فالتحميلُ الكسولُ كان يعني إمّا شاراتٍ تظهر
// متأخّرةً واحدةً واحدة، أو رقماً يُكتب قبل قياسه. وتقاريرُ هذا الملفّ
// تبويبةٌ أو تبويبتان، فالكلفةُ استعلامٌ إضافيٌّ واحدٌ على الأكثر — ولو
// كَبُرَ العددُ يوماً فالحلُّ شارةٌ تُحسَب باستعلامِ عدٍّ رخيصٍ لا تحميلٌ
// كسول.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_hub_kpi.dart';
import '../../picpos_shell/picpos_report_bar.dart';
import '../../picpos_shell/picpos_report_chart.dart';
import '../../picpos_shell/picpos_report_tabs.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';

/// محتوى تبويبةٍ بعد التحميل — كلُّه اختياريّ.
///
/// التبويبةُ في التصميم تحمل أيّاً من الثلاثة: صفَّ مؤشّرات، ورسمَ أعمدة،
/// وجدولاً. ولا تبويبةَ تحمل الثلاثةَ إلزاماً — فتبويبةُ «الفواتير» جدولٌ
/// وحدَه، و«العمليات» رسمٌ وجدولٌ بلا مؤشّرات.
class PicPosReportTabContent {
  const PicPosReportTabContent({
    this.kpis = const [],
    this.chart,
    this.table,
    this.badge,
  });

  final List<PicPosHubKpi> kpis;
  final PicPosReportChart? chart;
  final PicPosDataTable? table;

  /// شارةُ عددٍ على رأس التبويبة — **مقيسةٌ من الصفوف المحمَّلة** لا مكتوبة.
  final String? badge;

  bool get isEmpty => kpis.isEmpty && chart == null && table == null;
}

/// تعريفُ تبويبةٍ واحدة.
class PicPosReportTabDef {
  const PicPosReportTabDef({
    required this.id,
    required this.label,
    required this.icon,
    required this.load,
    this.note = '',
  });

  final String id;
  final String label;
  final IconData icon;

  /// سطرُ قاعدة العمل أعلى التبويبة — «TABS[].note» في التصميم.
  final String note;

  /// يُنادى مرّةً لكلّ (تبويبة، مدى) ويُخزَّن. `ref` للقراءة من المزوِّدات.
  final Future<PicPosReportTabContent> Function(WidgetRef ref, DateTimeRange range)
      load;
}

/// تعريفُ تقريرٍ كامل.
class PicPosReportDefinition {
  const PicPosReportDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tabs,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<PicPosReportTabDef> tabs;
}

/// عارضُ التقرير — يركّب التعريفَ على لبنات `picpos_shell`.
class ReportViewPicposScreen extends ConsumerStatefulWidget {
  const ReportViewPicposScreen({super.key, required this.definition});

  final PicPosReportDefinition definition;

  @override
  ConsumerState<ReportViewPicposScreen> createState() =>
      _ReportViewPicposScreenState();
}

class _ReportViewPicposScreenState extends ConsumerState<ReportViewPicposScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late DateTimeRange _range;

  /// نتائجُ التحميل بمفتاحِ «معرِّفُ التبويبة|بصمةُ المدى».
  final Map<String, Future<PicPosReportTabContent>> _futures = {};

  /// آخرُ محتوىً محمَّلٍ لكلّ تبويبةٍ — مصدرُ الشارة وحدَه.
  final Map<String, PicPosReportTabContent> _loaded = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: widget.definition.tabs.length, vsync: this);
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get _rangeKey =>
      '${_range.start.millisecondsSinceEpoch}-${_range.end.millisecondsSinceEpoch}';

  Future<PicPosReportTabContent> _future(PicPosReportTabDef tab) {
    final key = '${tab.id}|$_rangeKey';
    return _futures.putIfAbsent(key, () => tab.load(ref, _range));
  }

  void _onRangeChanged(DateTime start, DateTime end) {
    setState(() {
      _range = DateTimeRange(start: start, end: end);
      // المفاتيحُ تحمل المدى، فالخريطةُ لا تُصفَّر — لكنّ الشاراتِ المعروضةَ
      // صارت من مدىً آخر، وشارةٌ من مدىً سابقٍ رقمٌ يكذب.
      _loaded.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.definition;
    return PicPosScreenScaffold(
      title: def.title,
      subtitle: def.subtitle,
      icon: def.icon,
      bodyPadding: EdgeInsets.zero,
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
              for (final t in def.tabs)
                (
                  label: t.label,
                  icon: t.icon,
                  badge: _loaded[t.id]?.badge,
                ),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [for (final t in def.tabs) _TabBody(tab: t, future: _future(t), onLoaded: _remember)],
      ),
    );
  }

  void _remember(String tabId, PicPosReportTabContent content) {
    if (!mounted) return;
    if (_loaded[tabId]?.badge == content.badge) return;
    // بعد الإطار — الشارةُ تغيّر شريطَ التبويبات وهو يُبنى في نفس الإطار.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _loaded[tabId] = content);
    });
  }
}

class _TabBody extends StatelessWidget {
  const _TabBody({
    required this.tab,
    required this.future,
    required this.onLoaded,
  });

  final PicPosReportTabDef tab;
  final Future<PicPosReportTabContent> future;
  final void Function(String tabId, PicPosReportTabContent content) onLoaded;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PicPosReportTabContent>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
        }
        if (snap.hasError) {
          return _Message(
            icon: PhosphorIconsBold.warningCircle,
            text: 'تعذّر حسابُ التقرير',
            sub: '${snap.error}',
            tint: Theme.of(context).colorScheme.error,
          );
        }
        final content = snap.data ?? const PicPosReportTabContent();
        onLoaded(tab.id, content);
        if (content.isEmpty) {
          return _Message(
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
                padding: const EdgeInsetsDirectional.fromSTEB(26, 18, 26, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (content.kpis.isNotEmpty) ...[
                      PicPosHubKpiRow(items: content.kpis),
                      const SizedBox(height: 14),
                    ],
                    if (content.chart != null) ...[
                      content.chart!,
                      const SizedBox(height: 14),
                    ],
                    if (content.table != null) content.table!,
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

class _Message extends StatelessWidget {
  const _Message({
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
        ),
      ),
    );
  }
}
