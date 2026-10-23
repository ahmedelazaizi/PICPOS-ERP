import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/design_system/typography.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../picpos_shell/picpos_surface.dart';

// هيكلُ «ديالوج البيع السريع» — ودجتاتٌ خالصةٌ على التصميم.
//
// المصدرُ `invoice_templates/design/PicPos Quick Sale Dialog.dc.html`،
// وهو المعتمَدُ بأمر المالك 2026-08-28.
//
// ═══ لماذا هيكلٌ منفصلٌ لا فوركٌ للوحة ═══
//
// `pos_settings_widget.dart` يحمل منطقاً حقيقيّاً لا تنسيقاً فقط: حدودُ
// `pos_default_tax_rate` (‏`TaxRateBounds`)، وبلاطاتُ الصلاحية، ومهلةُ
// الجلسة الواحدة (‏Spec 135)، وتبطيلُ المزوّدات بعد الحفظ. ونسخُه إلى
// `*_picpos/` كان يضاعف ذلك كلَّه، فيفترق المنطقان عند أوّل إصلاح.
//
// فالهيكلُ وحدَه يُبنى هنا ودجتاتٍ خالصةً بلا حالةٍ ولا مزوّدات، واللوحةُ
// تستعملها **بعلمٍ من المستدعي** لا بفرعٍ على `Brand.isPicPos`: ذاك ثابتُ
// ترجمةٍ لا تراه البوّابةُ (تبني النكهةَ الافتراضيّة)، وهو نفسُ سببِ تمرير
// `PosLayoutPolicy` صراحةً في `PosProductSelectionPanel`.

/// وصفُ قسمٍ من أقسام الديالوج الخمسة — `SECTIONS` في التصميم.
class QuickSaleSection {
  /// مفتاحُ القسم كما في التصميم (`main` · `cat` · `grid` · `receipt` · `tpos`).
  final String key;
  final IconData icon;
  final Color tint;
  final String title;
  final String hint;

  /// عددُ الإعدادات في القسم — يظهر في الشريط الجانبيّ («‏١٧ إعداد»).
  ///
  /// ⚠️ **رقمٌ مقيسٌ لا مقدَّر**: مجموعُها ٣٧ وهو عددُ مفاتيح التصميم، وكلُّها
  /// موجودةٌ في المستودع قبل هذا البند — بما فيها اثنان بدَوَا مفقودَين
  /// (`pos_default_warehouse_branch_$branchId` بلاحقةِ فرعٍ، و
  /// `pos_session_timeout_enabled` ببادئة `pos_`).
  final int settingCount;

  const QuickSaleSection({
    required this.key,
    required this.icon,
    required this.tint,
    required this.title,
    required this.hint,
    required this.settingCount,
  });
}

/// الأقسامُ الخمسةُ بترتيب التصميم وألوانِه.
///
/// والعناوينُ **هي عينُ** ما تبنيه `pos_settings_widget.dart` سلفاً حرفاً
/// بحرف — ولهذا كان البندُ تنسيقاً لا بناء.
List<QuickSaleSection> get kQuickSaleSections => [
  QuickSaleSection(
    key: 'main',
    icon: PhosphorIconsBold.shoppingCart,
    tint: const Color(0xFF0250D3),
    title: tr('إعدادات البيع السريع الرئيسية'),
    hint: tr('الوردية والعرض، أزرار الكاشير، ترقيم المستندات، واجهة التفاعل، والسلة'),
    settingCount: 17,
  ),
  QuickSaleSection(
    key: 'cat',
    icon: PhosphorIconsBold.squaresFour,
    tint: const Color(0xFF22C55E),
    title: tr('إعدادات منطقة التصنيفات'),
    hint: tr('مقاسات شريط الأقسام أعلى شبكة الأصناف — سبعة قيم تتحرك معاً'),
    settingCount: 7,
  ),
  QuickSaleSection(
    key: 'grid',
    icon: PhosphorIconsBold.gridFour,
    tint: const Color(0xFF4A80E8),
    title: tr('إعدادات شبكة المنتجات'),
    hint: tr('تحكم في عدد وتباعد أيقونات المنتجات في الشبكة'),
    settingCount: 3,
  ),
  QuickSaleSection(
    key: 'receipt',
    icon: PhosphorIconsBold.receipt,
    tint: const Color(0xFF8B5CF6),
    title: tr('إعدادات الإيصال'),
    hint: tr('ما يُطبَع بعد إتمام البيع — ولغته وكوده وتذييله'),
    settingCount: 4,
  ),
  QuickSaleSection(
    key: 'tpos',
    icon: PhosphorIconsBold.table,
    tint: const Color(0xFFF59E0B),
    title: tr('إعدادات نقطة بيع الطاولات'),
    hint: tr('إعدادات تنظيم وتنسيق نقطة بيع الطاولات والصالة'),
    settingCount: 6,
  ),
];

