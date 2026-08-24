// شريطُ تبويبات الخزينة بشكل التصميم — كرتٌ بحدٍّ شعريّ، تبويباتٌ بخطٍّ
// سفليٍّ بثلاث نقاط، وحقلُ بحثٍ بعرض ٢٨٠ في آخر الصفّ.
//
// البديلُ كان `TabBar` القياسيّ بمؤشّرٍ يملأ التبويب — شكلٌ آخرُ تماماً.
// وهذا الشريطُ يقود نفسَ `TabController` فلا يتبدّل المنطق.
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'treasury_picpos_tokens.dart';

/// تبويبٌ واحد.
typedef TreasuryPicposTab = ({String label, IconData icon});

class TreasuryTabBarPicpos extends StatelessWidget {
  const TreasuryTabBarPicpos({
    super.key,
    required this.controller,
    required this.tabs,
    required this.searchController,
    required this.onSearchChanged,
    required this.searchQuery,
    this.searchHint = 'بحث في الخزينة (سندات، صناديق)...',
  });

  final TabController controller;
  final List<TreasuryPicposTab> tabs;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String searchQuery;
  final String searchHint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: TreasuryPicposTokens.hairlineOf(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      // `AnimatedBuilder` على المتحكّم: التبويبُ النشطُ يتبدّل من الشريط
      // ومن السحب على المحتوى معاً، فيُعاد الرسمُ في الحالتين.
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              _Tab(
                label: tabs[i].label,
                icon: tabs[i].icon,
                active: controller.index == i,
                onTap: () => controller.animateTo(i),
              ),
            const Spacer(),
            SizedBox(
              width: 280,
              height: 36,
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: searchHint,
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  suffixIcon: searchQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            searchController.clear();
                            onSearchChanged('');
                          },
                        ),
                  filled: true,
                  fillColor: TreasuryPicposTokens.fieldOf(context),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.primary : AppColors.textMuted;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
