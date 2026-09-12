// lib/presentation/shell/report_category_nav.dart
//
// فئاتُ التقارير في الشريط الجانبيّ — البندُ التاسع من أمر المالك 2026-09-12.
//
// ⚠️ **أُخرِجَت من `nav_widgets.dart` لتصير قابلةَ القياس.** كانت صنفاً
// خاصّاً داخل `part` من `app_shell.dart`، فلا اختبارَ ودجتٍ يصل إليها —
// وبلاغُ المالك «ليس تحتها باقى الشاشات الداخليه» لم يكن لي سبيلٌ إلى
// إثباته أو نفيه إلّا بإخراجها. والصنفُ الخاصُّ في `part` ليس تفصيلَ
// تنظيم: هو سطحُ واجهةٍ بلا حارسٍ ممكن.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/providers/e_invoicing_providers.dart';
import '../../domain/models/nav_search.dart';
import '../reports_picpos/screens/reports_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// فئاتُ التقارير في الشريط — البندُ التاسع من أمر المالك 2026-09-12
// ═══════════════════════════════════════════════════════════════════════════

/// رؤوسُ فئات التقارير تحت مجموعة «التقارير»، وتحت كلِّ رأسٍ تقاريرُه.
///
/// ⚠️ **الكتالوجُ يُقرأ من مصدره لا يُنسَخ.** `buildPicposReportCatalog` هي
/// عينُ ما تبنيه شاشةُ التقارير؛ ونسخُ العناوين هنا كان يُنتج مصدراً ثالثاً
/// في ملفٍّ يحمل أصلاً تحذيراً من ازدواجٍ قائم. وتُستدعى بـ
/// [PicposReportActions.inert] لأن الوصفَ لا يفتح شيئاً.
///
/// ⚠️ **والفتحُ يمرّ بشاشة التقارير لا بـ`action()`.** بطاقاتُ التقارير
/// هناك ملفوفةٌ بـ`PermissionGuard` مع تجاوزِ المسؤول؛ ونقرةٌ من الشريط
/// تستدعي الفعلَ مباشرةً كانت تفتح تقريراً محجوباً بلا كلمةِ مرور. فالشريطُ
/// **يطلب** والشاشةُ تفتح بعد `ensurePermission`.
class ReportCategoryNav extends ConsumerStatefulWidget {
  /// فتحُ التقرير: يُسجَّل الطلبُ ويُنتقَل إلى شاشة التقارير.
  final void Function(String categoryId, String? reportId) onOpen;

  const ReportCategoryNav({super.key, required this.onOpen});

  @override
  ConsumerState<ReportCategoryNav> createState() => _ReportCategoryNavState();
}

class _ReportCategoryNavState extends ConsumerState<ReportCategoryNav> {
  String? _openCatId;

  /// مفتاحُ رأسِ كلِّ فئةٍ — للتمرير إليه عند فتحها.
  final _headKeys = <String, GlobalKey>{};

  /// يُمرِّر رأسَ الفئة المفتوحة إلى أعلى النافذة فتظهر تقاريرُها تحته.
  ///
  /// ⚠️ **وهذا ليس تزييناً.** الشريطُ قائمةٌ مُمرَّرةٌ أطولُ من النافذة،
  /// ورأسٌ عند حدّها الأسفل تُفتَح تقاريرُه **أسفلَ الحدّ** — فلا يتغيّر
  /// شيءٌ في المرئيّ، والنقرةُ تبدو ميّتة. وهي الحالةُ الوحيدةُ الباقيةُ
  /// التي تفسّر بلاغَ المالك: القياسُ أثبت أنّ الفتحَ نفسَه يعمل — معزولاً
  /// وفي تعشيش `ListView › AnimatedCrossFade › Column` بعينه.
  void _revealHead(String catId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _headKeys[catId]?.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.0, // الرأسُ إلى أعلى النافذة
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final platform = ref.watch(activeEInvoicePlatformProvider).value;
    final cats = buildPicposReportCatalog(
      actions: PicposReportActions.inert,
      eInvoicePlatform: platform,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final cat in cats) ..._buildCategory(cat),
      ],
    );
  }

  List<Widget> _buildCategory(PicposReportCategory cat) {
    final isOpen = _openCatId == cat.id;
    final headKey = _headKeys.putIfAbsent(cat.id, GlobalKey.new);
    return [
      InkWell(
        key: headKey,
        onTap: () {
          setState(() => _openCatId = isOpen ? null : cat.id);
          if (!isOpen) _revealHead(cat.id);
        },
        child: Container(
          height: 32,
          margin: const EdgeInsets.only(right: 18, left: 6, bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isOpen
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Icon(cat.icon, size: 13, color: cat.color.withValues(alpha: 0.9)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cat.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: isOpen ? 0.95 : 0.72),
                    fontSize: 11.5,
                    fontWeight: isOpen ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: isOpen ? 0.25 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  PhosphorIconsBold.caretLeft,
                  size: 10,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      ),
      if (isOpen)
        for (final r in cat.mainReports)
          InkWell(
            onTap: () => widget.onOpen(cat.id, r.id),
            child: Container(
              height: 28,
              margin: const EdgeInsets.only(right: 30, left: 6, bottom: 1),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// مداخلُ البحث — البندُ الأوّل من بلاغ المالك 2026-09-12
// ═══════════════════════════════════════════════════════════════════════════

/// يحوّل كتالوجَ التقارير إلى مداخلَ يفهمها بحثُ الشريط.
///
/// ⚠️ **مُشتقٌّ من الكتالوج لا مكتوبٌ بيد.** `kNavSearchKeywords` خريطةٌ
/// يدويّةٌ تحمل لشاشة التقارير أربعَ كلماتٍ، وتحت الشاشة ثلاثةَ عشرَ فئةً
/// وستّةٌ وأربعون تقريراً. وإضافةُ عناوينِها يدويّاً تُنتج مصدراً ثانياً
/// يتخلّف: تقريرٌ جديدٌ في الكتالوج لا أحدَ يذكر كلمتَه هنا، فيصير غيرَ
/// قابلٍ للبحث بلا بلاغ. فالاشتقاقُ هو الحارس.
///
/// ⚠️ **وكلُّها تحمل [reportsScreenIndex]**: لا `ScreenId` لتقرير، والوجهةُ
/// شاشةُ التقارير نفسُها مع طلبٍ تستهلكه — وهو عينُ مسارِ فتحِ الشريط
/// المحروسِ بـ`ensurePermission`.
///
/// ووصفُ التقرير يدخل [NavSearchEntry.keywords] لأنّه «ما بداخله» حقّاً:
/// من يبحث عن «عمولة» لا يعرف أنّ التقريرَ اسمُه «أداء المندوبين».
List<NavSearchEntry> reportSearchEntries({
  required int reportsScreenIndex,
  required List<PicposReportCategory> categories,
}) {
  final out = <NavSearchEntry>[];
  for (final cat in categories) {
    out.add(NavSearchEntry(
      index: reportsScreenIndex,
      label: cat.title,
      group: 'reports',
      kind: NavSearchKind.reportCategory,
      reportCategoryId: cat.id,
    ));
    for (final r in cat.mainReports) {
      out.add(NavSearchEntry(
        index: reportsScreenIndex,
        label: r.title,
        group: 'reports',
        kind: NavSearchKind.report,
        reportCategoryId: cat.id,
        reportId: r.id,
        parentLabel: cat.title,
        keywords: [if (r.subtitle.trim().isNotEmpty) r.subtitle],
      ));
    }
  }
  return out;
}
