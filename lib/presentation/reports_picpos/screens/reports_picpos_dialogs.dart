part of 'reports_picpos_screen.dart';

extension _ReportsPicposSearch on _ReportsPicposScreenState {
  Widget _shortcutsBar(PicposReportCategory cat) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.picposHairline),
      ),
      child: Wrap(
        spacing: 11,
        runSpacing: 11,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            tr('اختصارات سريعة'),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: context.picposMuted,
            ),
          ),
          for (final s in cat.shortcuts) _expandedShortcutChip(cat, s),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // «المفضّلة وآخر ما فُتح» — بطاقةٌ واحدةٌ ببلاطات، لا سطرا رقائقَ منفصلان.
  // -----------------------------------------------------------------------

  /// المفضّلةُ أوّلاً ثمّ آخرُ ما فُتح بلا تكرار، بحدٍّ أعلى ستّ بلاطاتٍ كما
  /// في التصميم (`repeat(6,1fr)`).
  List<({_FlatItem item, bool fav})> _pinnedItems() {
    final out = <({_FlatItem item, bool fav})>[];
    final seen = <String>{};
    void add(String id, bool fav) {
      if (!seen.add(id) || out.length >= 6) return;
      for (final i in _allItems) {
        if (i.id == id) {
          out.add((item: i, fav: fav));
          return;
        }
      }
      seen.remove(id);
    }

    for (final id in _favorites) {
      add(id, true);
    }
    for (final id in _recent) {
      add(id, false);
    }
    return out;
  }

  Widget _pinnedCard(List<({_FlatItem item, bool fav})> pinned) {
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.picposHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.picposHairline)),
            ),
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsBold.star,
                  size: 18,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    tr('المفضّلة وآخر ما فُتح'),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: context.picposText,
                    ),
                  ),
                ),
                Text(
                  tr('تُحفظ لكل مستخدم على حدة'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.picposMuted,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(18, 14, 18, 18),
            child: Wrap(
              spacing: 11,
              runSpacing: 11,
              children: [for (final p in pinned) _pinnedTile(p.item, p.fav)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pinnedTile(_FlatItem item, bool fav) {
    return SizedBox(
      width: 190,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openFlatItem(item),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: context.picposField,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.picposHairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      item.category.icon,
                      size: 17,
                      color: item.category.color,
                    ),
                    const Spacer(),
                    Icon(
                      fav
                          ? PhosphorIconsFill.star
                          : PhosphorIconsBold.clockCounterClockwise,
                      size: 13,
                      color: fav ? AppColors.warning : context.picposMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                    color: context.picposText,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  // ⚠️ التصميمُ يكتب «مفضّل · فُتح 14:20»، ولا وقتَ فتحٍ
                  //    مخزَّناً — المحفوظُ ترتيبٌ لا طابعُ وقت. فيُكتب ما
                  //    يُعرَف: أمفضّلٌ هو أم مفتوحٌ مؤخّراً، واسمُ فئته.
                  fav
                      ? tr('مفضّل · {p0}', {'p0': item.category.title})
                      : tr('فُتح مؤخّراً · {p0}', {'p0': item.category.title}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: context.picposMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _expandedShortcutChip(
    PicposReportCategory cat,
    PicposReportShortcut s,
  ) {
    final parent = cat.mainReports.firstWhere(
      (r) => r.id == s.parentReportId,
      orElse: () => cat.mainReports.first,
    );
    final chip = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        _registerOpen(s.id);
        (s.action ?? parent.action)();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: cat.color.withValues(alpha: 0.07),
          border: Border.all(color: cat.color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsBold.lightning, size: 11, color: cat.color),
            const SizedBox(width: 5),
            Text(
              s.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cat.color,
              ),
            ),
          ],
        ),
      ),
    );

    // Shortcut inherits parent's permission (FR-026).
    if (parent.permission != null) {
      return PermissionGuard(
        permission: parent.permission!,
        allowManagerOverride: parent.allowManagerOverride,
        actionName: s.title,
        child: chip,
      );
    }
    return chip;
  }

  // -----------------------------------------------------------------------
  // Search results — مُغلّفة بـ PicPosContentCard (هوية PicPos).
  // -----------------------------------------------------------------------
  Widget _searchResultsSection(List<_FlatItem> results, int cols) {
    if (results.isEmpty) {
      return PicPosContentCard(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Column(
            children: [
              Icon(
                PhosphorIconsBold.magnifyingGlass,
                size: 56,
                color: context.picposMuted.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                tr('لا توجد تقارير مطابقة لـ "{_query}"', {'_query': _query}),
                style: TextStyle(color: context.picposMuted),
              ),
            ],
          ),
        ),
      );
    }
    return PicPosContentCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _miniHeader(
            PhosphorIconsBold.magnifyingGlass,
            tr('نتائج البحث ({p0})', {'p0': results.length}),
            AppColors.primary,
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: results.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 3.6,
            ),
            itemBuilder: (_, i) => _flatResultCard(results[i]),
          ),
        ],
      ),
    );
  }

  Widget _flatResultCard(_FlatItem item) {
    final isFav = !item.isShortcut && _favorites.contains(item.id);
    return _HoverCard(
      onTap: () => _openFlatItem(item),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 8, 10, 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: item.category.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                item.category.icon,
                color: item.category.color,
                size: 17,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (item.isShortcut) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            tr('اختصار'),
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warningDark,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.picposMuted,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            if (!item.isShortcut)
              IconButton(
                tooltip: isFav ? tr('إزالة من المفضلة') : tr('إضافة للمفضلة'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 22,
                  height: 22,
                ),
                icon: Icon(
                  isFav ? PhosphorIconsFill.star : PhosphorIconsBold.star,
                  size: 13,
                  color: isFav ? AppColors.warning : context.picposMuted,
                ),
                onPressed: () => _toggleFavorite(item.id),
              ),
          ],
        ),
      ),
    );
  }
}