/// أرقامٌ عربيّةٌ — نفسُ الدالّة المكرّرة في شاشات `*_picpos` الأخرى.
///
/// تُترك محلّيّةً عمداً: توحيدُها يمسُّ سبعَ شاشاتٍ ويخرج عن نطاق §٣.
String _ar(Object n) =>
    '$n'.replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)]);

/// أرضيّةُ رقعةٍ ملوّنةٍ خافتةٍ — `c.t + '22'` في التصميم.
Color _wash(Color tint) => tint.withValues(alpha: 0.13);

/// صفُّ إعدادٍ واحد — أيقونةٌ ملوّنةٌ · عنوانٌ · شارةُ مفتاح · شرحٌ · ضابط.
///
/// يطابق `{{ g.rows }}` في التصميم: حشوٌ رأسيٌّ ١١ وفاصلٌ سفليٌّ بالشعرة،
/// ورقعةُ أيقونةٍ ٣٢ بنصف قطر ١٠.
class QuickSaleSettingRow extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;

  /// مفتاحُ الإعداد في القاعدة — يُعرَض شارةً أحاديّةَ العرض.
  ///
  /// ⚠️ **ليس زينة.** التصميمُ يعرض `{{ r.key }}` في كلِّ صفّ، وبه يربط
  /// المديرُ ما يراه بما يُكتب فعلاً. و`direction: ltr` لأنّ المفتاحَ
  /// لاتينيٌّ داخلَ واجهةٍ من اليمين.
  final String settingKey;

  final String? sub;
  final Widget control;

  /// شارةُ صلاحيةٍ اختياريّة — `{{ r.perm }}` في التصميم.
  final String? permission;

  /// آخرُ صفٍّ في مجموعته لا يحمل فاصلاً سفليّاً.
  final bool isLast;

  const QuickSaleSettingRow({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    required this.settingKey,
    required this.control,
    this.sub,
    this.permission,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: _wash(tint),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.picposText,
                      ),
                    ),
                    if (permission != null) _PermissionBadge(permission!),
                    _KeyBadge(settingKey),
                  ],
                ),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    sub!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      height: 1.65,
                      color: context.picposMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          control,
        ],
      ),
    );
  }
}

class _KeyBadge extends StatelessWidget {
  final String value;
  const _KeyBadge(this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Text(
          value,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            fontFamily: AppTypography.mono,
            color: context.picposMuted,
          ),
        ),
      ),
    );
  }
}

class _PermissionBadge extends StatelessWidget {
  static const Color _violet = Color(0xFF8B5CF6);
  final String label;
  const _PermissionBadge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _violet.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: _violet,
        ),
      ),
    );
  }
}

/// ترويسةُ قسمٍ — رقعةٌ ملوّنةٌ خافتةٌ تحمل الأيقونةَ والعنوانَ والتلميح.
class QuickSaleSectionHeader extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String hint;

  const QuickSaleSectionHeader({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        border: Border.all(color: tint.withValues(alpha: 0.20)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _wash(tint),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.picposText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: context.picposMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقةُ مجموعةٍ — إطارٌ بالشعرة يضمُّ صفوفَ الإعداد، وترويسةٌ اختياريّة.
class QuickSaleGroupCard extends StatelessWidget {
  final String? label;
  final Color tint;
  final String? note;
  final List<Widget> rows;

  const QuickSaleGroupCard({
    super.key,
    required this.rows,
    required this.tint,
    this.label,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: context.picposField,
                border:
                    Border(bottom: BorderSide(color: context.picposHairline)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 3.5,
                    height: 15,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label!,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: context.picposText,
                      ),
                    ),
                  ),
                  if (note != null)
                    Text(
                      note!,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: context.picposMuted,
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ],
      ),
    );
  }
}

/// بلاطةُ قسمٍ في الشريط الجانبيّ — أيقونةٌ · عنوانٌ · عددُ الإعدادات · نقطة.
class QuickSaleNavTile extends StatelessWidget {
  static const Color dirtyTint = Color(0xFFF59E0B);

  final IconData icon;
  final Color tint;
  final String title;
  final int settingCount;
  final bool selected;

  /// تغييرٌ لم يُحفَظ في هذا القسم — نقطةٌ كهرمانيّةٌ في التصميم.
  final bool dirty;

  final VoidCallback? onTap;

  const QuickSaleNavTile({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    required this.settingCount,
    required this.selected,
    this.dirty = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? _wash(tint) : Colors.transparent,
          border: Border.all(
            color: selected ? tint.withValues(alpha: 0.35) : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected ? tint : _wash(tint),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 17, color: selected ? Colors.white : tint),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                      color: selected ? context.picposText : context.picposText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr('{p0} إعداد', {'p0': _ar(settingCount)}),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: context.picposMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (dirty)
              Container(
                key: const Key('nav-dirty-dot'),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: dirtyTint,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
