part of '../activity_log_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ACTIVITY LOG — Filters, Chips, User Filter, Date Buttons
// ═══════════════════════════════════════════════════════════════════════════

mixin _ActivityLogFiltersMixin on ConsumerState<ActivityLogScreen> {
  // Abstract — provided by the shell
  DateTime? get fromDate;
  DateTime? get toDate;
  int? get selectedUserId;
  String? get selectedCategory;
  String? get selectedSubAction;
  String? get selectedAction;
  int? get selectedBranchId;
  Map<int, Set<int>> get branchUserMapping;
  set fromDate(DateTime? val);
  set toDate(DateTime? val);
  set selectedUserId(int? val);
  set selectedCategory(String? val);
  set selectedSubAction(String? val);
  set selectedAction(String? val);
  set selectedBranchId(int? val);
  void loadLogs();
  List<ActivityLog> get logs;
  Map<String, String> get actionLabels;
  Map<String, String> get entityLabels;
  Map<String, Map<String, String>> get subActionLabelsMap;
  Map<String, List<String>> get categoryActionsMap;

  Widget buildViewToggleButton({
    required IconData icon,
    required bool isSelected,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? AppColors.primary
                    : Colors.white.withValues(alpha: 0.7),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildFiltersBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          // Date Range (auto-reload on pick)
          _buildDateButton('من', fromDate, (date) {
            setState(() => fromDate = date);
            loadLogs();
          }),
          _buildDateButton('إلى', toDate, (date) {
            setState(() => toDate = date);
            loadLogs();
          }),

          // User filter dropdown
          buildUserFilter(),

          // Branch filter dropdown
          buildBranchFilter(),

          // Quick Category Chips
          const SizedBox(width: 8),
          _buildCategoryChip('الأصناف', 'items', PhosphorIconsBold.package),
          _buildCategoryChip(
            'المبيعات',
            'sales',
            PhosphorIconsBold.shoppingCart,
          ),
          _buildCategoryChip(
            'المشتريات',
            'purchases',
            PhosphorIconsBold.receipt,
          ),
          _buildCategoryChip('الخزينة', 'treasury', PhosphorIconsBold.money),
          _buildCategoryChip('العملاء', 'customers', PhosphorIconsBold.users),
          _buildCategoryChip('الموردين', 'suppliers', PhosphorIconsBold.truck),
          _buildCategoryChip('نقطة البيع', 'pos', PhosphorIconsBold.storefront),
          _buildCategoryChip('نقطة بيع الطاولات', 'table_pos', PhosphorIconsBold.table),
          _buildCategoryChip('العروض', 'offers', PhosphorIconsBold.tag),
          _buildCategoryChip(
            'المخزون',
            'inventory',
            PhosphorIconsBold.warehouse,
          ),
          _buildCategoryChip('الإعدادات', 'settings', PhosphorIconsBold.gear),
          _buildCategoryChip('الجلسات', 'auth', PhosphorIconsBold.userCircle),
          _buildCategoryChip(
            'المستخدمين',
            'users',
            PhosphorIconsBold.usersThree,
          ),
          _buildCategoryChip('الطاولات', 'tables', PhosphorIconsBold.table),
          _buildCategoryChip('التوصيل', 'delivery', PhosphorIconsBold.moped),
          _buildCategoryChip('الطابعات', 'printers', PhosphorIconsBold.printer),
          _buildCategoryChip(
            'الموارد البشرية',
            'hr',
            PhosphorIconsBold.userPlus,
          ),
          _buildCategoryChip('الأدوار', 'roles', PhosphorIconsBold.shieldCheck),
          _buildCategoryChip(
            'تصميم الفواتير',
            'invoice_design',
            PhosphorIconsBold.fileText,
          ),
          _buildCategoryChip('الفروع', 'branches', PhosphorIconsBold.buildings),

          // Sub-filter chips (appear when category is selected)
          if (selectedCategory != null &&
              subActionLabelsMap.containsKey(selectedCategory)) ...[
            const SizedBox(width: 4),
            Container(
              width: 1,
              height: 24,
              color: Theme.of(context).dividerColor,
            ),
            const SizedBox(width: 4),
            ...subActionLabelsMap[selectedCategory]!.entries.map(
              (e) => _buildSubActionChip(e.value, e.key),
            ),
          ],

          // Search Button
          ElevatedButton.icon(
            onPressed: loadLogs,
            icon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
            label: const Text('بحث'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),

          // Clear Filters
          TextButton(
            onPressed: () {
              setState(() {
                fromDate = DateTime.now().subtract(const Duration(days: 7));
                toDate = DateTime.now();
                selectedUserId = null;
                selectedAction = null;
                selectedCategory = null;
                selectedSubAction = null;
                selectedBranchId = null;
              });
              loadLogs();
            },
            child: const Text('مسح الفلاتر'),
          ),

          // Log Count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'عدد العمليات: ${logs.length}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.info,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, String category, IconData icon) {
    final isSelected = selectedCategory == category;
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isSelected ? Colors.white : AppColors.primary,
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selectedColor: AppColors.primary,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.primary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (selected) {
        setState(() {
          selectedCategory = selected ? category : null;
          selectedAction = null;
          selectedSubAction = null;
        });
        loadLogs();
      },
    );
  }

  Widget _buildSubActionChip(String label, String actionKey) {
    final isSelected = selectedSubAction == actionKey;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: ChoiceChip(
        selected: isSelected,
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selectedColor: AppColors.info,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : AppColors.info,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (selected) {
          setState(() {
            selectedSubAction = selected ? actionKey : null;
          });
          loadLogs();
        },
      ),
    );
  }

  Widget _buildDateButton(
    String label,
    DateTime? date,
    Function(DateTime) onSelect,
  ) {
    return InkWell(
      onTap: () async {
        final selected = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (selected != null) onSelect(selected);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.textMuted),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              PhosphorIconsBold.calendar,
              size: 16,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              '$label: ${date != null ? '${date.day}/${date.month}/${date.year}' : 'اختر'}',
            ),
          ],
        ),
      ),
    );
  }

  Widget buildUserFilter() {
    final usersAsync = ref.watch(allUsersProvider);
    return usersAsync.when(
      data: (users) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.textMuted),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: selectedUserId,
              hint: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIconsBold.user,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(width: 8),
                  Text('كل المستخدمين'),
                ],
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('كل المستخدمين'),
                ),
                ...users.map(
                  (u) => DropdownMenuItem<int?>(
                    value: u.user.id,
                    child: Text(u.user.displayName),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => selectedUserId = value);
                loadLogs();
              },
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget buildBranchFilter() {
    final branchesAsync = ref.watch(allBranchesProvider);
    return branchesAsync.when(
      data: (branches) {
        if (branches.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.textMuted),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: selectedBranchId,
              hint: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIconsBold.buildings,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(width: 8),
                  Text('كل الفروع'),
                ],
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('كل الفروع'),
                ),
                ...branches.map(
                  (b) => DropdownMenuItem<int?>(
                    value: b.id,
                    child: Text(b.name),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => selectedBranchId = value);
                loadLogs();
              },
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
