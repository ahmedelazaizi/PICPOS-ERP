part of 'reports_picpos_screen.dart';

extension _ReportsPicposBuild on _ReportsPicposScreenState {
  /// أعمدةُ بطاقات التقارير — ثلاثةٌ في التصميم على العرض الكامل.
  int _detailColumnsFor(double w) {
    if (w >= 1150) return 3;
    if (w >= 760) return 2;
    return 1;
  }

  /// «تقرير مخصص» — يفتح مُنشئَ التقارير القائم.
  ///
  /// ⚠️ زرٌّ في التصميم ولم يكن في الشاشة، و`ReportBuilderScreen` **موجودةٌ
  /// فعلاً** ويصل إليها المستخدمُ من مكانٍ آخر — فهذا كشفُ ما هو قائمٌ لا
  /// وعدٌ بما ليس كذلك.
  Widget _customReportButton() {
    return ElevatedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ReportBuilderScreen(),
        ),
      ),
      icon: const Icon(PhosphorIconsBold.plus, size: 17),
      label:  Text(tr('تقرير مخصص')),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
    );
  }

  int _reportColumnsFor(double w) {
    if (w >= 1500) return 5;
    if (w >= 1200) return 4;
    if (w >= 900) return 3;
    if (w >= 640) return 2;
    return 1;
  }

  Widget _searchBar() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: tr('بحث في جميع التقارير...'),
          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(PhosphorIconsBold.x, size: 16),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          filled: true,
          fillColor: Theme.of(context).cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}