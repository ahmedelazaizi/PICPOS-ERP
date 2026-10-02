// بطاقةُ كيانٍ — كتلةُ `kind:'cards'` في ملفّات تصميم الشاشات الجديدة.
//
// تعرض كياناً واحداً (‏فرعاً · مساراً · موظفاً · أصلاً) في ثلاث طبقات:
// رأسٌ بأيقونةٍ أو أحرفٍ أولى وعنوانٍ وحبّةِ حالة، ثمّ شبكةُ إحصاءاتٍ
// متساويةِ الأعمدة، ثمّ تذييلُ رقائقَ على أرضيّة الحقل.
//
// ⚠️ **«الملف الكامل» لا يظهر إلّا حين يوجد ما يُفتَح.** في التصميم يُشتقّ
// من `!!DRAWERS[c.id]`، وهنا من [PicPosEntityCard.onOpen]. فسهمٌ يَعِد
// بتفصيلٍ ثمّ لا يفتح شيئاً أسوأُ من غيابه — ولذلك تُربَط قابليّةُ النقر
// بنفس الشرط، لا بعَلَمٍ منفصلٍ قد ينحرف عنه.
import 'package:flutter/material.dart';

import '../../core/i18n/tr.dart';
import '../../core/theme/app_colors.dart';
import 'picpos_surface.dart';

/// إحصاءٌ واحدٌ في شبكة البطاقة.
class PicPosEntityStat {
  const PicPosEntityStat(this.label, this.value, {this.tint});

  final String label;
  final String value;

  /// `null` ⇒ لونُ النصّ العاديّ. يُستعمل اللونُ للفت النظر إلى تجاوزٍ أو نقص.
  final Color? tint;
}

/// رقاقةٌ في تذييل البطاقة — أيقونةٌ ونصٌّ بلا إطار.
class PicPosEntityChip {
  const PicPosEntityChip(this.icon, this.label, {this.tint});

  final IconData icon;
  final String label;
  final Color? tint;
}

class PicPosEntityCard extends StatelessWidget {
  const PicPosEntityCard({
    super.key,
    required this.title,
    required this.tint,
    this.subtitle,
    this.icon,
    this.initials,
    this.status,
    this.statusTint,
    this.stats = const [],
    this.chips = const [],
    this.onOpen,
    this.openLabel,
  });

  final String title;
  final String? subtitle;
  final Color tint;

  /// أيقونةٌ أو أحرفٌ أولى — والأيقونةُ تسبق حين تُعطى الاثنتان.
  final IconData? icon;
  final String? initials;

  final String? status;
  final Color? statusTint;

  final List<PicPosEntityStat> stats;
  final List<PicPosEntityChip> chips;

  /// حين يُعطى: البطاقةُ قابلةٌ للنقر ويظهر سطرُ «الملف الكامل».
  final VoidCallback? onOpen;

  /// `null` ⇒ «الملف الكامل» مترجَمةً عبر `tr()` وقتَ الرسم.
  final String? openLabel;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(17),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _head(context),
          if (stats.isNotEmpty) _stats(context),
          if (chips.isNotEmpty || onOpen != null) _footer(context),
        ],
      ),
    );
    if (onOpen == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(17),
        child: card,
      ),
    );
  }

  Widget _head(BuildContext context) {
    final sTint = statusTint ?? tint;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: icon != null
                ? Icon(icon, size: 23, color: tint)
                : Text(
                    initials ?? '',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: tint,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                    color: context.picposText,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: context.picposMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (status != null && status!.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: sTint.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: sTint,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stats(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.picposHairline)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < stats.length; i++)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      // بلا فاصلٍ قبل الأوّل — التصميمُ يضعه على كلّ خانةٍ
                      // ويقع الأوّلُ على حافّة البطاقة فلا يُرى.
                      start: i == 0
                          ? BorderSide.none
                          : BorderSide(color: context.picposHairline),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        stats[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: context.picposMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        stats[i].value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: stats[i].tint ?? context.picposText,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border(top: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final ch in chips)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        ch.icon,
                        size: 12.5,
                        color: ch.tint ?? context.picposMuted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        ch.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ch.tint ?? context.picposMuted,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (onOpen != null) ...[
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  openLabel ?? tr('الملف الكامل'),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: context.picposBrandInk,
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  Icons.arrow_back_rounded,
                  size: 13,
                  color: context.picposBrandInk,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// شبكةُ بطاقاتٍ متساويةِ العرض تلتفّ عند الضيق.
///
/// ⚠️ **`align-items:start` في التصميم**: البطاقاتُ تختلف ارتفاعاً (‏رقائقُ
/// سطرٍ أو سطرَين)، وشدُّها لأطولِها يترك فراغاً أبيضَ داخلَ القصيرة.
class PicPosEntityCardGrid extends StatelessWidget {
  const PicPosEntityCardGrid({
    super.key,
    required this.children,
    this.minTileWidth = 340,
    this.gap = 13,
  });

  final List<Widget> children;
  final double minTileWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.isFinite ? c.maxWidth : minTileWidth;
        var perRow = ((maxW + gap) / (minTileWidth + gap)).floor();
        if (perRow < 1) perRow = 1;
        if (perRow > children.length) perRow = children.length;
        final tileW = (maxW - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            for (final w in children) SizedBox(width: tileW, child: w),
          ],
        );
      },
    );
  }
}

/// رأسُ كتلةٍ — شريطٌ ملوَّنٌ وعنوانٌ ووصفٌ خافتٌ على اليسار.
///
/// نفسُ رأسِ جدول البيانات، لكنّه هنا خارجَ بطاقةٍ لأنّ كتلةَ البطاقات في
/// التصميم شبكةٌ عاريةٌ لا صندوقٌ واحد.
class PicPosBlockHeader extends StatelessWidget {
  const PicPosBlockHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 15,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: context.picposText,
              ),
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: context.picposMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
