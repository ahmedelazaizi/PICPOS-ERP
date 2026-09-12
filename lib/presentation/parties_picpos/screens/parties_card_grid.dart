// شبكةُ بطاقاتِ الأطراف — ثلاثةُ أعمدةٍ في التصميم بدل `ListView` من
// `ListTile`.
//
// ⚠️ **والأزرارُ الأربعةُ لم تُختزل إلى ثلاثة.** التصميمُ يرسم «كشف حساب»
// وقلمَ تعديلٍ وثلاثَ نقاط؛ والشاشةُ القائمة تحمل أربعةَ إجراءات (سندٌ ماليّ ·
// كشفُ حساب · تعديل · حذف). فالنقاطُ الثلاثُ صارت قائمةً تحمل **السندَ
// والحذفَ** — لا زخرفاً. حذفُ إجراءٍ من شاشةٍ ماليّةٍ بحجّة «التصميم لا
// يرسمه» كان سيُسقط قدرةً قائمة.
part of 'parties_picpos_screen.dart';

/// لونُ سِمَةِ الطرف.
///
/// ⚠️ **نفسُ `getPartyTypeColor` حرفيّاً** (‏`party_helpers.dart`) بنفس ترتيب
/// الأولويّة — لا لوحةً جديدة. الفوركان يلوّنان نفسَ الطرف، فانحرافُ اللون
/// بينهما عيبٌ يُبلَّغ عنه لا ذوقٌ مختلف.
Color _partyTint(PicPosPartyCard p) {
  if (p.isDeliveryCompany) return Colors.teal;
  if (p.isCustomer && p.isSupplier) return Colors.purple;
  if (p.isCustomer) return AppColors.primary;
  if (p.isSupplier) return AppColors.warning;
  return AppColors.textMuted;
}

/// إجراءاتُ البطاقة — تُمرَّر من الشاشة لأن كلَّ واحدٍ منها يفتح حواراً أو
/// مساراً يحتاج `ref`، وهذا الملفُّ عرضٌ خالص.
class PartyCardActions {
  const PartyCardActions({
    required this.onStatement,
    required this.onEdit,
    required this.onVoucher,
    required this.onDelete,
    required this.onWhatsApp,
  });

  final void Function(PicPosPartyCard) onStatement;
  final void Function(PicPosPartyCard) onEdit;
  final void Function(PicPosPartyCard) onVoucher;
  final void Function(PicPosPartyCard) onDelete;

  /// إرسالُ كشفِ حسابٍ أو مطالبةٍ على واتساب — يُفتَح من الشاشة لأنه
  /// يحتاج `ref` لفحصِ الصلاحية وقراءةِ رمز الدولة.
  final void Function(PicPosPartyCard) onWhatsApp;
}

/// بطاقةُ طرفٍ واحدة.
class PartyCard extends StatelessWidget {
  const PartyCard({
    super.key,
    required this.party,
    required this.actions,
  });

