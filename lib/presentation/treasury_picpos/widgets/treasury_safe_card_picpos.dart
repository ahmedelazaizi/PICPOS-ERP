// بطاقةُ صندوقٍ بهويّة PicPos — **فوركٌ بقرار المالك 2026-08-22**.
//
// المصدر: `treasury/widgets/treasury_safe_card.dart`، ويبقى بلا مساسٍ لشاشة
// UralCash.
//
// **الفرقُ عن الأصل — مقيسٌ من التصميم لا من ذوق:**
//   • الأصلُ `Card`+`ListTile` بزوايا ٦ وأرضيّةٍ ملوّنةٍ بـ٤٪؛ والتصميمُ صفٌّ
//     بحدٍّ شعريٍّ وزوايا ١٢ بلا أرضيّةٍ ملوّنة.
//   • الأصلُ يعرض **إمّا** «افتراضي» **أو** نوعَ الصندوق في سطر العنوان
//     الفرعيّ — فصندوقٌ افتراضيٌّ يُخفي نوعَه. والتصميمُ يعرض الاثنين:
//     شارةُ «افتراضي» بجانب الاسم، والسطرُ الفرعيُّ `النوع · الفرع`.
//   • الأصلُ يضع `BranchChip` (شارةً ملوّنةً) بجانب الاسم؛ والتصميمُ يضع
//     **اسمَ الفرع نصّاً** في السطر الفرعيّ.
//
// ⚠️ **واسمُ الفرع يُمرَّر ولا يُستخرَج هنا**: البطاقةُ تبقى `StatelessWidget`
// خالصةً بلا مزوِّد، فتُختبَر بلا `ProviderScope` — واللوحُ الحاوي يحلُّ
// الأسماءَ مرّةً واحدةً لكلّ الصناديق بدل أن تشتقَّ كلُّ بطاقةٍ مزوِّداً.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import 'treasury_picpos_tokens.dart';

class TreasurySafeCardPicpos extends StatelessWidget {
  const TreasurySafeCardPicpos({
    super.key,
    required this.name,
    required this.safeType,
    required this.balance,
    required this.isDefault,
    this.branchName,
    this.onTap,
  });

  final String name;

  /// نفسُ قيم عمود `safe_type` — `cash` / `bank` / `click` / مخصّص.
  final String safeType;
  final double balance;
  final bool isDefault;

  /// اسمُ الفرع. `null` للصناديق القديمة بلا ربطِ فرع (نفسُ حالةِ
  /// `BranchChip` التي تُخفي نفسَها) — فيُعرض النوعُ وحدَه بلا فاصلة معلّقة.
  final String? branchName;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tint = TreasuryPicposTokens.tintFor(safeType);

    // ⚠️ **الرصيدُ غيرُ الموجب لا يأخذ لونَ النوع** — نفسُ حارس الأصل
    // (`balance > 0 ? color : textMuted`) منقولاً كما هو. التصميمُ يلوّن
    // بالنوع دائماً لأن عيّنتَه كلُّها موجبة؛ وصندوقٌ سالبٌ بلونٍ أخضرَ
    // يُقرأ سليماً وهو ليس كذلك.
    final balanceColor = balance > 0 ? tint : AppColors.textMuted;

    final subtitle = branchName == null
        ? TreasuryPicposTokens.labelFor(safeType)
        : '${TreasuryPicposTokens.labelFor(safeType)} · $branchName';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: TreasuryPicposTokens.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  TreasuryPicposTokens.iconFor(safeType),
                  size: 16,
                  color: tint,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isDefault) ...[
                          const SizedBox(width: 6),
                          const _DefaultBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // ⚠️ `Flexible` لا `Text` عارية: رصيدٌ من ثمانية أرقامٍ على
              // بطاقةٍ ضيّقةٍ كان يفيض ٤٨ بكسل — مقيسٌ في
              // `picpos_treasury_design_test`. والقصُّ أهونُ من الشريط
              // الأصفر والأسود.
              Flexible(
                child: Text(
                  NumberFormat('#,##0.00', 'ar').format(balance),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: balanceColor,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شارةُ «افتراضي» — `x.isDefault` في التصميم.
class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'افتراضي',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
