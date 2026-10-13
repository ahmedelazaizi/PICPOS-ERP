part of 'reports_picpos_screen.dart';

// ---------------------------------------------------------------------------
// _HoverCard — reusable hover-aware container card (منسوخ حرفياً من الأصل —
// يبقى Container/MouseRegion يدوي لأن PicPosContentCard لا يوفّر منطق hover
// التفاعلي؛ السلوك يُحفظ كما هو حسب مصيدة النسخ).
// ---------------------------------------------------------------------------
class _HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  // ملحوظة: كان لها `highlighted` يُبرزها حين تكون فئتُها مفتوحةً في
  // الأكورديون. وقد حلّ محلَّ الأكورديون شريطٌ جانبيٌّ يُبرز الفئةَ المختارةَ
  // في مكانه — فلم يبقَ من يمرّر الرايةَ، وبقاؤها معطَّلةً يوهم بخيارٍ لا أثرَ له.
  const _HoverCard({
    required this.child,
    required this.onTap,
  });

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final showActive = _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: showActive
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.border.withValues(alpha: 0.5),
            width: showActive ? 1.2 : 1,
          ),
          boxShadow: showActive
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  )
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data classes (منسوخة حرفياً من الأصل).
// ---------------------------------------------------------------------------
/// مجموعاتُ فئات التقارير في الشريط الجانبيّ — ترتيبُها ترتيبُ العرض.
List<String> get _kGroupOrder => [
  tr('البيع والربح'),
  tr('المخزون والشراء'),
  tr('العملاء والموردون'),
  tr('المال والضرائب'),
  tr('المتابعة والتحليل'),
];

/// فئةُ التقارير ← مجموعتُها.
///
/// ⚠️ **كلُّ فئةٍ لا بدّ لها من مدخلٍ هنا**: الشريطُ يرسم المجموعاتِ بترتيب
/// [_kGroupOrder]، وفئةٌ بلا مجموعةٍ تسقط في آخر مجموعةٍ صامتةً. يقيس ذلك
/// حارسٌ في `test/widget/picpos_reports_hub_test.dart`.
Map<String, String> get _kCatGroup => {
  'sales': tr('البيع والربح'),
  'profit': tr('البيع والربح'),
  'returns': tr('البيع والربح'),
  'inventory': tr('المخزون والشراء'),
  'purchases': tr('المخزون والشراء'),
  'customers': tr('العملاء والموردون'),
  'suppliers': tr('العملاء والموردون'),
  'reps': tr('العملاء والموردون'),
  'cashbox': tr('المال والضرائب'),
  'taxes': tr('المال والضرائب'),
  'users': tr('المتابعة والتحليل'),
  'branches': tr('المتابعة والتحليل'),
  'audit': tr('المتابعة والتحليل'),
  'analytics': tr('المتابعة والتحليل'),
};

/// وصفُ الفئة في رأس لوحة التفصيل.
///
/// ⚠️ **مقصوصٌ على ما تحويه الفئةُ فعلاً.** أوصافُ التصميم تَعِد في أربعة
/// مواضعَ بما لا وجودَ له هنا: «ربح كل فاتورة» في الأرباح، و«أسباب الإرجاع»
/// في المرتجعات، و«الأصناف الراكدة» في المخزون، و«المديونية والدفعات» في
/// الموردين — فحُذفت تلك الجملُ وحدَها وبقي ما تُقابله تقاريرُ قائمة.
///
/// و«القوائم المالية» فئةٌ مستقلّةٌ في التصميم وهي هنا **تقريرٌ داخل
/// التحليلات** — فلم تُخترَع فئةٌ جديدةٌ لتطابق الرسم.
Map<String, String> get _kCatDesc => {
  'sales': tr('كل ما يخص حركة البيع: الفواتير، الكاشير، الأصناف، المجموعات، وطرق الدفع'),
  'profit': tr('تكلفة المبيعات وصافي الربح وهامش الربح على مستوى الصنف والتصنيف'),
  'returns': tr('مرتجعات المبيعات والمشتريات والمبالغ المستردة'),
  'inventory': tr('أرصدة وقيم المخزون، كرت الصنف، الجرد، والصلاحيات'),
  'purchases': tr('المشتريات بفلاتر كاملة ومتابعة أوامر الشراء المفتوحة'),
  'customers': tr('كشوف الحساب، تقادم الذمم، سلوك الشراء، وتسوية الذمم مع الأستاذ العام'),
  'suppliers': tr('كشوف حساب الموردين وحجم التعامل'),
  'reps': tr('مبيعات المناديب وتحصيلاتهم من المستندات المختومة، وتغطية المسارات، ومخزون السيارات'),
  'cashbox': tr('حركة الخزينة، الورديات وعجز النقدية، التوصيل، والمصروفات التشغيلية'),
  'taxes': tr('الضريبة المحصلة والمدفوعة وصافي الالتزام وحالة الفاتورة الإلكترونية'),
  'users': tr('نشاط المستخدمين وسجل الدخول ومصفوفة الصلاحيات لكل دور'),
  'branches': tr('مقارنة أداء الفروع والتحويلات المخزنية بينها'),
  'audit': tr('سجل العمليات والتعديلات والطباعة والإلغاءات — أثر كامل لكل حركة'),
  'analytics': tr('اتجاهات وأنماط المبيعات وتقسيم العملاء ودوران المخزون'),
};

