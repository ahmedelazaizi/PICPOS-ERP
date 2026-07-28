part of 'scale_plu_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SCALE PLU (PicPos fork) — Logic: Export, Verify, CRUD, Dialogs, Barcode
// Settings
//
// Copied verbatim from `lib/presentation/screens/scale_plu/scale_logic.dart`
// (`_ScaleLogicMixin`). Only the `part of` target and the mixin name
// changed — see the copy-trap note in `scale_plu_picpos_screen.dart`.
//
// Bug-9 (barcode prefix): the fix lives right here, unchanged from source —
// `prefix` is `weightPrefix` ('scale_weight_prefix', default '21') for
// weight-sold items or `pricePrefix` ('scale_price_prefix', default '20')
// otherwise, and `scaleItemIsSoldByWeight(...)` treats `weightByPiece` as
// NOT sold by weight. See `exportToScale()` below and the twin logic in
// `scale_panels_picpos.dart`'s `_showDataPreview()`.
// ═══════════════════════════════════════════════════════════════════════════

mixin _ScaleLogicPicposMixin on ConsumerState<ScalePluPicposScreen> {
  // Abstract — provided by the shell
  List<LabelScale> get scales;
  set scales(List<LabelScale> val);
  int get selectedScaleIndex;
  set selectedScaleIndex(int val);
  Set<int> get selectedCategoryIds;
  Set<int> get selectedProductIds;
  bool get isExporting;
  set isExporting(bool val);
  String get searchQuery;
  Future<void> loadScales();

  IScaleRepository get _scaleRepo => ref.read(scaleRepositoryProvider);
  ISettingsRepository get _settingsRepo => ref.read(settingsRepositoryProvider);

  List<ProductEntity> filterProducts(List<ProductEntity> all) {
    var filtered = all
        .where(
          (p) =>
              p.scaleType == 'weight' ||
              p.scaleType == 'weightByPiece' ||
              p.scaleType == 'display' ||
              p.isSoldByWeight,
        )
        .toList();
// ... (rest of the filterProducts logic remains same)
    if (selectedCategoryIds.isNotEmpty) {
      filtered = filtered
          .where(
            (p) =>
                p.categoryId != null &&
                selectedCategoryIds.contains(p.categoryId),
          )
          .toList();
    }

    if (searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (p) =>
                p.name.contains(searchQuery) ||
                p.code.contains(searchQuery) ||
                (p.scalePluNumber?.toString().contains(searchQuery) ?? false),
          )
          .toList();
    }

    return filtered;
  }

  void selectAllVisible() {
    final products = ref.read(allProductsProvider).value ?? [];
    final filtered = filterProducts(products);
    setState(() {
      if (selectedProductIds.length == filtered.length) {
        selectedProductIds.clear();
      } else {
        selectedProductIds.clear();
        selectedProductIds.addAll(filtered.map((p) => p.id));
      }
    });
  }

  Future<void> exportToScale() async {
    if (selectedScaleIndex < 0 || selectedScaleIndex >= scales.length) {
      if (mounted) {
        AppToast.show(context, 'اختر ميزان أولاً', type: ToastType.warning);
      }
      return;
    }

    final scale = scales[selectedScaleIndex];
    if (!scale.isActive) {
      if (mounted) {
        AppToast.show(context, 'الميزان المحدد غير مفعّل', type: ToastType.warning);
      }
      return;
    }

    // Validate connection settings before attempting
    final conn = LabelScaleService.connectionFromString(scale.connectionType);
    if ((conn == LabelScaleConnection.tcp || conn == LabelScaleConnection.aclasSDK) && (scale.ipAddress == null || scale.ipAddress!.isEmpty)) {
      if (mounted) AppToast.show(context, 'يجب إدخال عنوان IP للميزان "${scale.name}" أولاً', type: ToastType.error);
      return;
    }
    if (conn == LabelScaleConnection.serial && (scale.comPort == null || scale.comPort!.isEmpty)) {
      if (mounted) AppToast.show(context, 'يجب إدخال منفذ COM للميزان "${scale.name}" أولاً', type: ToastType.error);
      return;
    }

    if (selectedProductIds.isEmpty) {
      if (mounted) {
        AppToast.show(context, 'حدد أصناف للترحيل أولاً', type: ToastType.warning);
      }
      return;
    }

    setState(() => isExporting = true);

    try {
      final products = ref.read(allProductsProvider).value ?? [];
      final selectedProducts = products
          .where((p) => selectedProductIds.contains(p.id))
          .toList();

      if (selectedProducts.isEmpty) {
        if (mounted) {
          AppToast.show(context, 'لم يتم العثور على الأصناف المحددة', type: ToastType.warning);
        }
        return;
      }

      // Load barcode settings
      final weightPrefix = await _settingsRepo.getSetting('scale_weight_prefix') ?? '21';
      final pricePrefix = await _settingsRepo.getSetting('scale_price_prefix') ?? '20';
      final codeLen = int.tryParse(await _settingsRepo.getSetting('scale_weight_item_code_len') ?? '5') ?? 5;

      final maxPlu = scale.maxPlu > 0 ? scale.maxPlu : 500;
      final pluItems = <ScalePLUItem>[];
      for (final p in selectedProducts) {
        final pluNumber = p.scalePluNumber ?? p.id;
        if (pluNumber < 1 || pluNumber > maxPlu) {
          debugPrint('[ScaleExport] Skipping product ${p.name}: PLU $pluNumber out of valid range (1-$maxPlu)');
          continue;
        }

        final isByWeight = scaleItemIsSoldByWeight(
          scaleType: p.scaleType,
          isSoldByWeight: p.isSoldByWeight,
        );
        final prefix = isByWeight ? weightPrefix : pricePrefix;
        final scaleBarcode = '$prefix${pluNumber.toString().padLeft(codeLen, '0')}';

        pluItems.add(
          ScalePLUItem(
            pluNumber: pluNumber,
            name: p.name,
            unitPrice: p.pricePerUnit ?? p.salePrice,
            isByWeight: isByWeight,
            department: isByWeight ? int.tryParse(weightPrefix) ?? 21 : int.tryParse(pricePrefix) ?? 20,
            barcode: scaleBarcode,
            productCode: p.code,
          ),
        );
      }

      if (pluItems.isEmpty) {
        if (mounted) {
          AppToast.show(context, 'لم يتم العثور على أصناف صالحة للترحيل (تحقق من أرقام الـ PLU)', type: ToastType.warning);
        }
        setState(() => isExporting = false);
        return;
      }

      // Warn if exceeding scale's PLU capacity
      if (pluItems.length > maxPlu) {
        debugPrint('[ScaleExport] Warning: ${pluItems.length} items exceed maxPlu=$maxPlu for scale "${scale.name}"');
        if (mounted) {
          AppToast.show(context, 'تحذير: عدد الأصناف (${pluItems.length}) يتجاوز سعة الميزان ($maxPlu) — سيتم إرسال أول $maxPlu صنف فقط', type: ToastType.warning);
        }
        pluItems.removeRange(maxPlu, pluItems.length);
      }

      // ── Handle CSV file export mode separately ──
      final conn = LabelScaleService.connectionFromString(scale.connectionType);
      if (conn == LabelScaleConnection.file) {
        await _exportCSVFile(scale, pluItems);
        return;
      }

      final result = await _scaleRepo.syncToScale(scale, pluItems);

      debugPrint('[ScaleExport] Result: ${result.success}/${result.total} success, ${result.failed} failed');
      if (result.errors.isNotEmpty) {
        debugPrint('[ScaleExport] Errors: ${result.errors.join("; ")}');
      }

      if (mounted) {
        if (result.failed == 0 && result.success > 0) {
          AppToast.show(context, 'تم ترحيل ${result.success} صنف بنجاح إلى ${scale.name}', type: ToastType.success);
        } else if (result.success == 0) {
          final brand = LabelScaleService.brandFromString(scale.brand);
          _showExportErrorDialog(scale, brand, conn, result);
        } else {
          AppToast.show(context, 'تم ترحيل ${result.success} من ${result.total} — فشل ${result.failed}', type: ToastType.warning);
        }
      }
    } catch (e, stack) {
      debugPrint('[ScaleExport] EXCEPTION: $e');
      debugPrint('[ScaleExport] Stack: $stack');
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(PhosphorIconsBold.warning, color: AppColors.error),
                SizedBox(width: 8),
                Text('فشل الترحيل'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الميزان: ${scale.name}'),
                Text('IP: ${scale.ipAddress}:${scale.port}'),
                const SizedBox(height: 12),
                const Text('تفاصيل الخطأ:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                  ),
                  child: Text('$e', style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً')),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isExporting = false);
    }
  }

  void _showExportErrorDialog(
    LabelScale scale,
    LabelScaleBrand brand,
    LabelScaleConnection connection,
    PLUUploadResult result,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.warning, color: AppColors.error),
            SizedBox(width: 8),
            Text('فشل ترحيل جميع الأصناف'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الميزان: ${scale.name}'),
            Text('العلامة التجارية: ${brand.name.toUpperCase()}'),
            Text('نوع الاتصال: ${connection == LabelScaleConnection.tcp ? "TCP/IP" : "Serial"}'),
            Text('IP: ${scale.ipAddress}:${scale.port}'),
            const SizedBox(height: 12),
            Text('الأصناف: ${result.total} — نجاح: ${result.success} — فشل: ${result.failed}'),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('الأخطاء:', style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(result.errors.join('\n'), style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'تأكد من:\n• الميزان متصل بالشبكة\n• عنوان IP والمنفذ صحيح\n• العلامة التجارية مطابقة للميزان',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً')),
        ],
      ),
    );
  }

  Future<void> verifyConnection() async {
    if (selectedScaleIndex < 0 || selectedScaleIndex >= scales.length) {
      if (mounted) {
        AppToast.show(context, 'اختر ميزان أولاً', type: ToastType.warning);
      }
      return;
    }

    final scale = scales[selectedScaleIndex];
    if (mounted) {
      AppToast.show(context, 'جاري اختبار الاتصال بـ ${scale.ipAddress}:${scale.port}...', type: ToastType.info);
    }

    try {
      final result = await _scaleRepo.testConnection(scale);

      if (mounted) {
        if (result['success'] == true) {
          AppToast.show(context, 'الاتصال بـ ${scale.name} ناجح ✓', type: ToastType.success);
        } else {
          AppToast.show(context, 'فشل الاتصال: ${result['error'] ?? 'غير معروف'}', type: ToastType.error);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل الاتصال — $e', type: ToastType.error);
      }
    }
  }

  void addScale() {
    showScaleDialog();
  }

  void editScale(int index) {
    showScaleDialog(existingIndex: index);
  }

  void deleteScale(int index) {
    final scale = scales[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الميزان'),
        content: Text('هل تريد حذف "${scale.name}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _scaleRepo.deleteScale(scale.id);
              await loadScales();
              if (selectedScaleIndex >= scales.length) {
                setState(() => selectedScaleIndex = scales.isEmpty ? -1 : scales.length - 1);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  static const _brandOptions = {
    'cas': 'CAS (CL5000/CL5200)', 'digi': 'DIGI (SM-100/SM-120)',
    'aclas': 'ACLAS (LS2X/LS6X)', 'rongta': 'Rongta (RLS1100)',
    'mettlerToledo': 'Mettler Toledo (bPlus)', 'tem': 'TEM',
    'dibal': 'Dibal (G310)', 'nvkTma': 'NVK TMA',
  };

  static const _defaultBrandPorts = {
    'cas': 20304, 'digi': 3001, 'rongta': 9100, 'aclas': 8000,
    'mettlerToledo': 252, 'tem': 9100, 'dibal': 3000, 'nvkTma': 8000,
  };

  static const _baudRates = [2400, 4800, 9600, 19200, 38400, 57600, 115200];

  void showScaleDialog({int? existingIndex}) {
    final isEdit = existingIndex != null;
    final existing = isEdit ? scales[existingIndex] : null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final ipCtrl = TextEditingController(text: existing?.ipAddress ?? '192.168.1.90');
    final portCtrl = TextEditingController(text: '${existing?.port ?? 20304}');
    final maxPluCtrl = TextEditingController(text: '${existing?.maxPlu ?? 500}');
    final ftpUserCtrl = TextEditingController(text: existing?.ftpUsername ?? 'anonymous');
    final ftpPassCtrl = TextEditingController(text: existing?.ftpPassword ?? '');
    final comPortCtrl = TextEditingController(text: existing?.comPort ?? 'COM3');
    String selectedBrand = existing?.brand ?? 'cas';
    String selectedConnection = existing?.connectionType ?? 'tcp';
    int selectedBaudRate = existing?.baudRate ?? 9600;
    int selectedDataBits = existing?.dataBits ?? 8;
    String selectedParity = existing?.parity ?? 'none';
    String selectedStopBits = existing?.stopBits ?? 'one';
    String selectedHandshake = existing?.handShake ?? 'none';
    bool isTesting = false;
    bool isScanning = false;
    String? testResult;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Helper to build a LabelScale from current dialog state
          LabelScale buildScaleFromDialog() => LabelScale(
            id: existing?.id ?? 0,
            name: nameCtrl.text.isEmpty ? 'ميزان ${scales.length + 1}' : nameCtrl.text,
            brand: selectedBrand,
            connectionType: selectedConnection,
            ipAddress: ipCtrl.text.isEmpty ? null : ipCtrl.text,
            port: int.tryParse(portCtrl.text) ?? (_defaultBrandPorts[selectedBrand] ?? 20304),
            comPort: comPortCtrl.text.isEmpty ? null : comPortCtrl.text,
            maxPlu: int.tryParse(maxPluCtrl.text) ?? 500,
            ftpUsername: selectedConnection == 'ftp' ? ftpUserCtrl.text : null,
            ftpPassword: selectedConnection == 'ftp' ? ftpPassCtrl.text : null,
            isActive: true,
            baudRate: selectedBaudRate,
            dataBits: selectedDataBits,
            parity: selectedParity,
            stopBits: selectedStopBits,
            handShake: selectedHandshake,
            createdAt: existing?.createdAt ?? DateTime.now(),
          );

          return AlertDialog(
          title: Row(
            children: [
              Icon(isEdit ? PhosphorIconsBold.pencilSimple : PhosphorIconsBold.plusCircle, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(isEdit ? 'تعديل ميزان' : 'إضافة ميزان جديد'),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Basic Info ──
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'اسم الميزان', hintText: 'مثال: ميزان ديلي', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(PhosphorIconsBold.tag, size: 18)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedBrand,
                    decoration: const InputDecoration(labelText: 'العلامة التجارية', border: OutlineInputBorder(), isDense: true),
                    items: _brandOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() {
                        selectedBrand = v;
                        // Auto-update port to brand default
                        final defaultPort = _defaultBrandPorts[v] ?? 20304;
                        portCtrl.text = '$defaultPort';
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedConnection,
                    decoration: const InputDecoration(labelText: 'طريقة الاتصال', border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'aclassdk', child: Text('AclasSDK — كشف تلقائي بالـ IP فقط')),
                      DropdownMenuItem(value: 'tcp', child: Text('TCP/IP (شبكة)')),
                      DropdownMenuItem(value: 'serial', child: Text('Serial (COM)')),
                      DropdownMenuItem(value: 'ftp', child: Text('FTP (رفع ملف)')),
                      DropdownMenuItem(value: 'file', child: Text('تصدير ملف CSV')),
                    ],
                    onChanged: (v) => setDialogState(() { selectedConnection = v ?? 'tcp'; testResult = null; }),
                  ),

                  // ── AclasSDK: IP-only auto-detect ──
                  if (selectedConnection == 'aclassdk') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: ipCtrl,
                      decoration: const InputDecoration(labelText: 'عنوان IP', hintText: '192.168.1.90', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(PhosphorIconsBold.globe, size: 18)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.success.withValues(alpha: 0.3))),
                      child: const Row(children: [
                        Icon(PhosphorIconsBold.info, size: 16, color: AppColors.success), SizedBox(width: 8),
                        Expanded(child: Text('يكفي إدخال عنوان IP فقط. النظام يكتشف الميزان والبروتوكول تلقائياً عبر AclasSDK.', style: TextStyle(fontSize: 12, color: AppColors.success))),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: isScanning
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                        label: Text(isScanning ? 'جاري الكشف...' : 'اكتشاف الميزان'),
                        onPressed: isScanning ? null : () async {
                          final ip = ipCtrl.text.trim();
                          if (ip.isEmpty) { AppToast.show(ctx, 'أدخل عنوان IP أولاً', type: ToastType.info); return; }
                          setDialogState(() { isScanning = true; testResult = null; });
                          try {
                            final result = await LabelScaleService.instance.testConnection(
                              brand: LabelScaleService.brandFromString(selectedBrand),
                              connection: LabelScaleConnection.aclasSDK,
                              ipAddress: ip,
                            );
                            if (ctx.mounted) {
                              if (result['success'] == true) {
                                setDialogState(() => testResult = 'تم كشف الميزان بنجاح!\n'
                                    'البروتوكول: ${result['protocol'] ?? '-'} | المنفذ: ${result['port'] ?? '-'} | أقصى PLU: ${result['maxPlu'] ?? '-'}');
                              } else {
                                final errDetail = result['error']?.toString() ?? 'لم يتم العثور على الميزان';
                                setDialogState(() => testResult = '$errDetail\nتأكد من: (1) AclasSDK.dll موجود بجوار البرنامج  (2) الميزان مُشغّل  (3) الـ IP صحيح');
                              }
                            }
                          } catch (e) {
                            if (ctx.mounted) setDialogState(() => testResult = 'خطأ: $e');
                          } finally {
                            if (ctx.mounted) setDialogState(() => isScanning = false);
                          }
                        },
                      ),
                    ),
                  ],

                  // ── TCP/FTP Settings ──
                  if (selectedConnection == 'tcp' || selectedConnection == 'ftp') ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(flex: 2, child: TextField(
                        controller: ipCtrl,
                        decoration: const InputDecoration(labelText: 'عنوان IP', hintText: '192.168.1.90', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(PhosphorIconsBold.globe, size: 18)),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(
                        controller: portCtrl,
                        decoration: InputDecoration(
                          labelText: 'المنفذ',
                          hintText: '${_defaultBrandPorts[selectedBrand] ?? 20304}',
                          border: const OutlineInputBorder(), isDense: true,
                          suffixIcon: isScanning
                              ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                              : IconButton(
                                  icon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                                  tooltip: 'بحث تلقائي عن المنفذ',
                                  onPressed: () async {
                                    final ip = ipCtrl.text.trim();
                                    if (ip.isEmpty) { AppToast.show(ctx, 'أدخل عنوان IP أولاً', type: ToastType.info); return; }
                                    setDialogState(() { isScanning = true; testResult = null; });
                                    try {
                                      final brand = LabelScaleService.brandFromString(selectedBrand);
                                      final ports = await LabelScaleService.instance.scanForOpenPort(ip, brand: brand);
                                      if (ctx.mounted) {
                                        if (ports.isEmpty) {
                                          setDialogState(() => testResult = 'لم يتم العثور على منافذ مفتوحة على $ip — أدخل رقم المنفذ يدوياً واضغط اختبار الاتصال');
                                        } else {
                                          setDialogState(() {
                                            portCtrl.text = '${ports.first}';
                                            testResult = 'تم العثور على ${ports.length == 1 ? "المنفذ: ${ports.first}" : "منافذ: ${ports.join(", ")} — تم اختيار ${ports.first}"}';
                                          });
                                        }
                                      }
                                    } catch (e) {
                                      if (ctx.mounted) setDialogState(() => testResult = 'خطأ أثناء البحث: $e');
                                    } finally {
                                      if (ctx.mounted) setDialogState(() => isScanning = false);
                                    }
                                  },
                                ),
                        ),
                        keyboardType: TextInputType.number,
                      )),
                    ]),
                  ],

                  // ── FTP Credentials ──
                  if (selectedConnection == 'ftp') ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: TextField(controller: ftpUserCtrl, decoration: const InputDecoration(labelText: 'مستخدم FTP', border: OutlineInputBorder(), isDense: true))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: ftpPassCtrl, decoration: const InputDecoration(labelText: 'كلمة مرور FTP', border: OutlineInputBorder(), isDense: true), obscureText: true)),
                    ]),
                  ],

                  // ── Serial Settings ──
                  if (selectedConnection == 'serial') ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: TextField(
                        controller: comPortCtrl,
                        decoration: const InputDecoration(labelText: 'منفذ COM', hintText: 'COM3', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(PhosphorIconsBold.plugs, size: 18)),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: DropdownButtonFormField<int>(
                        value: selectedBaudRate,
                        decoration: const InputDecoration(labelText: 'سرعة الاتصال', border: OutlineInputBorder(), isDense: true),
                        items: _baudRates.map((r) => DropdownMenuItem(value: r, child: Text('$r'))).toList(),
                        onChanged: (v) => setDialogState(() => selectedBaudRate = v ?? 9600),
                      )),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: DropdownButtonFormField<int>(
                        value: selectedDataBits,
                        decoration: const InputDecoration(labelText: 'Data Bits', border: OutlineInputBorder(), isDense: true),
                        items: [5, 6, 7, 8].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                        onChanged: (v) => setDialogState(() => selectedDataBits = v ?? 8),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: DropdownButtonFormField<String>(
                        value: selectedParity,
                        decoration: const InputDecoration(labelText: 'Parity', border: OutlineInputBorder(), isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('None')),
                          DropdownMenuItem(value: 'odd', child: Text('Odd')),
                          DropdownMenuItem(value: 'even', child: Text('Even')),
                        ],
                        onChanged: (v) => setDialogState(() => selectedParity = v ?? 'none'),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: DropdownButtonFormField<String>(
                        value: selectedStopBits,
                        decoration: const InputDecoration(labelText: 'Stop Bits', border: OutlineInputBorder(), isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'one', child: Text('1')),
                          DropdownMenuItem(value: 'two', child: Text('2')),
                          DropdownMenuItem(value: 'onePointFive', child: Text('1.5')),
                        ],
                        onChanged: (v) => setDialogState(() => selectedStopBits = v ?? 'one'),
                      )),
                    ]),
                  ],

                  // ── Max PLU ──
                  const SizedBox(height: 12),
                  TextField(controller: maxPluCtrl, decoration: const InputDecoration(labelText: 'سعة PLU القصوى', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number),

                  // ── File mode info ──
                  if (selectedConnection == 'file') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.info.withValues(alpha: 0.3))),
                      child: const Row(children: [
                        Icon(PhosphorIconsBold.info, size: 16, color: AppColors.info), SizedBox(width: 8),
                        Expanded(child: Text('سيتم تصدير ملف CSV يمكن استيراده في برنامج PLU Manager الخاص بالميزان', style: TextStyle(fontSize: 12, color: AppColors.info))),
                      ]),
                    ),
                  ],

                  // ── Test Connection & Scan ──
                  if (selectedConnection != 'file') ...[
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(
                        onPressed: isTesting ? null : () async {
                          setDialogState(() { isTesting = true; testResult = null; });
                          try {
                            final scale = buildScaleFromDialog();
                            final result = await _scaleRepo.testConnection(scale);
                            if (ctx.mounted) {
                              final ok = result['success'] == true;
                              setDialogState(() => testResult = ok ? 'الاتصال ناجح ✓' : 'فشل: ${result['error'] ?? 'غير معروف'}');
                            }
                          } catch (e) {
                            if (ctx.mounted) setDialogState(() => testResult = 'خطأ: $e');
                          } finally {
                            if (ctx.mounted) setDialogState(() => isTesting = false);
                          }
                        },
                        icon: isTesting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(PhosphorIconsBold.plugsConnected, size: 16),
                        label: const Text('اختبار الاتصال', style: TextStyle(fontSize: 12)),
                      )),
                      if (isEdit) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: ctx,
                              builder: (c) => Directionality(
                                textDirection: ui.TextDirection.rtl,
                                child: AlertDialog(
                                  title: const Text('مسح ذاكرة الميزان'),
                                  content: const Text('هل تريد مسح جميع الأصناف المحفوظة على الميزان؟\nهذا الإجراء لا يمكن التراجع عنه.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                                    FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(backgroundColor: AppColors.error), child: const Text('مسح')),
                                  ],
                                ),
                              ),
                            );
                            if (confirmed == true) {
                              final scale = buildScaleFromDialog();
                              final ok = await _scaleRepo.clearScaleMemory(scale);
                              if (ctx.mounted) {
                                setDialogState(() => testResult = ok ? 'تم مسح ذاكرة الميزان ✓' : 'فشل مسح الذاكرة');
                              }
                            }
                          },
                          icon: const Icon(PhosphorIconsBold.trash, size: 16),
                          label: const Text('مسح الذاكرة', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                        ),
                      ],
                    ]),
                    // Test result feedback
                    if (testResult != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: testResult!.contains('✓') ? AppColors.success.withValues(alpha: 0.08) : AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          Icon(testResult!.contains('✓') ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.warningCircle, size: 16,
                            color: testResult!.contains('✓') ? AppColors.success : AppColors.error),
                          const SizedBox(width: 8),
                          Expanded(child: Text(testResult!, style: TextStyle(fontSize: 12, color: testResult!.contains('✓') ? AppColors.success : AppColors.error))),
                        ]),
                      ),
                    ],
                  ],

                  // ── Barcode format settings ──
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(PhosphorIconsBold.barcode, size: 16, color: Colors.deepPurple), SizedBox(width: 8),
                          Text('إعدادات باركود الميزان (EAN-13)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple)),
                        ]),
                        const SizedBox(height: 4),
                        const Text('تحدد كيف يفك POS باركود الميزان عند مسحه بالاسكانر', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 10),
                        FutureBuilder<Map<String, String>>(
                          future: _loadBarcodeSettings(),
                          builder: (ctx2, snap) {
                            final data = snap.data ?? {};
                            final pricePfxCtrl = TextEditingController(text: data['scale_price_prefix'] ?? '20');
                            final weightPfxCtrl = TextEditingController(text: data['scale_weight_prefix'] ?? '21');
                            final pluLenCtrl = TextEditingController(text: data['scale_weight_item_code_len'] ?? '5');
                            final wDivCtrl = TextEditingController(text: data['scale_weight_divider'] ?? '1000');
                            final pDivCtrl = TextEditingController(text: data['scale_price_divider'] ?? '100');
                            return Column(children: [
                              Row(children: [
                                Expanded(child: TextField(controller: pricePfxCtrl, decoration: const InputDecoration(labelText: 'بادئة السعر', hintText: '20', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number, onChanged: (v) => _settingsRepo.saveSetting('scale_price_prefix', v))),
                                const SizedBox(width: 8),
                                Expanded(child: TextField(controller: weightPfxCtrl, decoration: const InputDecoration(labelText: 'بادئة الوزن', hintText: '21', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number, onChanged: (v) => _settingsRepo.saveSetting('scale_weight_prefix', v))),
                                const SizedBox(width: 8),
                                Expanded(child: TextField(controller: pluLenCtrl, decoration: const InputDecoration(labelText: 'طول كود PLU', hintText: '5', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number, onChanged: (v) { _settingsRepo.saveSetting('scale_weight_item_code_len', v); _settingsRepo.saveSetting('scale_price_item_code_len', v); })),
                              ]),
                              const SizedBox(height: 8),
                              Row(children: [
                                Expanded(child: TextField(controller: wDivCtrl, decoration: const InputDecoration(labelText: 'مقسوم الوزن', hintText: '1000', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number, onChanged: (v) => _settingsRepo.saveSetting('scale_weight_divider', v))),
                                const SizedBox(width: 8),
                                Expanded(child: TextField(controller: pDivCtrl, decoration: const InputDecoration(labelText: 'مقسوم السعر', hintText: '100', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number, onChanged: (v) => _settingsRepo.saveSetting('scale_price_divider', v))),
                              ]),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                                child: const Text(
                                  'مثال: 2112345012345\n[21] بادئة  [12345] PLU  [01234] وزن  [5] تحقق\nالوزن = 01234 ÷ 1000 = 1.234 كجم',
                                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.4),
                                ),
                              ),
                            ]);
                          },
                        ),
                      ],
                    ),
                  ),
                  // Brand-specific tips
                  if (selectedBrand == 'rongta' && selectedConnection == 'tcp') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
                      child: const Row(children: [
                        Icon(PhosphorIconsBold.lightbulb, size: 16, color: Colors.orange), SizedBox(width: 8),
                        Expanded(child: Text('لميزان Rongta: يُنصح باستخدام FTP بدلاً من TCP للترحيل المباشر', style: TextStyle(fontSize: 12, color: Colors.orange))),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final labelScale = buildScaleFromDialog();
                await _scaleRepo.saveScale(labelScale);
                await loadScales();
                if (!isEdit) {
                  setState(() => selectedScaleIndex = scales.length - 1);
                }
              },
              child: Text(isEdit ? 'حفظ' : 'إضافة'),
            ),
          ],
        );
        },
      ),
    );
  }

  /// Export PLU items as CSV file (for manual import via PLU Manager software)
  Future<void> _exportCSVFile(LabelScale scale, List<ScalePLUItem> pluItems) async {
    try {
      final brand = LabelScaleService.brandFromString(scale.brand);
      final csvContent = LabelScaleService.instance.generatePLUCsv(
        pluItems, brand: brand,
      );

      // Save to Desktop or user-accessible location
      final desktopPath = '${Platform.environment['USERPROFILE']}\\Desktop';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'PLU_${scale.name.replaceAll(RegExp(r'[^\w]'), '_')}_$timestamp.csv';
      final filePath = '$desktopPath\\$fileName';

      // Write as UTF-16 LE — matches PLU Manager's native TSV format (2.xls)
      final transport = ScaleTransport();
      await File(filePath).writeAsBytes(transport.encodeUtf16LE(csvContent));

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(PhosphorIconsBold.checkCircle, color: AppColors.success),
                SizedBox(width: 8),
                Text('تم تصدير ملف CSV'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تم تصدير ${pluItems.length} صنف بنجاح'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    filePath,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'الخطوة التالية: افتح برنامج PLU Manager الخاص بالميزان واستورد هذا الملف',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Open the folder in Explorer
                  Process.run('explorer.exe', ['/select,', filePath]);
                },
                child: const Text('فتح الموقع'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل تصدير CSV: $e', type: ToastType.error);
      }
    }
  }

  Future<Map<String, String>> _loadBarcodeSettings() async {
    final keys = [
      'scale_price_prefix', 'scale_weight_prefix',
      'scale_weight_item_code_len', 'scale_weight_divider',
      'scale_price_divider', 'scale_price_item_code_len',
    ];
    final map = <String, String>{};
    for (final key in keys) {
      final val = await _settingsRepo.getSetting(key);
      if (val != null) map[key] = val;
    }
    return map;
  }
}
