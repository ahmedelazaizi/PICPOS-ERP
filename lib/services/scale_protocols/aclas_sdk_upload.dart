// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

// AclasSDK unified upload (all brands, IP-only)

extension _AclasSdkUpload on ScaleProtocolHandler {
  // ═══════════════════════════════════════════════════════════════
  // AclasSDK — Unified IP-Only Upload (all brands)
  // ═══════════════════════════════════════════════════════════════
  // Uses AclasSDK.dll for auto-detection via UDP.
  // Works with any Aclas-compatible scale (Rongta, NVK, TEM, Aclas,
  // CAS CL-series, DIGI SM-series, etc.) — no port needed.
  // ═══════════════════════════════════════════════════════════════

  Future<PLUUploadResult> _uploadViaAclasSDK(
    List<ScalePLUItem> items,
    String? ip, {
    int? customUdpPort,
  }) async {
    final effectiveIp = ip ?? '192.168.1.100';

    logger?.info('AclasSDK — ترحيل موحّد عبر IP فقط ($effectiveIp)');
    logger?.info('تسلسل الترحيل: الأقسام → الوحدات → المجموعات → PLU → مفاتيح الاختصار');

    final tempDir = Directory.systemTemp;
    final ts = DateTime.now().millisecondsSinceEpoch;

    // ── Step 1: Collect prerequisite IDs from PLU items ──
    logger?.section('إنشاء ملفات البيانات');

    // Collect unique department IDs referenced by PLU items
    final deptIds = items.map((e) => e.department).toSet();
    final departments = deptIds.map((id) => AclasDepartment(
      id: id,
      name: 'قسم $id',
    )).toList();

    // Collect unique unit IDs referenced by PLU items
    final unitIds = items.map((e) => e.isByWeight ? 4 : 10).toSet();
    final units = <AclasUnit>[];
    // Standard Aclas unit table — include all common units
    final standardUnits = {
      1: 'g',     // gram
      2: '100g',  // 100 grams
      3: 'lb',    // pound
      4: 'kg',    // kilogram
      5: 'oz',    // ounce
      10: 'pcs',  // pieces/count
      11: 'bag',  // bag
      12: 'box',  // box
    };
    for (final uid in unitIds) {
      units.add(AclasUnit(
        id: uid,
        name: standardUnits[uid] ?? 'unit$uid',
      ));
    }
    // Always include kg(4) and pcs(10) — the two most common
    if (!unitIds.contains(4)) {
      units.add(AclasUnit(id: 4, name: 'kg'));
    }
    if (!unitIds.contains(10)) {
      units.add(AclasUnit(id: 10, name: 'pcs'));
    }

    // Default group (GroupID=1 used in PLU file)
    final groups = [AclasGroup(id: 1, name: 'عام')];

    // ── Generate Department file ──
    final deptFilePath = '${tempDir.path}\\aclas_dept_upload_$ts.txt';
    await AclasSDK.generateDepartmentFile(departments, deptFilePath);
    logger?.info('ملف الأقسام: $deptFilePath (${departments.length} قسم: ${deptIds.join(", ")})');

    // ── Generate Unit file ──
    final unitFilePath = '${tempDir.path}\\aclas_unit_upload_$ts.txt';
    await AclasSDK.generateUnitFile(units, unitFilePath);
    logger?.info('ملف الوحدات: $unitFilePath (${units.length} وحدة: ${units.map((u) => '${u.id}=${u.name}').join(", ")})');

    // ── Generate Group file ──
    final groupFilePath = '${tempDir.path}\\aclas_group_upload_$ts.txt';
    await AclasSDK.generateGroupFile(groups, groupFilePath);
    logger?.info('ملف المجموعات: $groupFilePath (${groups.length} مجموعة)');

    // ── Generate PLU file ──
    // ItemCode = the product's actual code/SKU from the POS (e.g. "10001")
    // NOT the sequential PLU number. The scale's firmware displays the
    // ItemCode field as-is — if we pass a numeric "1" it pads/truncates it;
    // passing "10001" preserves the full 5-digit code.
    // Falls back to PLU number string only if the product has no code set.
    final pluItems = items.map((item) => AclasPLUItem(
      id: item.pluNumber,
      itemCode: (item.productCode != null && item.productCode!.isNotEmpty)
          ? item.productCode!
          : item.pluNumber.toString(),
      departmentId: item.department,
      name: item.name,
      price: item.unitPrice,
      unitId: (item.isByWeight) ? 4 : 10,  // 4=kg, 10=pcs
      barcodeType1: 7,
      barcodeType2: 7,
      tareWeight: item.tareWeight,
    )).toList();
    final pluFilePath = '${tempDir.path}\\aclas_plu_upload_$ts.txt';
    await AclasSDK.generatePLUFile(pluItems, pluFilePath);
    logger?.info('ملف PLU: $pluFilePath (${items.length} صنف)');

    // ── Generate HotKey file ──
    // KeyNo is the PHYSICAL button position (1, 2, 3, ...) — NOT the PLU number.
    // Scales vary: 24 (4×6), 56 (7×8), 112 (14×8). buildSequentialMappings
    // auto-wraps to Mode pages (0, 1, 2...) when items > buttonsPerPage,
    // so Shift/Page buttons on the scale access the additional layers.
    // Default 112 works for the largest common layout; the scale silently
    // ignores higher keyNos on smaller keyboards.
    final pluIds = items.map((e) => e.pluNumber).toList();
    final hotKeyMappings = AclasHotKeyMapping.buildSequentialMappings(pluIds);
    final hotKeyFilePath = '${tempDir.path}\\aclas_hotkey_upload_$ts.txt';
    await AclasSDK.generateHotKeyFile(hotKeyMappings, hotKeyFilePath);
    logger?.info('ملف HotKey: $hotKeyFilePath (${hotKeyMappings.length} مفتاح)');
    logger?.info('  التوزيع: ${hotKeyMappings.take(12).map((m) => "صفحة${m.mode}·زر${m.keyNo}→PLU${m.pluId}").join(", ")}');

    // ── Generate per-item PLU files (for retry fallback only) ──
    // If the batch upload has missing records after verification, the
    // isolate re-uploads each item with its own dedicated SDK task. This
    // bypasses firmware bugs that silently drop records in large batches.
    final perItemFiles = <String>[];
    for (int i = 0; i < pluItems.length; i++) {
      final path = '${tempDir.path}\\aclas_plu_item_${ts}_$i.txt';
      await AclasSDK.generatePLUFile([pluItems[i]], path);
      perItemFiles.add(path);
    }
    logger?.info('تم إنشاء ${perItemFiles.length} ملف إحتياطى (retry)');

    // ── Check prerequisite cache ──
    final cacheKey = '$effectiveIp:${customUdpPort ?? 0}';
    final prereqHash = _computePrereqHash(deptIds, unitIds);
    final skipPrereqs = _prereqCached(cacheKey, prereqHash);
    if (skipPrereqs) {
      logger?.info('⚡ الأقسام/الوحدات مخزّنة مسبقاً لهذا الميزان — '
          'تخطى مرحلة المتطلبات (توفير ~8 ثوانى)');
    }

    // ── Detect + Upload full sequence in background isolate ──
    logger?.section('كشف وترحيل (background isolate)');
    logger?.info('تشغيل AclasSDK في خيط خلفي — الواجهة تبقى مستجيبة...');
    if (!skipPrereqs) {
      logger?.info('التسلسل: Department → Unit → Group → PLU → HotKey');
    } else {
      logger?.info('التسلسل: PLU → HotKey (المتطلبات مخزّنة)');
    }
    onProgress?.call(0, items.length);

    try {
      // Assemble isolate args. The layout is positional (see _aclasUploadInIsolate):
      //   0: ip, 1: pluBatch, 2: hotKey, 3: dept, 4: unit, 5: group,
      //   6: customPort, 7: skipPrereqs, 8: expectedCount, 9..N: per-item PLU files
      final isolateArgs = <String>[
        effectiveIp,
        pluFilePath,
        hotKeyFilePath,
        deptFilePath,
        unitFilePath,
        groupFilePath,
        customUdpPort?.toString() ?? '',
        skipPrereqs ? '1' : '0',
        items.length.toString(),
        ...perItemFiles,
      ];

      // Guard against a wedged AclasSDK WaitForTask. The upload runs in a
      // background isolate, but _waitForTask (aclas_sdk_ffi.dart) is a BLOCKING
      // UDP FFI call with no native timeout — if the scale is unplugged, on the
      // wrong port, or unresponsive, that isolate blocks and this await would
      // otherwise never complete, freezing the whole export ("النظام علق تعليق
      // كامل بعد ترحيل الأصناف للميزان"). Bound it: the budget scales with the
      // record count (a real upload of N PLU records takes proportional time)
      // with a 45s floor for detect + prereq sequence. On timeout the UI
      // recovers with an actionable error; the leaked isolate finishes when the
      // SDK's own UDP timeout fires (or on process exit). The scale path emitted
      // NOTHING to the diagnostic log before — hence this hang was invisible in
      // the field logs — so log the start and the timeout for traceability.
      final uploadBudget = Duration(
        seconds: (45 + items.length ~/ 2).clamp(45, 900),
      );
      await DiagnosticLogger.log(
        DiagnosticLogger.plu,
        'aclas upload START ip=$effectiveIp items=${items.length} '
        'budget=${uploadBudget.inSeconds}s skipPrereqs=$skipPrereqs',
      );
      final Map<String, dynamic> raw;
      try {
        raw = await Isolate.run(
          () => _aclasUploadInIsolate(isolateArgs),
        ).timeout(uploadBudget);
      } on TimeoutException {
        logger?.error(
            'انتهت مهلة الترحيل (${uploadBudget.inSeconds}ث) — الميزان لم يستجب. '
            'تأكد من توصيل الميزان وصحة المنفذ ثم أعد المحاولة.');
        await DiagnosticLogger.log(
          DiagnosticLogger.plu,
          'aclas upload TIMEOUT after ${uploadBudget.inSeconds}s '
          'ip=$effectiveIp items=${items.length} — WaitForTask wedged',
        );
        return PLUUploadResult(
          total: items.length,
          success: 0,
          failed: items.length,
          errors: [
            'انتهت مهلة الترحيل — الميزان لم يستجب خلال ${uploadBudget.inSeconds} ثانية. '
            'تأكد من توصيل الميزان وصحة المنفذ (UDP) ثم أعد المحاولة.'
          ],
        );
      }

      final sdkSuccess = raw['success'] == true;
      final message = raw['message']?.toString() ?? '';
      final uploadedCount = raw['uploadedCount'] is int
          ? raw['uploadedCount'] as int
          : items.length;
      final expectedCount = raw['expectedCount'] is int
          ? raw['expectedCount'] as int
          : items.length;
      final retriedOk = raw['retriedOk'] is int ? raw['retriedOk'] as int : 0;
      final retriedFail = raw['retriedFail'] is int ? raw['retriedFail'] as int : 0;

      // Record successful prereq upload in cache (if it ran)
      if (!skipPrereqs && sdkSuccess) {
        _recordPrereqUploaded(cacheKey, prereqHash);
      }

      onProgress?.call(items.length, items.length);

      if (retriedOk > 0 || retriedFail > 0) {
        logger?.info('إعادة المحاولة الفردية: $retriedOk نجح، $retriedFail فشل');
      }

      if (sdkSuccess) {
        logger?.success('تم الترحيل بنجاح! ($uploadedCount/$expectedCount صنف) '
            '(${raw['protocol'] ?? '-'} / UDP:${raw['port'] ?? '-'})');
        logger?.info('التفاصيل: $message');
        return PLUUploadResult(
          total: items.length,
          success: uploadedCount,
          failed: items.length - uploadedCount,
        );
      } else {
        // Partial success is possible: some records persisted, some didn't
        final errors = <String>[message];
        if (uploadedCount > 0 && uploadedCount < expectedCount) {
          errors.add('الميزان استلم $uploadedCount من $expectedCount أصناف فقط');
        }
        logger?.error('فشل الترحيل الكامل: $message');
        return PLUUploadResult(
          total: items.length,
          success: uploadedCount,
          failed: items.length - uploadedCount,
          errors: errors,
        );
      }
    } finally {
      // Clean up all temp files (including per-item retry files)
      for (final path in [pluFilePath, hotKeyFilePath, deptFilePath, unitFilePath, groupFilePath, ...perItemFiles]) {
        try { await File(path).delete(); } catch (_) {}
      }
    }
  }
}