  final PicPosPartyCard party;
  final PartyCardActions actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _partiesMuted(context);
    final tint = _partyTint(party);
    final tintBg = tint.withValues(alpha: 31 / 255);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, tint, tintBg, muted),
          const SizedBox(height: 11),
          _balanceRow(context, muted),
          if (party.isOverLimit) ...[
            const SizedBox(height: 11),
            _overLimitBanner(),
          ],
          const SizedBox(height: 11),
          _actionRow(context),
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context,
    Color tint,
    Color tintBg,
    Color muted,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tintBg,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            party.initials,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: tint,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                party.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              Text(
                party.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: muted,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: tintBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            party.typeLabel,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: tint,
            ),
          ),
        ),
      ],
    );
  }

  Widget _balanceRow(BuildContext context, Color muted) {
    // اللونُ يتبع الإشارة: موجبٌ = مدينٌ على الطرف (أخضر عندنا)، سالبٌ = له.
    final balanceColor =
        party.balance >= 0 ? AppColors.success : AppColors.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'الرصيد',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
              Text(
                party.balanceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  color: balanceColor,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          party.creditLimitLabel,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: muted,
          ),
        ),
      ],
    );
  }

  Widget _overLimitBanner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: .10),
          border: Border.all(color: AppColors.error.withValues(alpha: .30)),
          borderRadius: BorderRadius.circular(9),
        ),
        // ‏`Flexible` لا `mainAxisSize.min` عارياً: البطاقةُ في عمودٍ واحدٍ على
        // شاشةٍ ضيّقةٍ تُبقي للنصّ أقلَّ من عرضه، وبلا هذا كان يفيض بالشريط
        // الأصفر بدل أن يقصَّ بالحذف. (‏قِيس: ‏٩٫٥ بكسل عند عرضِ ٢٤٠.)
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsBold.warning, size: 13, color: AppColors.error),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'تجاوز حد الائتمان',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.error,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _actionRow(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _partiesMuted(context);
    final border = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(9),
      side: BorderSide(color: theme.dividerColor),
    );

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              key: const Key('party-statement'),
              onPressed: () => actions.onStatement(party),
              icon: const Icon(PhosphorIconsBold.fileText,
                  size: 13, color: AppColors.primary),
              label: Text(
                'كشف حساب',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: border,
                side: BorderSide(color: theme.dividerColor),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _squareAction(
          context,
          keyValue: 'party-edit',
          icon: PhosphorIconsBold.pencilSimple,
          color: AppColors.warning,
          tooltip: 'تعديل',
          onPressed: () => actions.onEdit(party),
        ),
        const SizedBox(width: 6),
        // النقاطُ الثلاثُ تحمل ما لا يتّسع له الصفّ — لا زخرفاً.
        SizedBox(
          width: 32,
          height: 32,
          child: PopupMenuButton<String>(
            key: const Key('party-more'),
            tooltip: 'المزيد',
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            icon: Icon(PhosphorIconsBold.dotsThreeVertical,
                size: 13, color: muted),
            onSelected: (v) {
              if (v == 'voucher') actions.onVoucher(party);
              if (v == 'whatsapp') actions.onWhatsApp(party);
              if (v == 'delete') actions.onDelete(party);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'voucher',
                child: Row(
                  children: [
                    Icon(PhosphorIconsBold.money,
                        size: 16, color: AppColors.success),
                    SizedBox(width: 8),
                    Text('سند مالي', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'whatsapp',
                child: Row(
                  children: [
                    Icon(PhosphorIconsBold.whatsappLogo,
                        size: 16, color: AppColors.success),
                    SizedBox(width: 8),
                    Text('إرسال واتساب', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(PhosphorIconsBold.trash,
                        size: 16, color: AppColors.error),
                    SizedBox(width: 8),
                    Text('حذف', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _squareAction(
    BuildContext context, {
    required String keyValue,
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 32,
      height: 32,
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton(
          key: Key(keyValue),
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
            side: BorderSide(color: theme.dividerColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          child: Icon(icon, size: 13, color: color),
        ),
      ),
    );
  }
}

/// الشبكةُ نفسُها — ثلاثةُ أعمدةٍ تتقلّص مع ضيق العرض.
class PartiesCardGrid extends StatelessWidget {
  const PartiesCardGrid({
    super.key,
    required this.parties,
    required this.actions,
  });

  final List<PicPosPartyCard> parties;
  final PartyCardActions actions;

  @override
  Widget build(BuildContext context) {
    if (parties.isEmpty) {
      return const PicPosEmptyState(
        icon: PhosphorIconsBold.users,
        title: 'لا يوجد أطراف',
        hint: 'جرّب تغيير الترشيح أو مسح خانة البحث.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          < 700 => 1,
          < 1080 => 2,
          _ => 3,
        };
        // الارتفاعُ ثابتٌ لا نسبةٌ: البطاقةُ تكبر ببانر التجاوز، والنسبةُ
        // الثابتةُ كانت ستقصّه في العمود الضيّق. و`mainAxisExtent` يمنح
        // البطاقةَ ارتفاعاً كافياً للحالتين معاً.
        return GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 11,
            mainAxisSpacing: 11,
            mainAxisExtent: 168,
          ),
          itemCount: parties.length,
          itemBuilder: (context, i) => PartyCard(
            key: ValueKey(parties[i].id),
            party: parties[i],
            actions: actions,
          ),
        );
      },
    );
  }
}
