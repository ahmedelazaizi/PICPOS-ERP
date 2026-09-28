import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

// معاينةُ شاشة الكاشير داخلَ ديالوج «إعدادات البيع السريع» — §٣.
//
// المصدرُ: اللوحةُ اليمنى في
// `invoice_templates/design/PicPos Quick Sale Dialog.dc.html`، ووسمُها
// «مقياس ٥٠٪».
//
// ═══ لماذا مقاساتٌ حقيقيّةٌ لا صورةٌ تقريبيّة ═══
//
// قيمةُ هذه اللوحة كلُّها في أنّ المديرَ يجرّ «عرض التسمية» فيرى الرقعةَ
// تتّسع **بنفس البكسل**. فكلُّ مقاسٍ هنا يأتي من الإعداد لا من رقمٍ مكتوب،
// ومعاينةٌ ترسم ثوابتَ تبدو صحيحةً وهي تكذب — وذلك أسوأُ من غيابها، لأنّها
// تجعله يثق برقمٍ لم يُطبَّق.
//
// ⚠️ **والمحاكاةُ داكنةٌ في الوضعَين معاً**: هي صورةٌ لشاشة الكاشير لا سطحُ
// واجهةٍ يتبع وضعَ المستخدم — كما تبقى معاينةُ الورق المطبوع بيضاءَ في
// الوضع الغامق. ولهذا لا `context.picpos*` هنا.

const _canvas = Color(0xFF0B1220);
const _bar = Color(0xFF111A2B);
const _tile = Color(0xFF161F33);
const _line = Color(0xFF243247);
const _ink = Color(0xFFE2E8F2);
const _muted = Color(0xFF7C8AA3);

/// أسماءُ تصنيفاتٍ للمعاينة — أوّلُها طويلٌ عمداً.
///
/// «صناعة الحلويات» هو الاسمُ الذي صوّره المالكُ مبتوراً 2026-08-29، فوجودُه
/// هنا يجعل أثرَ «عرض التسمية» مرئيّاً في اللحظة التي يُجَرُّ فيها المِنزلق.
const _catNames = ['صناعة الحلويات', 'مشروبات', 'ألبان', 'خضار'];

class QuickSaleDisplayPreview extends StatelessWidget {
  final bool showTopBar;

  // ── التصنيفات ──
  final double catIconSize;
  final double catFontSize;
  final double catSpacing;
  final double catRunSpacing;
  final double catLabelWidth;
  final String catShape;

  // ── الشبكة ──
  final int gridColumns;
  final double gridSpacing;
  final double gridAspectRatio;

  // ── الأصناف ──
  final double nameFontSize;
  final double priceFontSize;
  final bool showProductImages;

  const QuickSaleDisplayPreview({
    super.key,
    this.showTopBar = true,
    this.catIconSize = 44,
    this.catFontSize = 9,
    this.catSpacing = 12,
    this.catRunSpacing = 8,
    this.catLabelWidth = 52,
    this.catShape = 'circle',
    this.gridColumns = 8,
    this.gridSpacing = 8,
    this.gridAspectRatio = 0.75,
    this.nameFontSize = 12,
    this.priceFontSize = 14,
    this.showProductImages = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _canvas,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(),
          if (showTopBar) _topBar(),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _barcode(),
                const SizedBox(height: 8),
                _grid(),
                const SizedBox(height: 10),
                _categories(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: const BoxDecoration(
          color: _bar,
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(children: [
          const Icon(PhosphorIconsBold.eye, size: 14, color: _muted),
          const SizedBox(width: 7),
          const Expanded(
            child: Text('معاينة شاشة الكاشير',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _ink)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF4A80E8).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text('مقياس ٥٠٪',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF9EC1FF))),
          ),
        ]),
      );

  Widget _topBar() => Container(
        key: const Key('preview-topbar'),
        height: 22,
        decoration: const BoxDecoration(
          color: _bar,
          border: Border(bottom: BorderSide(color: _line)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: const Row(children: [
          Icon(PhosphorIconsBold.bell, size: 11, color: Color(0xFFF59E0B)),
          SizedBox(width: 6),
          Text('الفرع الرئيسي',
              style: TextStyle(fontSize: 8.5, color: _muted)),
        ]),
      );

  Widget _barcode() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: _tile,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(children: [
          Icon(PhosphorIconsBold.barcode, size: 12, color: _muted),
          SizedBox(width: 7),
          Text('امسح الباركود…',
              style: TextStyle(fontSize: 9, color: _muted)),
        ]),
      );

  /// صفّان من الشبكة — يكفيان لإظهار أثرِ الأعمدة والتباعد والنسبة.
  Widget _grid() {
    final columns = gridColumns.clamp(2, 12);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: columns * 2,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: gridSpacing / 2,
        mainAxisSpacing: gridSpacing / 2,
        childAspectRatio: gridAspectRatio,
      ),
      itemBuilder: (_, _) => Container(
        key: const Key('preview-tile'),
        decoration: BoxDecoration(
          color: _tile,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showProductImages)
              const Expanded(
                child: Icon(PhosphorIconsBold.package,
                    size: 10, color: _muted),
              ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text('صنف',
                  style: TextStyle(
                      fontSize: nameFontSize / 2, color: _ink)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text('٣٢.٠٠',
                  style: TextStyle(
                      fontSize: priceFontSize / 2,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF22C55E))),
            ),
          ],
        ),
      ),
    );
  }

  /// شريطُ التصنيفات — بنفس مقاسات الإعداد مقسومةً على اثنين (مقياس ٥٠٪).
  ///
  /// ⚠️ **التسميةُ سطران** كما شُحنت بعد بلاغ 2026-08-29، فالمعاينةُ تُظهر
  /// أثرَ «عرض التسمية» على البتر لا على العرض وحدَه.
  Widget _categories() {
    final iconSize = catIconSize / 2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: _bar,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: catSpacing / 2,
        runSpacing: catRunSpacing / 2,
        children: [
          for (var i = 0; i < _catNames.length; i++)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: i == 0 ? const Color(0xFF0250D3) : _tile,
                    border: Border.all(color: _line),
                    borderRadius: catShape == 'rounded'
                        ? BorderRadius.circular(iconSize * 0.25)
                        : BorderRadius.circular(iconSize / 2),
                  ),
                  child: Icon(PhosphorIconsBold.cookie,
                      size: iconSize * 0.45,
                      color: i == 0 ? Colors.white : _muted),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  key: const Key('preview-cat-label'),
                  width: catLabelWidth,
                  child: Text(
                    _catNames[i],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: catFontSize,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: const Color(0xFFC6D0E0),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
