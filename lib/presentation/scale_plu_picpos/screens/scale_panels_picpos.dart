// ignore_for_file: deprecated_member_use
part of 'scale_plu_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SCALE PLU (PicPos fork) — Panels: Header, Category Panel, Items Grid,
// Scale Panel
//
// Copied verbatim from `lib/presentation/screens/scale_plu/scale_panels.dart`
// (`_ScalePanelsMixin`). Only the `part of` target and the mixin name
// changed — see the copy-trap note in `scale_plu_picpos_screen.dart`.
// ═══════════════════════════════════════════════════════════════════════════

mixin _ScalePanelsPicposMixin on ConsumerState<ScalePluPicposScreen> {
  // Abstract — provided by the shell
  TextEditingController get searchController;
  String get searchQuery;
  set searchQuery(String val);
  bool get isExporting;
  Set<int> get selectedCategoryIds;
  Set<int> get selectedProductIds;
  List<LabelScale> get scales;
  int get selectedScaleIndex;
  set selectedScaleIndex(int val);
  void exportToScale();
  void verifyConnection();
  void selectAllVisible();
  void addScale();
  void editScale(int index);
  void deleteScale(int index);
  List<ProductEntity> filterProducts(List<ProductEntity> all);
  Future<void> loadScales();

  Widget buildHeader() {
    return Row(
      children: [
        const Icon(
          PhosphorIconsBold.scales,
          size: 28,
          color: AppColors.primary,
        ),
        const SizedBox(width: 10),
        Text(
          'تصدير مواد الميزان PLU',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.headlineMedium?.color,
          ),
        ),
        const Spacer(),
        // Search
        SizedBox(
          width: 250,
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'بحث عن صنف...',
              prefixIcon: const Icon(
                PhosphorIconsBold.magnifyingGlass,
                size: 18,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onChanged: (v) => setState(() => searchQuery = v),
          ),
        ),
        const SizedBox(width: 8),
        // PLU Manager button
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const PluManagerScreen(),
            ),
          ),
          icon: const Icon(PhosphorIconsBold.barcode, size: 18),
          label: const Text('مدير PLU'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF6C63FF),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            side: const BorderSide(color: Color(0xFF6C63FF)),
          ),
        ),
        const SizedBox(width: 8),
        // Preview data button
        OutlinedButton.icon(
          onPressed: () => _showDataPreview(),
          icon: const Icon(PhosphorIconsBold.table, size: 18),
          label: const Text('معاينة البيانات'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.deepPurple,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            side: const BorderSide(color: Colors.deepPurple),
          ),
        ),
        const SizedBox(width: 8),
        // Export button
        FilledButton.icon(
          onPressed: isExporting ? null : exportToScale,
          icon: isExporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(PhosphorIconsBold.upload, size: 18),
          label: const Text('ترحيل للميزان'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
        const SizedBox(width: 8),
        // Verify button
        OutlinedButton.icon(
          onPressed: verifyConnection,
          icon: const Icon(PhosphorIconsBold.plugsConnected, size: 18),
          label: const Text('تحقق'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(width: 8),
        // Select all
        OutlinedButton.icon(
          onPressed: selectAllVisible,
          icon: const Icon(PhosphorIconsBold.checkSquare, size: 18),
          label: const Text('تحديد الكل'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget buildCategoryPanel(
    AsyncValue<List<Category>> categoriesAsync,
    bool isDark,
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsBold.funnel,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'التصنيفات',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (selectedCategoryIds.isEmpty) {
                        categoriesAsync.whenData((cats) {
                          selectedCategoryIds.addAll(cats.map((c) => c.id));
                        });
                      } else {
                        selectedCategoryIds.clear();
                      }
                    });
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(40, 28),
                  ),
                  child: Text(
                    selectedCategoryIds.isEmpty ? 'الكل' : 'مسح',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: categoriesAsync.when(
              data: (categories) => ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  final isSelected = selectedCategoryIds.contains(cat.id);
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          selectedCategoryIds.add(cat.id);
                        } else {
                          selectedCategoryIds.remove(cat.id);
                        }
                      });
                    },
                    title: Text(cat.name, style: const TextStyle(fontSize: 13)),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildItemsGrid(
    AsyncValue<List<ProductEntity>> productsAsync,
    bool isDark,
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsBold.listBullets,
                  size: 18,
                  color: AppColors.info,
                ),
                const SizedBox(width: 8),
                const Text(
                  'أصناف الميزان',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                productsAsync.when(
                  data: (products) {
                    final filtered = filterProducts(products);
                    return Text(
                      '${selectedProductIds.length} / ${filtered.length} صنف',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          Expanded(
            child: productsAsync.when(
              data: (products) {
                final filtered = filterProducts(products);
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PhosphorIconsBold.scales,
                          size: 48,
                          color: AppColors.textMuted.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'لا توجد أصناف مطابقة',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'حدد تصنيفات أو اختر أصناف ميزان',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 16,
                    columns: const [
                      DataColumn(label: Text('ترحيل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('PLU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('اسم المادة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('سعر البيع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('النوع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('التصنيف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    ],
                    rows: filtered.map((p) {
                      final isSelected = selectedProductIds.contains(p.id);
                      return DataRow(
                        selected: isSelected,
                        color: WidgetStateProperty.resolveWith<Color?>((states) {
                          if (states.contains(WidgetState.selected)) {
                            return AppColors.success.withValues(alpha: 0.08);
                          }
                          return null;
                        }),
                        cells: [
                          DataCell(
                            Checkbox(
                              value: isSelected,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    selectedProductIds.add(p.id);
                                  } else {
                                    selectedProductIds.remove(p.id);
                                  }
                                });
                              },
                              activeColor: AppColors.success,
                            ),
                          ),
                          DataCell(
                            Text(
                              '${p.scalePluNumber ?? p.id}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 200,
                              child: Text(
                                p.name, overflow: TextOverflow.ellipsis, maxLines: 1,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          DataCell(Text(p.salePrice.toStringAsFixed(AppConstants.decimalPlaces), style: const TextStyle(fontSize: 13))),
                          DataCell(_buildScaleTypeBadge(p.scaleType ?? '')),
                          DataCell(
                            FutureBuilder<Category?>(
                              future: p.categoryId != null
                                  ? ref.read(productRepositoryProvider).getCategoryById(p.categoryId!)
                                  : Future.value(null),
                              builder: (_, snap) => Text(
                                snap.data?.name ?? '—',
                                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScaleTypeBadge(String scaleType) {
    final (label, color) = switch (scaleType) {
      'weight' => ('ميزان', AppColors.success),
      'weightByPiece' => ('حبة', AppColors.info),
      'display' => ('عرض', AppColors.warning),
      _ => ('عدد', AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  /// Show a preview of PLU data that will be sent to the scale
  Future<void> _showDataPreview() async {
    final products = ref.read(allProductsProvider).value ?? [];
    final filtered = filterProducts(products);
    final selected = filtered.where((p) => selectedProductIds.contains(p.id)).toList();

    if (selected.isEmpty) {
      AppToast.show(context, 'حدد أصناف أولاً لمعاينة البيانات', type: ToastType.warning);
      return;
    }

    // Load barcode settings
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final weightPrefix = await settingsRepo.getSetting('scale_weight_prefix') ?? '21';
    final pricePrefix = await settingsRepo.getSetting('scale_price_prefix') ?? '20';
    final codeLen = int.tryParse(await settingsRepo.getSetting('scale_weight_item_code_len') ?? '5') ?? 5;

    // Build PLU items for preview
    final pluItems = <ScalePLUItem>[];
    for (final p in selected) {
      final pluNumber = p.scalePluNumber ?? p.id;
      final isByWeight = scaleItemIsSoldByWeight(
        scaleType: p.scaleType,
        isSoldByWeight: p.isSoldByWeight,
      );
      final prefix = isByWeight ? weightPrefix : pricePrefix;
      final scaleBarcode = '$prefix${pluNumber.toString().padLeft(codeLen, '0')}';
      pluItems.add(ScalePLUItem(
        pluNumber: pluNumber, name: p.name, unitPrice: p.pricePerUnit ?? p.salePrice,
        isByWeight: isByWeight, department: isByWeight ? int.tryParse(weightPrefix) ?? 21 : int.tryParse(pricePrefix) ?? 20,
        barcode: scaleBarcode, productCode: p.code,
      ));
    }

    // Generate CSV content for preview
    final csvContent = LabelScaleService.instance.generatePLUCsv(pluItems);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(PhosphorIconsBold.table, color: Colors.deepPurple),
          const SizedBox(width: 8),
          Text('معاينة بيانات الترحيل (${pluItems.length} صنف)'),
        ]),
        content: SizedBox(
          width: 800,
          height: 500,
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'جدول الأصناف'),
                    Tab(text: 'صيغة CSV'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // Table view
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columnSpacing: 16,
                            columns: const [
                              DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('PLU', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('اسم الصنف', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('السعر', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('النوع', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('القسم', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('الباركود', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('كود المنتج', style: TextStyle(fontWeight: FontWeight.bold))),
                            ],
                            rows: pluItems.asMap().entries.map((e) {
                              final i = e.key;
                              final item = e.value;
                              return DataRow(cells: [
                                DataCell(Text('${i + 1}')),
                                DataCell(Text('${item.pluNumber}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(item.name)),
                                DataCell(Text(item.unitPrice.toStringAsFixed(AppConstants.decimalPlaces))),
                                DataCell(Text(item.isByWeight ? 'وزن' : 'عدد')),
                                DataCell(Text('${item.department}')),
                                DataCell(Text(item.barcode ?? '—', style: const TextStyle(fontFamily: 'monospace'))),
                                DataCell(Text(item.productCode ?? '—')),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                      // CSV view
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          csvContent,
                          style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Save CSV to Desktop for inspection
              final desktopPath = '${Platform.environment['USERPROFILE']}\\Desktop';
              final filePath = '$desktopPath\\plu_preview_${DateTime.now().millisecondsSinceEpoch}.csv';
              // Write as UTF-16 LE — matches PLU Manager's native TSV format (2.xls)
              final transport = ScaleTransport();
              await File(filePath).writeAsBytes(transport.encodeUtf16LE(csvContent));
              if (ctx.mounted) {
                Navigator.pop(ctx);
                AppToast.show(context, 'تم حفظ CSV على سطح المكتب', type: ToastType.success);
                Process.run('notepad.exe', [filePath]);
              }
            },
            child: const Text('حفظ CSV وفتحه'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget buildScalePanel(bool isDark) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.devices, size: 18, color: AppColors.warning),
                const SizedBox(width: 8),
                const Text('الموازين المتصلة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: addScale,
                  icon: const Icon(PhosphorIconsBold.plus, size: 16),
                  label: const Text('إضافة ميزان', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: const Size(0, 32),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: scales.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد موازين — اضغط "إضافة ميزان"',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 20,
                      columns: const [
                        DataColumn(label: Text('', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('الميزان', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('مفعّل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('IP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('المنفذ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('العلامة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('الاتصال', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('سعة PLU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('إجراءات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                      rows: scales.asMap().entries.map((entry) {
                        final i = entry.key;
                        final s = entry.value;
                        final isSelected = i == selectedScaleIndex;
                        return DataRow(
                          selected: isSelected,
                          color: WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.selected)) {
                              return AppColors.primary.withValues(alpha: 0.08);
                            }
                            return null;
                          }),
                          onSelectChanged: (_) => setState(() => selectedScaleIndex = i),
                          cells: [
                            DataCell(
                              Radio<int>(
                                value: i, groupValue: selectedScaleIndex,
                                onChanged: (v) => setState(() => selectedScaleIndex = v!),
                                activeColor: AppColors.primary,
                              ),
                            ),
                            DataCell(Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                            DataCell(
                              Switch(
                                value: s.isActive,
                                onChanged: (v) async {
                                  await ref.read(scaleRepositoryProvider).updateScaleStatus(s.id, v);
                                  loadScales();
                                },
                                activeThumbColor: AppColors.success,
                              ),
                            ),
                            DataCell(Text(s.ipAddress ?? '-', style: const TextStyle(fontSize: 13))),
                            DataCell(Text('${s.port}', style: const TextStyle(fontSize: 13))),
                            DataCell(Text(s.brand.toUpperCase(), style: const TextStyle(fontSize: 12))),
                            DataCell(Text(
                              const {'tcp': 'TCP/IP', 'serial': 'Serial', 'ftp': 'FTP', 'file': 'CSV'}[s.connectionType] ?? s.connectionType,
                              style: const TextStyle(fontSize: 12),
                            )),
                            DataCell(Text('${s.maxPlu}', style: const TextStyle(fontSize: 13))),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(PhosphorIconsBold.pencilSimple, size: 16),
                                    color: AppColors.warning, tooltip: 'تعديل',
                                    onPressed: () => editScale(i),
                                  ),
                                  IconButton(
                                    icon: const Icon(PhosphorIconsBold.trash, size: 16),
                                    color: AppColors.error, tooltip: 'حذف',
                                    onPressed: () => deleteScale(i),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
