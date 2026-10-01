// شريطُ ترشيح «العملاء والموردين» — بطاقةٌ واحدةٌ تحمل خانةَ بحثٍ مصمتة،
// فاصلاً رأسيّاً، خمسَ حبّاتٍ للنوع، ثمّ زرَّ «المجموعات» في الطرف.
//
// ⚠️ **بدلُ `SegmentedButton`** الذي كان يحمل الأشرطةَ الخمسة. والدلالةُ لم
// تتغيّر — انتقاءٌ أُحاديٌّ من خمسةٍ بنفس المعرّفات (`all`/`customer`/
// `supplier`/`delivery`/`both`) — فقط الشكلُ صار حبّاتِ التصميم. وحُفظت
// إمكانيّةُ الوصول: كلُّ حبّةٍ `InkWell` داخلَ `Semantics` منتقاةٍ صراحةً،
// فقارئُ الشاشة يعلن الحالةَ كما كان `SegmentedButton` يفعل.
part of 'parties_picpos_screen.dart';

/// حبّةُ نوعٍ واحدة — دائريّةٌ، تنقلب إلى لون العلامة حين تُنتقى.
class _PartyTypePill extends StatelessWidget {
  const _PartyTypePill({
    required this.filter,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final PicPosPartyFilter filter;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _partiesMuted(context);
    final fg = selected ? Colors.white : theme.textTheme.bodyMedium?.color;

    return Semantics(
      selected: selected,
      button: true,
      label: filter.displayLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              border: Border.all(
                color: selected ? AppColors.primary : theme.dividerColor,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: selected ? Colors.white : muted),
                const SizedBox(width: 6),
                Text(
                  filter.displayLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// أيقونةُ كلِّ ترشيحٍ — مطابقةٌ لما كان `SegmentedButton` يحمله.
IconData _partyFilterIcon(PicPosPartyFilter f) {
  switch (f) {
    case PicPosPartyFilter.all:
      return PhosphorIconsBold.listDashes;
    case PicPosPartyFilter.customer:
      return PhosphorIconsBold.user;
    case PicPosPartyFilter.supplier:
      return PhosphorIconsBold.truck;
    case PicPosPartyFilter.delivery:
      return PhosphorIconsBold.moped;
    case PicPosPartyFilter.both:
      return PhosphorIconsBold.usersThree;
  }
}

/// شريطُ الترشيح الكامل.
class PartiesFilterBar extends StatelessWidget {
  const PartiesFilterBar({
    super.key,
    required this.controller,
    required this.filter,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.onGroupsPressed,
    this.showTypeFilters = true,
  });

  final TextEditingController controller;
  final PicPosPartyFilter filter;
  final ValueChanged<PicPosPartyFilter> onFilterChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onGroupsPressed;
  final bool showTypeFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _partiesMuted(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      // ‏`Wrap` لا `Row`: خمسُ حبّاتٍ وخانةُ بحثٍ وزرٌّ لا تسعُ عرضَ شاشةٍ
      // ضيّقة، و`Row` كانت ستفيض بدل أن تلتفّ. (‏قِيس بفحصِ فيضانٍ صريح.)
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 340,
            height: 36,
            child: TextField(
              controller: controller,
              onChanged: onSearchChanged,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                hintText: tr('البحث بالاسم أو رقم الهاتف...'),
                hintStyle: TextStyle(fontSize: 12, color: muted),
                prefixIcon: Icon(
                  PhosphorIconsBold.magnifyingGlass,
                  size: 14,
                  color: muted,
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 34, minHeight: 34),
                filled: true,
                fillColor: picposDialogField(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (showTypeFilters) ...[
            Container(width: 1, height: 24, color: theme.dividerColor),
            for (final f in PicPosPartyFilter.values)
              _PartyTypePill(
                filter: f,
                icon: _partyFilterIcon(f),
                selected: filter == f,
                onTap: () => onFilterChanged(f),
              ),
          ],
          OutlinedButton.icon(
            onPressed: onGroupsPressed,
            icon: const Icon(PhosphorIconsBold.usersFour, size: 14),
            label:  Text(tr('المجموعات'), style: const TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.textTheme.bodyMedium?.color,
              side: BorderSide(color: theme.dividerColor),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