class PicposReportCategory {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final List<PicposReportEntry> mainReports;
  final List<PicposReportShortcut> shortcuts;

  const PicposReportCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.mainReports,
    this.shortcuts = const [],
  });
}

class PicposReportEntry {
  final String id;
  final String title;
  final String subtitle;
  final String? permission;
  final VoidCallback action;

  /// Manager override is enabled for every protected report — same UX as the
  /// legacy launcher. Kept as a getter (not a constructor field) so the
  /// analyzer doesn't complain about an "unused optional parameter" while
  /// preserving the contract documented in data-model.md.
  bool get allowManagerOverride => true;

  const PicposReportEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.action,
    this.permission,
  });
}

class PicposReportShortcut {
  final String id;
  final String title;
  final String parentReportId;

  /// Destination for shortcuts that lead somewhere OTHER than their parent
  /// report. Without this every shortcut fell through to `parent.action()`,
  /// so «حسب المجموعة» opened the plain sales report — the by-category report
  /// existed and was reachable elsewhere, but this chip never went there,
  /// which read to users as "the report is missing".
  final VoidCallback? action;

  const PicposReportShortcut(this.id, this.title, this.parentReportId,
      {this.action});
}

class _FlatItem {
  final String id;
  final String title;
  final String subtitle;
  final PicposReportCategory category;
  final bool isShortcut;
  const _FlatItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.isShortcut,
  });
}

List<_FlatItem> _flatten(List<PicposReportCategory> cats) {
  final out = <_FlatItem>[];
  for (final cat in cats) {
    for (final r in cat.mainReports) {
      out.add(_FlatItem(
        id: r.id,
        title: r.title,
        subtitle: r.subtitle,
        category: cat,
        isShortcut: false,
      ));
    }
    for (final s in cat.shortcuts) {
      out.add(_FlatItem(
        id: s.id,
        title: s.title,
        subtitle: cat.title,
        category: cat,
        isShortcut: true,
      ));
    }
  }
  return out;
}

/// أفعالُ الكتالوج التي تحتاج شجرةَ الودجت.
///
/// ⚠️ **ولماذا كائنٌ لا معاملاتٌ خمسة**: من يريد وصفَ الكتالوج — الشريطُ
/// الجانبيُّ يقرأ العناوينَ والصلاحيّات — لا شأنَ له بأيٍّ منها، ولولا
/// [inert] لاضطرَّ إلى تلفيق خمسِ دوالٍّ فارغةٍ في موضع الاستدعاء.
class PicposReportActions {
  /// دفعُ شاشةِ تقريرٍ على المُلاح.
  final void Function(Widget Function()) open;

  /// حواراتٌ تُبنى في مكانها ولا تُدفَع كشاشة.
  final VoidCallback showLowStock;
  final VoidCallback showExpired;
  final VoidCallback showExpiring;
  final VoidCallback showArReconciliation;
  final VoidCallback showInventoryGlReconciliation;

  const PicposReportActions({
    required this.open,
    required this.showLowStock,
    required this.showExpired,
    required this.showExpiring,
    required this.showArReconciliation,
    required this.showInventoryGlReconciliation,
  });

  static void _noop() {}
  static void _noopOpen(Widget Function() _) {}

  /// وصفٌ بلا فتح — لمن يقرأ الكتالوج ليعرضه لا ليفتحه.
  ///
  /// ⚠️ ونقرةٌ على نتيجةٍ بُنيت بهذه لا تفعل شيئاً بصمت. فمن يعرضها يفتح
  /// عبر مسارِ الشاشة المحروس لا عبر `action` — وهو الفرقُ الذي يحفظ فحصَ
  /// الصلاحية وموافقةَ المسؤول.
  static const inert = PicposReportActions(
    open: _noopOpen,
    showLowStock: _noop,
    showExpired: _noop,
    showExpiring: _noop,
    showArReconciliation: _noop,
    showInventoryGlReconciliation: _noop,
  );
}
