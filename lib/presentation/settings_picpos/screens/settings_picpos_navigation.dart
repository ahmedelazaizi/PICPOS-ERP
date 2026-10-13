part of 'settings_picpos_screen.dart';

extension _SettingsPicposNavigation on _SettingsPicposScreenState {
  Widget _buildSectionPane(_SettingsSection section) {
    return SettingsSectionPane(
      sectionId: section.id,
      children: [
        _SectionHeader(section: section),
        const SizedBox(height: 20),
        for (final child in section.children()) ...[
          child,
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  /// Search over section titles + their keyword lists.
  ///
  /// It resolves to a SECTION, not to an individual control, because most
  /// settings here live inside nested dialogs and expansion tiles that have
  /// no addressable identity. Landing the user on the right section is the
  /// honest thing this data can support — and it already fixes the case that
  /// motivated it, where «منع تراكم الأصناف» sits behind a tile inside a
  /// dialog inside a card and was effectively unfindable.
  Widget _buildSearchResults(List<_SettingsSection> sections, String query) {
    final q = query.toLowerCase();
    final matches = sections
        .where((s) =>
            s.title.toLowerCase().contains(q) ||
            s.keywords.toLowerCase().contains(q))
        .toList();

    if (matches.isEmpty) {
      return PicPosEmptyState(
        icon: PhosphorIconsBold.magnifyingGlass,
        title: tr('لا يوجد إعداد بهذا الاسم'),
        hint: tr('جرّب كلمة أقصر — «طابعة» بدل «إعدادات الطابعة الحرارية».'),
        action: TextButton(
          onPressed: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
          },
          child:  Text(tr('مسح البحث')),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 24),
      children: [
        Text(
          tr('{p0} قسم مطابق', {'p0': matches.length}),
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        for (final s in matches)
          PicPosContentCard(
            child: ListTile(
              leading: Icon(s.icon, color: AppColors.primary),
              title: Text(s.title),
              subtitle: Text(
                s.keywords,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(PhosphorIconsBold.caretLeft, size: 16),
              onTap: () => setState(() {
                _selectedSectionId = s.id;
                _searchController.clear();
                _searchQuery = '';
              }),
            ),
          ),
      ],
    );
  }

  // ignore: unused_element
  String _getThemeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return tr('تلقائي (حسب إعدادات النظام)');
      case ThemeMode.light:
        return tr('الوضع النهاري');
      case ThemeMode.dark:
        return tr('الوضع الليلي');
    }
  }

  /// ⚠️ كان `SimpleDialog` — بلاغُ المالك بالصورة 2026-08-25. والأوصافُ
  /// أدناه من التصميم (‏`SECTIONS.system` → بلوكُ «مظهر البرنامج»).
  // ignore: unused_element
  Future<void> _showThemeSelector(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    final labels = {
      ThemeMode.system: tr('تلقائي'),
      ThemeMode.light: tr('فاتح'),
      ThemeMode.dark: tr('غامق'),
    };

    final picked = await showPicPosOptionPicker<ThemeMode>(
      context: context,
      icon: PhosphorIconsBold.palette,
      title: tr('مظهر البرنامج'),
      subtitle: tr('يُطبَّق على كل الشاشات وشاشة العميل'),
      selected: current,
      options:  [
        PicPosOption(
          value: ThemeMode.light,
          label: tr('فاتح'),
          sub: tr('الأنسب للإضاءة القويّة والطباعة من الشاشة'),
          icon: PhosphorIconsBold.sun,
        ),
        PicPosOption(
          value: ThemeMode.dark,
          label: tr('غامق'),
          sub: tr('مريحٌ للكاشير في الورديات الليليّة'),
          icon: PhosphorIconsBold.moon,
        ),
        PicPosOption(
          value: ThemeMode.system,
          label: tr('تلقائي'),
          sub: tr('يتبع مظهرَ ويندوز'),
          icon: PhosphorIconsBold.monitor,
        ),
      ],
    );

    if (picked == null || picked == current) return;
    ref.read(themeModeProvider.notifier).setMode(picked);

    // #Forensic Log: Theme change
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      logger.logSettingsChange(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        tr('مظهر التطبيق'),
        newValue: labels[picked] ?? '',
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
  }
}
