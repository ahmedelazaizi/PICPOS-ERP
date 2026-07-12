// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
// ═══════════════════════════════════════════════════════════════════════════
// SCALE PROTOCOLS — Brand-specific PLU upload implementations
// ═══════════════════════════════════════════════════════════════════════════
//
// Extracted from LabelScaleService for maintainability (PIR C-01).
// Each brand's upload and record-building methods are grouped together.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:serial_port_win32/serial_port_win32.dart';
import '../core/constants/app_constants.dart';
import 'aclas_sdk_ffi.dart';
import 'label_scale_service.dart';
import 'scale_transport.dart';
import 'scale_upload_logger.dart';
import '../data/database/database.dart' show LabelScale;

// ═══════════════════════════════════════════════════════════════
// AclasSDK Isolate Helper (top-level — required by Isolate.run)
// ═══════════════════════════════════════════════════════════════

/// Runs AclasSDK detect+upload in a background isolate.
/// Inputs are plain strings; output is a plain Map — no FFI objects cross boundaries.
///
/// Full upload sequence (PLU Manager standard):
///   1. Department — prerequisite tables (PLU references DepartmentID)
///   2. Unit       — prerequisite tables (PLU references UnitID)
///   3. PLU        — main product data
///   4. HotKey     — keyboard shortcut mappings
///
/// Without steps 1-2, the scale silently rejects PLU records that reference
/// non-existent department/unit IDs, even though the SDK reports success.
Future<Map<String, dynamic>> _aclasUploadInIsolate(List<String> args) async {
  // args[0] = ip
  // args[1] = pluFilePath                 — main batch file (all items)
  // args[2] = hotKeyFilePath              (optional)
  // args[3] = departmentFilePath          (optional)
  // args[4] = unitFilePath                (optional)
  // args[5] = groupFilePath               (optional)
  // args[6] = customUdpPort               (optional, string; empty = defaults)
  // args[7] = skipPrereqs                 ('1' = skip dept/unit/group upload — cached from prior session)
  // args[8] = expectedPluCount            (string int; for read-back verification)
  // args[9..N] = per-item PLU files       (one per item, for retry fallback if batch count mismatch)
  final ip = args[0];
  final pluFilePath = args[1];
  final hotKeyFilePath = args.length > 2 && args[2].isNotEmpty ? args[2] : null;
  final deptFilePath = args.length > 3 && args[3].isNotEmpty ? args[3] : null;
  final unitFilePath = args.length > 4 && args[4].isNotEmpty ? args[4] : null;
  final groupFilePath = args.length > 5 && args[5].isNotEmpty ? args[5] : null;
  final customPort = args.length > 6 && args[6].isNotEmpty
      ? int.tryParse(args[6])
      : null;
  final skipPrereqs = args.length > 7 && args[7] == '1';
  final expectedCount = args.length > 8 && args[8].isNotEmpty
      ? int.tryParse(args[8]) ?? 0
      : 0;
  final perItemFiles = args.length > 9 ? args.sublist(9) : <String>[];

  if (!AclasSDK.load()) {
    return {'success': false, 'message': 'فشل تحميل AclasSDK.dll — تأكد من وجود الملف'};
  }
  if (!AclasSDK.initialize()) {
    return {'success': false, 'message': 'فشل تهيئة AclasSDK'};
  }
  try {
    // ── Detect device — user-supplied port first, then auto ──
    // Detection via the SDK is SLOW (~2-6 seconds per port due to UDP
    // retries configured in AclasSDK.ini). We limit fallback ports to the
    // two most common Aclas UDP ports to keep total detection time bounded
    // even when the user's configured port is wrong.
    AclasDeviceInfo? device;
    final triedPorts = <int>[];
    if (customPort != null && customPort > 0) {
      device = AclasSDK.getDeviceInfo(ip, port: customPort);
      triedPorts.add(customPort);
    }
    device ??= AclasSDK.getDeviceInfo(ip);  // auto-detect (port=0)
    if (device == null) {
      // Only the two most-common Aclas UDP ports. Total worst-case time
      // with the tightened AclasSDK.ini (TryCount=1, Timeout=1500ms) is
      // ~3 seconds for this loop — vs the previous ~48 seconds for 8 ports.
      for (final p in const [9001, 5001]) {
        if (triedPorts.contains(p)) continue;
        device = AclasSDK.getDeviceInfo(ip, port: p);
        triedPorts.add(p);
        if (device != null) break;
      }
    }
    if (device == null) {
      return {
        'success': false,
        'message': 'لم يتم كشف الميزان في $ip\n'
            'المنافذ التي جُرِّبت: ${triedPorts.join(", ")}\n'
            'تأكد من: (1) الـ IP صحيح  (2) الميزان مُشغّل  (3) AclasSDK.dll موجود\n'
            'إن عرفت منفذ UDP الخاص بميزانك، أدخله يدوياً في إعدادات الميزان.',
      };
    }

    final log = StringBuffer();

    // ── Step 1-2: Prerequisite tables (Department/Unit/Group) ──
    // Can be skipped when the caller has a cached "already uploaded to
    // this scale" flag — saves ~6-9 seconds on repeat upload sessions.
    if (skipPrereqs) {
      log.write('الأقسام/الوحدات/المجموعات (مخزّنة مسبقاً) ⇢ | ');
    } else {
      if (deptFilePath != null) {
        final deptResult = await AclasSDK.uploadDataFile(
          ip, deptFilePath, AclasDataType.department, 'Department',
          deviceInfo: device,
        );
        log.write(deptResult.success ? 'الأقسام ✓ | ' : 'الأقسام ✗ | ');
      }
      if (unitFilePath != null) {
        final unitResult = await AclasSDK.uploadDataFile(
          ip, unitFilePath, AclasDataType.unit, 'Unit',
          deviceInfo: device,
        );
        log.write(unitResult.success ? 'الوحدات ✓ | ' : 'الوحدات ✗ | ');
      }
      if (groupFilePath != null) {
        final groupResult = await AclasSDK.uploadDataFile(
          ip, groupFilePath, AclasDataType.group, 'Group',
          deviceInfo: device,
        );
        log.write(groupResult.success ? 'المجموعات ✓ | ' : 'المجموعات ✗ | ');
      }
    }

    // ══════════════════════════════════════════════════════════════════
    // PLU upload strategy: PER-ITEM SEQUENTIAL (proven reliable)
    // ══════════════════════════════════════════════════════════════════
    // Empirically, Fire Bird / Rongta firmwares accept only the FIRST PLU
    // record per `_execTaskA` task — subsequent records in a batch file
    // are silently dropped. So we upload each item in its own SDK task.
    //
    // With the tightened AclasSDK.ini (SyncTryCount=2, Timeout=1500ms)
    // each per-item upload takes ~1-2 seconds, giving ~12-24 sec total
    // for a 12-item session. Each task's success/failure is authoritative
    // (from the SDK) so we don't need separate read-back verification.
    //
    // TRUE parallelism is not possible: the SDK uses a single internal
    // worker thread and a single UDP socket per `AclasSDK_Initialize`
    // session — concurrent `_execTaskA` calls would corrupt state. The
    // SDK is designed for serial task submission.
    // ══════════════════════════════════════════════════════════════════

    int retriedOk = 0;
    int retriedFail = 0;
    int verifiedCount = 0;
    bool pluPhaseSucceeded = false;

    if (perItemFiles.isNotEmpty) {
      // Primary path: upload each item individually
      log.write('PLU (per-item ×${perItemFiles.length}): ');
      for (int i = 0; i < perItemFiles.length; i++) {
        final r = await AclasSDK.uploadDataFile(
          ip, perItemFiles[i], AclasDataType.plu,
          'PLU #${i + 1}',
          deviceInfo: device,
        );
        if (r.success) {
          retriedOk++;
          verifiedCount++;
        } else {
          retriedFail++;
        }
      }
      pluPhaseSucceeded = retriedOk > 0;
      log.write('$retriedOk نجح، $retriedFail فشل | ');
    } else {
      // Fallback: single-item shortcut (batch file contains only 1 item)
      final pluResult = await AclasSDK.uploadPLU(
        ip, pluFilePath, deviceInfo: device,
      );
      pluPhaseSucceeded = pluResult.success;
      if (pluResult.success) {
        verifiedCount = expectedCount;
        retriedOk = expectedCount;
      } else {
        retriedFail = expectedCount;
      }
      log.write(pluResult.success ? 'PLU ✓ | ' : 'PLU ✗ | ');
    }

    // ── Step 4: HotKey mapping (single batch — works on this firmware) ──
    if (pluPhaseSucceeded && hotKeyFilePath != null) {
      final hkResult = await AclasSDK.uploadHotKeys(
        ip, hotKeyFilePath, deviceInfo: device,
      );
      log.write(hkResult.success ? 'مفاتيح الاختصار ✓' : 'مفاتيح الاختصار ✗');
    }

    // ── Honest success determination ──
    // Overall success = ALL items uploaded successfully.
    final overallSuccess =
        pluPhaseSucceeded && verifiedCount >= expectedCount;

    return {
      'success': overallSuccess,
      'message': 'تم ترحيل $verifiedCount من $expectedCount أصناف\n'
          'تسلسل الترحيل: $log',
      'protocol': device.protocolType,
      'port': device.port,
      'uploadedCount': verifiedCount,
      'expectedCount': expectedCount,
      'retriedOk': retriedOk,
      'retriedFail': retriedFail,
      'skippedPrereqs': skipPrereqs,
    };
  } finally {
    AclasSDK.finalizeSdk();
  }
}

// ═══════════════════════════════════════════════════════════════
// Module-level prerequisite upload cache
// ═══════════════════════════════════════════════════════════════
//
// Dept/Unit/Group upload takes ~6-9 seconds. Once uploaded for a given
// scale + set of IDs, we can skip the re-upload for 60 minutes. This
// turns repeat PLU uploads (the common case) from ~20 sec → ~8-10 sec.
//
// Cache key: "ip:port"
// Cache value: hash of uploaded prerequisites (changes if dept/unit IDs
// change, invalidating the skip).

class _PrereqCacheEntry {
  final String hash;
  final DateTime at;
  _PrereqCacheEntry(this.hash, this.at);
}

final Map<String, _PrereqCacheEntry> _aclasPrereqCache = {};

String _computePrereqHash(Set<int> deptIds, Set<int> unitIds) {
  final d = (deptIds.toList()..sort()).join(',');
  final u = (unitIds.toList()..sort()).join(',');
  return 'd=$d|u=$u';
}

/// Returns true if the prereq tables for this scale+IDs combo were
/// uploaded within the last 60 minutes.
bool _prereqCached(String cacheKey, String hash) {
  final entry = _aclasPrereqCache[cacheKey];
  if (entry == null) return false;
  if (entry.hash != hash) return false;
  final ageMinutes = DateTime.now().difference(entry.at).inMinutes;
  return ageMinutes < 60;
}

void _recordPrereqUploaded(String cacheKey, String hash) {
  _aclasPrereqCache[cacheKey] = _PrereqCacheEntry(hash, DateTime.now());
}

/// Handles PLU upload protocol for all supported scale brands.
/// CSV upload framing variant — name + wrapper function.
class _CsvFrame {
  final String name;
  final List<int> Function(List<int> csvBytes) wrap;
  _CsvFrame(this.name, this.wrap);
}

/// Frame wrapper variants tried when uploading PLU to Rongta scales via raw TCP.
/// Different firmwares expect different framing — we try all until one gets ACK.
enum _RongtaFrame {
  /// STX + "0110" + data + ETX + LRC — RLS1000 Software Manual §2.5
  stxCmdDataEtxLrc,
  /// STX + "0110" + data + ETX (no checksum) — some firmwares skip LRC validation
  stxCmdDataEtx,
  /// "0110" + data + CRLF — simplified ASCII line-based
  cmdDataCrLf,
  /// Just data + CRLF — raw PLU record per line (no command code)
  dataCrLf,
}

class ScaleProtocolHandler {
  final ScaleTransport transport;

  /// Current upload logger (set per upload session)
  ScaleUploadLogger? logger;

  ScaleProtocolHandler(this.transport);

  /// Progress callback: (current, total) — called after each PLU is sent.
  void Function(int current, int total)? onProgress;

  /// Upload items using the appropriate brand protocol.
  /// Tries universal CSV-over-TCP first (works with most modern scales),
  /// then falls back to brand-specific binary protocol.
  Future<PLUUploadResult> upload({
    required LabelScaleBrand brand,
    required LabelScaleConnection connection,
    required List<ScalePLUItem> items,
    String? ip,
    int? port,
    String? com,
    int? baud,
    int? dataBits,
    String? parity,
    String? stopBits,
    String weightPrefix = '21',
    int pluCodeLen = 5,
    void Function(int current, int total)? onProgress,
    bool autoOpenLog = true,
  }) async {
    this.onProgress = onProgress;
    // ── Create upload logger ──
    final connStr = connection == LabelScaleConnection.tcp ? 'TCP/IP'
        : connection == LabelScaleConnection.ftp ? 'FTP'
        : connection == LabelScaleConnection.serial ? 'Serial'
        : 'File';
    final address = connection == LabelScaleConnection.serial
        ? (com ?? 'COM3')
        : '${ip ?? "—"}:${port ?? "—"}';

    logger = ScaleUploadLogger(
      scaleName: brand.name,
      brand: brand.name.toUpperCase(),
      connection: connStr,
      address: address,
    );

    if (items.isEmpty) {
      logger!.error('لا توجد أصناف للترحيل');
      logger!.result(0, 0, 0, ['No items']);
      await logger!.saveAndOpen(autoOpen: autoOpenLog);
      return PLUUploadResult(total: 0, success: 0, failed: 0, errors: ['No items to upload']);
    }

    // Log the PLU data table
    logger!.pluTable(items);

    logger!.section('بدء الترحيل');
    logger!.info('البروتوكول: ${brand.name.toUpperCase()} عبر $connStr');
    logger!.info('عدد الأصناف: ${items.length}');

    // ── Use brand-specific protocol ──
    final result = await _dispatchBrand(brand, items, connection, ip, port, com, baud, dataBits, parity, stopBits);

    // Log the result
    logger!.result(result.total, result.success, result.failed, result.errors);

    // Save and open the log file
    try {
      await logger!.saveAndOpen(autoOpen: autoOpenLog);
    } catch (e) {
      debugPrint('[ScaleLog] Failed to save log: $e');
    }

    return result;
  }

  Future<PLUUploadResult> _dispatchBrand(
    LabelScaleBrand brand,
    List<ScalePLUItem> items,
    LabelScaleConnection connection,
    String? ip, int? port, String? com, int? baud,
    int? dataBits, String? parity, String? stopBits,
  ) async {
    // ── AclasSDK: unified IP-only upload for ALL brands ──
    // The port (if provided by the user) is used as a first-try hint for UDP
    // discovery; the isolate still falls back to common Aclas ports on miss.
    if (connection == LabelScaleConnection.aclasSDK) {
      return _uploadViaAclasSDK(items, ip, customUdpPort: port);
    }

    switch (brand) {
      case LabelScaleBrand.cas:
        return _uploadCAS(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
      case LabelScaleBrand.digi:
        return _uploadDIGI(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
      case LabelScaleBrand.rongta:
        return _uploadRongta(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
      case LabelScaleBrand.aclas:
        return _uploadAclas(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
      case LabelScaleBrand.mettlerToledo:
        return _uploadMettlerToledo(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
      case LabelScaleBrand.tem:
        return _uploadTEM(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
      case LabelScaleBrand.dibal:
        return _uploadDibal(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
      case LabelScaleBrand.nvkTma:
        return _uploadNVK(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
    }
  }

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

      final raw = await Isolate.run(
        () => _aclasUploadInIsolate(isolateArgs),
      );

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

  // ═══════════════════════════════════════════════════════════════
  // Universal CSV-over-TCP Upload (PLU Manager approach)
  // ═══════════════════════════════════════════════════════════════

  /// Upload PLU items by sending CSV data over TCP.
  /// This is the universal approach used by PLU Manager software —
  /// it works with most modern label scales (CAS, TEM, Rongta, DIGI,
  /// Aclas, etc.) that can parse CSV data received on their TCP port.
  Future<PLUUploadResult> _uploadViaCSV(
    List<ScalePLUItem> items,
    String ip,
    int port,
    String weightPrefix,
    int pluCodeLen,
  ) async {
    Socket? socket;
    try {
      // Generate CSV in the same format as our file export (CAS PLU Manager compatible)
      final csvContent = LabelScaleService.instance.generatePLUCsv(
        items,
        weightPrefix: weightPrefix,
        pluCodeLen: pluCodeLen,
      );

      debugPrint('[Scale-CSV] Generated CSV: ${csvContent.length} chars, ${items.length} items');

      // Encode to CP1256 for Arabic support (scales don't understand UTF-8)
      final List<int> bytes = [];
      for (final char in csvContent.runes) {
        if (char < 128) {
          bytes.add(char);
        } else {
          bytes.addAll(transport.encodeCP1256(String.fromCharCode(char)));
        }
      }

      debugPrint('[Scale-CSV] Encoded to ${bytes.length} bytes (CP1256), connecting to $ip:$port...');

      // Connect and send the entire CSV payload
      socket = await transport.connectTCP(ip, port);
      socket.add(Uint8List.fromList(bytes));
      await socket.flush();

      // Wait for the scale to acknowledge the data
      final response = await transport.readResponse(
        socket, timeout: const Duration(seconds: 3),
      );
      if (response.isNotEmpty) {
        debugPrint('[Scale-CSV] Response: ${response.length} bytes');
      } else {
        debugPrint('[Scale-CSV] No response from scale after CSV send');
      }

      if (response.isEmpty) {
        debugPrint('[Scale-CSV] CSV sent but no confirmation from scale — reporting as failed');
        return PLUUploadResult(
          total: items.length,
          success: 0,
          failed: items.length,
          errors: ['تم إرسال البيانات لكن الميزان لم يؤكد الاستلام'],
        );
      }

      debugPrint('[Scale-CSV] CSV upload complete with response: ${items.length} items sent to $ip:$port');
      onProgress?.call(items.length, items.length);

      return PLUUploadResult(
        total: items.length,
        success: items.length,
        failed: 0,
      );
    } catch (e) {
      debugPrint('[Scale-CSV] CSV upload failed: $e');
      return PLUUploadResult(
        total: items.length,
        success: 0,
        failed: items.length,
        errors: ['CSV upload failed: $e'],
      );
    } finally {
      try { await socket?.close(); } catch (_) {}
    }
  }

  /// Build a clear-all-PLU command for the given brand.
  Uint8List? buildClearCommand(LabelScaleBrand brand) {
    switch (brand) {
      case LabelScaleBrand.cas:
        return Uint8List.fromList(utf8.encode('C43A02\x0a'));
      case LabelScaleBrand.digi:
        return Uint8List.fromList(utf8.encode('\x02PLUCLR\x03'));
      case LabelScaleBrand.rongta:
        return Uint8List.fromList(utf8.encode('\x02CLRPLU\x03'));
      case LabelScaleBrand.aclas:
        return Uint8List.fromList(utf8.encode('\x02PLUCLR\x03'));
      case LabelScaleBrand.mettlerToledo:
        return Uint8List.fromList(utf8.encode('CLEAR_ALL_PLU\r\n'));
      case LabelScaleBrand.tem:
        return Uint8List.fromList(utf8.encode('\x02CLRALL\x03'));
      case LabelScaleBrand.dibal:
        return Uint8List.fromList(utf8.encode('\x02C\x03'));
      case LabelScaleBrand.nvkTma:
        return Uint8List.fromList(utf8.encode('\x02CLRALL\x03'));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Shared TCP PLU upload loop — eliminates duplication across brands
  // ═══════════════════════════════════════════════════════════════

  /// Standard ACK/NAK interpreter for binary protocols.
  /// Also recognizes echo-back pattern (Fire Bird, Chinese scales).
  /// [sentCmd] is optional — if provided, enables echo-back detection.
  /// Returns empty string on success, error message on failure.
  String _interpretACKNAK(Uint8List response, ScalePLUItem item, {Uint8List? sentCmd}) {
    if (response.isNotEmpty) {
      logger?.receivedBytes('رد PLU ${item.pluNumber}', response);
      if (response[0] == 0x06) {
        logger?.success('PLU ${item.pluNumber}: ACK — تم القبول');
        return ''; // success
      } else if (response[0] == 0x15) {
        logger?.error('PLU ${item.pluNumber}: NAK — رفض');
        return 'PLU ${item.pluNumber}: رفض الميزان (NAK)';
      } else if (sentCmd != null && _isEchoBackSuccess(sentCmd, response)) {
        logger?.success('PLU ${item.pluNumber}: Echo-back — تم القبول ✓');
        return ''; // success — echo-back confirmation
      } else {
        logger?.warning('PLU ${item.pluNumber}: رد غير متوقع — فشل');
        return 'PLU ${item.pluNumber}: رد غير متوقع 0x${response[0].toRadixString(16)}';
      }
    }
    logger?.error('PLU ${item.pluNumber}: لا استجابة — فشل');
    return 'PLU ${item.pluNumber}: لا استجابة من الميزان';
  }

  /// Text OK/ER interpreter for Aclas-style protocols.
  String _interpretTextOKER(Uint8List response, ScalePLUItem item) {
    final respStr = response.isNotEmpty
        ? String.fromCharCodes(response).trim()
        : '';
    if (response.isNotEmpty) {
      logger?.receivedBytes('رد PLU ${item.pluNumber}', response);
    }
    if (respStr.startsWith('OK')) {
      logger?.success('PLU ${item.pluNumber}: OK — تم القبول');
      return '';
    } else if (respStr.startsWith('ER')) {
      logger?.error('PLU ${item.pluNumber}: ER — رفض');
      return 'PLU ${item.pluNumber}: رفض الميزان (ER)';
    } else if (response.isNotEmpty) {
      logger?.warning('PLU ${item.pluNumber}: رد غير معروف — فشل');
      return 'PLU ${item.pluNumber}: رد غير معروف: $respStr';
    }
    logger?.error('PLU ${item.pluNumber}: لا استجابة — فشل');
    return 'PLU ${item.pluNumber}: لا استجابة من الميزان';
  }

  /// Detect echo-back response pattern used by Fire Bird, Rongta, and many
  /// Chinese label scales. The scale echoes the sent command (minus the leading
  /// 'W' byte) and terminates with CR LF ETX (0x0D 0x0A 0x03).
  ///
  /// Example:
  ///   Sent:     W 36F01,000004L0063:21000004...checksum  (83 bytes)
  ///   Response: 36F01,000004L0063:21000004...checksum + padding + 0D 0A 03
  bool _isEchoBackSuccess(Uint8List sent, Uint8List response) {
    if (response.length < 10) return false;

    // Check 1: Response ends with ETX (0x03) — the standard end marker.
    // Look for 0x03 near the end (may be the last non-zero byte).
    bool hasETX = false;
    for (int i = response.length - 1; i >= response.length - 5 && i >= 0; i--) {
      if (response[i] == 0x03) { hasETX = true; break; }
    }
    if (!hasETX) return false;

    // Check 2: Response starts with same data as sent (skipping the 'W' prefix).
    // The sent command starts with 'W' (0x57), the echo starts at sent[1].
    if (sent.length < 5) return false;
    final matchLen = (response.length < sent.length - 1) ? response.length : sent.length - 1;
    // Compare first 10 bytes (enough to confirm it's the same record)
    final checkLen = matchLen < 10 ? matchLen : 10;
    int matching = 0;
    for (int i = 0; i < checkLen; i++) {
      if (response[i] == sent[i + 1]) matching++;
    }
    // At least 80% of checked bytes should match
    return matching >= (checkLen * 0.8).ceil();
  }

  /// Generic TCP PLU upload loop.
  ///
  /// Sends each item's record to [socket], reads the response,
  /// and interprets it via [interpret]. Returns aggregated counters.
  Future<({int success, int failed, List<String> errors})> _uploadPLUOverTCP({
    required Socket socket,
    required List<ScalePLUItem> items,
    required Uint8List Function(ScalePLUItem) buildRecord,
    required String Function(Uint8List response, ScalePLUItem item) interpret,
    int? delimiter,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    int success = 0;
    int failed = 0;
    final errors = <String>[];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      logger?.pluItem(i + 1, items.length, item.pluNumber, item.name,
          item.unitPrice, item.isByWeight, item.barcode ?? '');
      try {
        final cmd = buildRecord(item);
        logger?.sentBytes('PLU ${item.pluNumber}', cmd);
        socket.add(cmd);
        await socket.flush();

        final response = await transport.readResponse(
          socket, timeout: timeout, delimiter: delimiter,
        );

        final error = interpret(response, item);
        if (error.isEmpty) {
          success++;
        } else {
          failed++;
          errors.add(error);
        }
      } catch (e) {
        failed++;
        errors.add('PLU ${item.pluNumber}: $e');
        logger?.error('PLU ${item.pluNumber}: خطأ — $e');
      }
      onProgress?.call(i + 1, items.length);
    }

    return (success: success, failed: failed, errors: errors);
  }

  /// Try a specific PLU protocol on a TCP port.
  /// Returns PLUUploadResult if the scale responds with ACK, null otherwise.
  Future<PLUUploadResult?> tryProtocolOnPort(
    String ip,
    int port,
    List<ScalePLUItem> items,
    String protocolName,
    Uint8List Function(ScalePLUItem) recordBuilder,
  ) async {
    try {
      debugPrint('[LabelScale] Trying $protocolName on $ip:$port...');
      final socket = await transport.connectTCP(ip, port);
      int success = 0;
      int failed = 0;
      final errors = <String>[];

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        try {
          final cmd = recordBuilder(item);
          socket.add(cmd);
          await socket.flush();

          final response = await transport.readResponse(
            socket, timeout: const Duration(seconds: 2),
          );

          if (response.isNotEmpty && response[0] == 0x06) {
            success++;
          } else if (response.isNotEmpty) {
            failed++;
            errors.add(
              'PLU ${item.pluNumber}: Unexpected response 0x${response[0].toRadixString(16)}',
            );
          } else {
            failed++;
            errors.add('PLU ${item.pluNumber}: لا استجابة من الميزان');
            debugPrint('[Scale] PLU ${item.pluNumber}: No response from scale — counted as FAILED');
          }
        } catch (e) {
          failed++;
          errors.add('PLU ${item.pluNumber}: $e');
        }
        onProgress?.call(i + 1, items.length);
      }

      await socket.close();
      return PLUUploadResult(
        total: items.length,
        success: success,
        failed: failed,
        errors: errors,
      );
    } catch (e) {
      debugPrint(
        '[LabelScale] $protocolName on $ip:$port failed: $e',
      );
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CAS CL5000 / CL5200 Protocol
  // ═══════════════════════════════════════════════════════════════

  Future<PLUUploadResult> _uploadCAS(
    List<ScalePLUItem> items,
    LabelScaleConnection conn,
    String? ip, int? port, String? com, int? baud,
    int? dataBits, String? parity, String? stopBits,
  ) async {
    int success = 0;
    int failed = 0;
    final errors = <String>[];

    final effectiveIp = ip ?? '192.168.1.100';
    final effectivePort = port ?? 20304;

    logger?.section('CAS — بدء الاتصال');
    logger?.info('الهدف: $effectiveIp:$effectivePort | الاتصال: $conn');

    Socket? socket;
    dynamic serialPort;
    try {
      if (conn == LabelScaleConnection.serial) {
        // ── Serial Mode ──
        serialPort = SerialPort(com ?? 'COM3', openNow: false, BaudRate: baud ?? 9600);
        await transport.configureSerial(serialPort, baud ?? 9600, dataBits, parity, stopBits);
        serialPort.open();
        logger?.success('تم فتح المنفذ التسلسلي ${com ?? "COM3"} بسرعة ${baud ?? 9600}');

        final startCmd = Uint8List.fromList(utf8.encode('\x02PLUSTART\x03'));
        serialPort.writeBytesFromUint8List(startCmd);
        logger?.sentBytes('PLUSTART', startCmd);
        await Future.delayed(const Duration(milliseconds: 300));

        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          logger?.pluItem(i + 1, items.length, item.pluNumber, item.name, item.unitPrice, item.isByWeight, item.barcode ?? '');
          try {
            final cmd = _buildCASPLURecord(item);
            logger?.sentBytes('PLU ${item.pluNumber}', cmd);

            serialPort.writeBytesFromUint8List(cmd);
            await Future.delayed(const Duration(milliseconds: 100));

            final resp = await serialPort.readBytes(64, timeout: const Duration(milliseconds: 1500));
            if (resp.isNotEmpty) {
              logger?.receivedBytes('رد PLU ${item.pluNumber}', Uint8List.fromList(resp));
              if (resp[0] == 0x06) {
                success++;
                logger?.success('PLU ${item.pluNumber}: ACK — تم القبول');
              } else if (resp[0] == 0x15) {
                failed++;
                errors.add('PLU ${item.pluNumber}: رفض الميزان (NAK)');
                logger?.error('PLU ${item.pluNumber}: NAK — رفض');
              } else {
                final fullResp = String.fromCharCodes(resp.where((b) => b >= 0x20 && b < 0x7F));
                failed++;
                errors.add('PLU ${item.pluNumber}: رد غير متوقع 0x${resp[0].toRadixString(16)} ($fullResp)');
                logger?.warning('PLU ${item.pluNumber}: رد: "$fullResp" — فشل');
              }
            } else {
              failed++;
              errors.add('PLU ${item.pluNumber}: لا استجابة من الميزان');
              logger?.error('PLU ${item.pluNumber}: لا استجابة — فشل');
            }
          } catch (e) {
            failed++;
            errors.add('PLU ${item.pluNumber}: $e');
            logger?.error('PLU ${item.pluNumber}: خطأ — $e');
          }
          onProgress?.call(i + 1, items.length);
        }

        final endCmd = Uint8List.fromList(utf8.encode('\x02PLUEND\x03'));
        serialPort.writeBytesFromUint8List(endCmd);
        logger?.sentBytes('PLUEND', endCmd);
        await Future.delayed(const Duration(milliseconds: 200));
        logger?.info('تم إغلاق المنفذ التسلسلي');
      } else {
        // ── TCP Mode ── (W36F01 binary records directly, no wrapper commands)
        logger?.info('جاري الاتصال TCP بـ $effectiveIp:$effectivePort...');
        socket = await transport.connectTCP(effectiveIp, effectivePort);
        logger?.success('تم الاتصال TCP بنجاح');

        // Drain any welcome/banner data from the scale
        final banner = await transport.readResponse(
          socket, timeout: const Duration(seconds: 1),
        );
        if (banner.isNotEmpty) {
          logger?.receivedBytes('بيانات ترحيب من الميزان', banner);
        }

        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          logger?.pluItem(i + 1, items.length, item.pluNumber, item.name, item.unitPrice, item.isByWeight, item.barcode ?? '');
          try {
            final cmd = _buildCASPLURecord(item);
            logger?.sentBytes('PLU ${item.pluNumber}', cmd);

            socket.add(cmd);
            await socket.flush();

            final response = await transport.readResponse(
              socket, timeout: const Duration(seconds: 3),
            );

            if (response.isNotEmpty) {
              logger?.receivedBytes('رد PLU ${item.pluNumber}', response);
              if (response[0] == 0x06) {
                success++;
                logger?.success('PLU ${item.pluNumber}: ACK — تم القبول');
              } else if (response[0] == 0x15) {
                failed++;
                errors.add('PLU ${item.pluNumber}: رفض الميزان (NAK)');
                logger?.error('PLU ${item.pluNumber}: NAK — رفض');
              } else {
                // Log full response text for diagnosis
                final fullResp = String.fromCharCodes(response).replaceAll(RegExp(r'[^\x20-\x7E]'), '.');
                failed++;
                errors.add('PLU ${item.pluNumber}: رد غير متوقع 0x${response[0].toRadixString(16)} ($fullResp)');
                logger?.warning('PLU ${item.pluNumber}: رد: "$fullResp" — فشل');
              }
            } else {
              failed++;
              errors.add('PLU ${item.pluNumber}: لا استجابة من الميزان');
              logger?.error('PLU ${item.pluNumber}: لا استجابة — فشل');
            }
          } catch (e) {
            failed++;
            errors.add('PLU ${item.pluNumber}: $e');
            logger?.error('PLU ${item.pluNumber}: خطأ — $e');
          }
          onProgress?.call(i + 1, items.length);
        }

        logger?.info('تم إغلاق اتصال TCP');
      }
    } catch (e) {
      logger?.error('خطأ في الاتصال: $e');
      return PLUUploadResult(
        total: items.length, success: 0, failed: items.length,
        errors: ['خطأ في الاتصال: $e'],
      );
    } finally {
      try { await socket?.close(); } catch (_) {}
      try { serialPort?.close(); } catch (_) {}
    }

    return PLUUploadResult(
      total: items.length, success: success, failed: failed, errors: errors,
    );
  }

  /// Build a CAS PLU record
  /// W + record_type + F + format + , + plu_no + L + data_length + : + data + bcc
  Uint8List _buildCASPLURecord(ScalePLUItem item) {
    final List<int> dataBytes = [];

    // Department(2) + PLU#(6) + ItemType(1)
    final dept = item.department.toString().padLeft(2, '0');
    final plu = item.pluNumber.toString().padLeft(6, '0');
    final itemType = item.isByWeight ? '0' : '1';
    dataBytes.addAll(utf8.encode(dept));
    dataBytes.addAll(utf8.encode(plu));
    dataBytes.addAll(utf8.encode(itemType));

    // Name1(40) - CP1256 for Arabic, reversed for visual LTR display
    final nameEncoded = transport.encodeCP1256(
      ScaleTransport.reverseArabicForScale(item.name),
    );
    final paddedName = Uint8List(40)..fillRange(0, 40, 0x20);
    for (int i = 0; i < nameEncoded.length && i < 40; i++) {
      paddedName[i] = nameEncoded[i];
    }
    dataBytes.addAll(paddedName);

    // Unit price (8 digits, right-aligned)
    final priceInt = (item.unitPrice * 100).round();
    final priceStr = priceInt.toString().padLeft(8, '0');
    dataBytes.addAll(utf8.encode(priceStr));

    // Tare weight (6 digits)
    final tareInt = (item.tareWeight * 1000).round();
    final tareStr = tareInt.toString().padLeft(6, '0');
    dataBytes.addAll(utf8.encode(tareStr));

    // BCC = XOR of all data bytes
    int bcc = 0;
    for (final b in dataBytes) {
      bcc ^= b;
    }

    final dataLen = dataBytes.length.toString().padLeft(4, '0');

    final header = utf8.encode('W36F01,$plu' 'L$dataLen:');
    final result = Uint8List(header.length + dataBytes.length + 1);
    result.setAll(0, header);
    result.setAll(header.length, dataBytes);
    result[result.length - 1] = bcc;

    debugPrint('[CAS-Record] PLU=$plu dept=$dept type=$itemType price=$priceStr tare=$tareStr nameLen=${nameEncoded.length} dataLen=$dataLen bcc=0x${bcc.toRadixString(16)} totalBytes=${result.length}');

    return result;
  }

  // ═══════════════════════════════════════════════════════════════
  // DIGI SM-100/SM-120 Protocol
  // ═══════════════════════════════════════════════════════════════

  Future<PLUUploadResult> _uploadDIGI(
    List<ScalePLUItem> items,
    LabelScaleConnection conn,
    String? ip, int? port, String? com, int? baud,
    int? dataBits, String? parity, String? stopBits,
  ) async {
    int success = 0;
    int failed = 0;
    final errors = <String>[];

    final effectiveIp = ip ?? '192.168.1.100';
    final effectivePort = port ?? 3001;

    logger?.section('DIGI — بدء الاتصال');
    logger?.info('الهدف: ${conn == LabelScaleConnection.serial ? (com ?? "COM3") : "$effectiveIp:$effectivePort"} | الاتصال: $conn');

    Socket? socket;
    dynamic serialPort;
    try {
      if (conn == LabelScaleConnection.serial) {
        serialPort = SerialPort(com ?? 'COM3', openNow: false, BaudRate: baud ?? 9600);
        await transport.configureSerial(serialPort, baud ?? 9600, dataBits, parity, stopBits);
        serialPort.open();
        logger?.success('تم فتح المنفذ التسلسلي ${com ?? "COM3"}');

        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          logger?.pluItem(i + 1, items.length, item.pluNumber, item.name, item.unitPrice, item.isByWeight, item.barcode ?? '');
          try {
            final cmd = _buildDIGIPLURecord(item);
            logger?.sentBytes('PLU ${item.pluNumber}', cmd);
            serialPort.writeBytesFromUint8List(cmd);
            await Future.delayed(const Duration(milliseconds: 100));

            final resp = await serialPort.readBytes(64, timeout: const Duration(milliseconds: 1500));
            if (resp.isNotEmpty) {
              logger?.receivedBytes('رد PLU ${item.pluNumber}', Uint8List.fromList(resp));
              if (resp[0] == 0x06) {
                success++;
                logger?.success('PLU ${item.pluNumber}: ACK — تم القبول');
              } else if (resp[0] == 0x15) {
                failed++;
                errors.add('PLU ${item.pluNumber}: رفض الميزان (NAK)');
                logger?.error('PLU ${item.pluNumber}: NAK — رفض');
              } else {
                failed++;
                errors.add('PLU ${item.pluNumber}: رد غير معروف 0x${resp[0].toRadixString(16)}');
                logger?.warning('PLU ${item.pluNumber}: رد غير معروف 0x${resp[0].toRadixString(16)} — فشل');
              }
            } else {
              failed++;
              errors.add('PLU ${item.pluNumber}: لا استجابة من الميزان');
              logger?.error('PLU ${item.pluNumber}: لا استجابة — فشل');
            }
          } catch (e) {
            failed++;
            errors.add('PLU ${item.pluNumber}: $e');
            logger?.error('PLU ${item.pluNumber}: خطأ — $e');
          }
          onProgress?.call(i + 1, items.length);
        }

        logger?.info('تم إغلاق المنفذ التسلسلي');
      } else {
        logger?.info('جاري الاتصال TCP بـ $effectiveIp:$effectivePort...');
        socket = await transport.connectTCP(effectiveIp, effectivePort);
        logger?.success('تم الاتصال TCP بنجاح');

        final r = await _uploadPLUOverTCP(
          socket: socket, items: items,
          buildRecord: _buildDIGIPLURecord,
          interpret: _interpretACKNAK,
          delimiter: 0x03,
        );
        success = r.success; failed = r.failed; errors.addAll(r.errors);

        logger?.info('تم إغلاق اتصال TCP');
      }
    } catch (e) {
      logger?.error('خطأ في الاتصال: $e');
      return PLUUploadResult(
        total: items.length, success: 0, failed: items.length,
        errors: ['خطأ في الاتصال: $e'],
      );
    } finally {
      try { await socket?.close(); } catch (_) {}
      try { serialPort?.close(); } catch (_) {}
    }

    return PLUUploadResult(
      total: items.length, success: success, failed: failed, errors: errors,
    );
  }

  /// Build a DIGI PLU record
  /// Format: <STX>PLU,dept,plu_no,type,name,unit_price,tare,barcode<ETX>
  Uint8List _buildDIGIPLURecord(ScalePLUItem item) {
    final type = item.isByWeight ? 'W' : 'C';
    final price = (item.unitPrice * 100).round();
    final tare = (item.tareWeight * 1000).round();
    final name = transport.padRight(
      ScaleTransport.reverseArabicForScale(item.name), 24,
    );
    final bc = item.barcode ?? '';

    final record = '\x02PLU,${item.department},${item.pluNumber},$type,$name,$price,$tare,$bc\x03';
    return Uint8List.fromList(utf8.encode(record));
  }

  // ═══════════════════════════════════════════════════════════════
  // Rongta RLS1100 Protocol
  // ═══════════════════════════════════════════════════════════════

  Future<PLUUploadResult> _uploadRongta(
    List<ScalePLUItem> items,
    LabelScaleConnection conn,
    String? ip, int? port, String? com, int? baud,
    int? dataBits, String? parity, String? stopBits,
  ) async {
    int success = 0;
    int failed = 0;
    final errors = <String>[];

    logger?.section('Rongta — بدء الاتصال');

    Socket? socket;
    dynamic serialPort;
    try {
      if (conn == LabelScaleConnection.ftp) {
        // ── FTP Mode (Rongta RLS primary & most reliable method) ──
        logger?.info('FTP ترحيل عبر إلى ${ip ?? "192.168.1.100"}:${port ?? 21}');
        final ftpResult = await _tryRongtaFTP(
          ip ?? '192.168.1.100', port ?? 21, items, _buildRongtaCSV(items),
        );
        if (ftpResult != null) {
          logger?.success('FTP: تم رفع الملف بنجاح (${ftpResult.success} صنف)');
          return ftpResult;
        }
        logger?.error('FTP: فشل الاتصال');
        return PLUUploadResult(
          total: items.length, success: 0, failed: items.length,
          errors: ['فشل اتصال FTP بـ ${ip ?? "192.168.1.100"}:${port ?? 21}'],
        );

      } else if (conn == LabelScaleConnection.tcp) {
        // ══════════════════════════════════════════════════════════════
        // Rongta RLS — TCP/IP Upload Strategy:
        //   1. Try FTP (port 21) — standard PLU Manager method
        //   2. Fallback to AclasSDK (UDP/Pecr auto-detect)
        //
        // Most Rongta RLS scales manage PLU data via FTP, NOT raw TCP.
        // Port 4001 (user-configured) is for scale communication/printing
        // but PLU upload goes through FTP on port 21.
        // AclasSDK UDP often reports success but data doesn't persist
        // on scales that don't fully support the Pecr protocol.
        // ══════════════════════════════════════════════════════════════
        final effectiveIp = ip ?? '192.168.1.100';

        // ══════════════════════════════════════════════════════════════
        // STRATEGY 1 (PRIORITY): Rongta RLS 0110 Binary over raw TCP
        // ══════════════════════════════════════════════════════════════
        // Many Fire Bird / Rongta RLS scales support PLU upload via raw TCP
        // on port 4001 (the user's configured port). This is the official
        // RLS1100 protocol and does NOT require FTP server to be enabled.
        //
        // Frame format (from RLS1000 Software Manual §2.5):
        //   STX(0x02) + "0110" + 99-byte-PLU-record + ETX(0x03) + LRC
        //
        // We try multiple frame variants since different firmwares differ.
        // ══════════════════════════════════════════════════════════════
        logger?.section('محاولة 1: Rongta RLS 0110 TCP Binary');
        logger?.info('بروتوكول Rongta TCP الأصلى على البورت ${port ?? 4001}');

        final tcpResult = await _tryRongtaTCP0110(
          effectiveIp, port ?? 4001, items,
        );
        if (tcpResult != null && tcpResult.success > 0) {
          logger?.success('✓ تم الترحيل عبر TCP 0110 على البورت ${port ?? 4001}');
          return tcpResult;
        }
        logger?.info('TCP 0110 فشل — جاري تجربة CSV-over-TCP...');

        // ══════════════════════════════════════════════════════════════
        // STRATEGY 2: CSV-over-TCP on configured port (4001)
        // ══════════════════════════════════════════════════════════════
        // Some Fire Bird/Rongta firmwares accept CSV bulk upload by sending
        // the entire CSV content as a single TCP payload, optionally wrapped
        // with start/end commands. Tries several framings.
        logger?.section('محاولة 2: CSV-over-TCP');
        final csvResult = await _tryCsvOverTcp(
          effectiveIp, port ?? 4001, items,
        );
        if (csvResult != null && csvResult.success > 0) {
          logger?.success('✓ تم الترحيل عبر CSV-over-TCP!');
          return csvResult;
        }
        logger?.info('CSV-over-TCP فشل — جاري استكشاف الخيارات الأخرى...');

        // ── Strategy 3: Port scan + service identification ──
        // Discover which ports are open AND what service runs on each.
        // A scale might run FTP on port 5002 instead of standard 21.
        logger?.section('محاولة 3: استكشاف البورتات والخدمات');
        final allPortsToScan = [
          21, 22, 23, 80, 443,                    // Standard
          4001, 4000, 5001, 5002, 5000,           // Scale common
          6001, 7001, 8000, 8001, 8080, 8888,     // Alternatives
          9100, 9101, 9200, 9000,                 // Printer/label
        ];
        final openPorts = await _probePorts(effectiveIp, allPortsToScan);
        if (openPorts.isEmpty) {
          logger?.error('⚠ لا يوجد أى بورت مفتوح — الميزان غير متصل أو محجوب بجدار حماية');
        } else {
          logger?.success('البورتات المفتوحة: ${openPorts.join(", ")}');
          // Grab banners to identify what's running on each port
          final services = await _identifyServices(effectiveIp, openPorts);

          // Try FTP on any port whose banner starts with "220" (FTP standard greeting)
          for (final entry in services.entries) {
            if (entry.value.startsWith('FTP:')) {
              logger?.section('محاولة FTP على Port ${entry.key} (اكتُشف عبر banner)');
              final ftpResult = await _tryRongtaFTP(
                effectiveIp, entry.key, items, _buildRongtaCSV(items),
              );
              if (ftpResult != null && ftpResult.success > 0) {
                logger?.success('✓ تم الترحيل عبر FTP على Port ${entry.key}!');
                return ftpResult;
              }
            }
          }
        }

        // ── Strategy 3: FTP on standard port 21 (even if not in banner list) ──
        logger?.section('محاولة 4: FTP على Port 21 (قياسى)');
        logger?.info('Rongta PLU Manager يستخدم FTP — جاري المحاولة...');
        final ftpResult = await _tryRongtaFTP(
          effectiveIp, 21, items, _buildRongtaCSV(items),
        );
        if (ftpResult != null && ftpResult.success > 0) {
          logger?.success('FTP: تم رفع ${ftpResult.success} صنف بنجاح!');
          return ftpResult;
        }
        logger?.info('FTP غير متاح — جاري تجربة HTTP...');

        // ── Strategy 2: HTTP Upload (modern Chinese scales) ──
        // Only try HTTP on already-identified HTTP ports (from banner grab).
        // Avoids wasting time hitting non-HTTP ports that just time out.
        logger?.section('محاولة 5: HTTP');
        // Extract HTTP-ish ports (either banner starts with HTTP/, or common HTTP ports)
        final httpCandidatePorts = openPorts
            .where((p) => [80, 443, 8080, 8888, 8000, 8001, 5000].contains(p))
            .toList();
        final httpResult = httpCandidatePorts.isEmpty
            ? null
            : await _tryHttpUpload(
                effectiveIp, items, _buildRongtaCSV(items),
                ports: httpCandidatePorts,
              );
        if (httpResult != null && httpResult.success > 0) {
          logger?.success('HTTP: تم رفع ${httpResult.success} صنف بنجاح!');
          return httpResult;
        }
        logger?.info('HTTP غير متاح — جاري تجربة AclasSDK كملاذ أخير...');

        // ── Strategy 5: AclasSDK (UDP/Pecr) — Full Sequence ──
        // Upload order: Department → Unit → Group → PLU → HotKey
        // Without prerequisite tables, scale silently rejects PLU records.
        logger?.section('محاولة 6: AclasSDK (UDP/Pecr)');
        logger?.info('Rongta RLS — AclasSDK ترحيل عبر UDP');
        logger?.info('تسلسل الترحيل: الأقسام → الوحدات → المجموعات → PLU → مفاتيح الاختصار');

        final tempDir = Directory.systemTemp;
        final rongTs = DateTime.now().millisecondsSinceEpoch;
        final filesToClean = <String>[];

        // Generate all prerequisite + data files
        final deptIds = items.map((e) => e.department).toSet();
        final deptFilePath = '${tempDir.path}\\rongta_dept_$rongTs.txt';
        await AclasSDK.generateDepartmentFile(
          deptIds.map((id) => AclasDepartment(id: id, name: 'قسم $id')).toList(),
          deptFilePath,
        );
        filesToClean.add(deptFilePath);
        logger?.info('ملف الأقسام: ${deptIds.length} قسم');

        final unitFilePath = '${tempDir.path}\\rongta_unit_$rongTs.txt';
        await AclasSDK.generateUnitFile([
          AclasUnit(id: 4, name: 'kg'),
          AclasUnit(id: 10, name: 'pcs'),
        ], unitFilePath);
        filesToClean.add(unitFilePath);
        logger?.info('ملف الوحدات: kg(4), pcs(10)');

        final groupFilePath = '${tempDir.path}\\rongta_group_$rongTs.txt';
        await AclasSDK.generateGroupFile([
          AclasGroup(id: 1, name: 'عام'),
        ], groupFilePath);
        filesToClean.add(groupFilePath);

        final pluItems = items.map((item) => AclasPLUItem(
          id: item.pluNumber,
          itemCode: item.pluNumber.toString(),
          departmentId: item.department,
          name: item.name,
          price: item.unitPrice,
          unitId: (item.isByWeight) ? 4 : 10,
          barcodeType1: 7,
          barcodeType2: 7,
          tareWeight: item.tareWeight,
        )).toList();
        final pluFilePath = '${tempDir.path}\\rongta_plu_$rongTs.txt';
        await AclasSDK.generatePLUFile(pluItems, pluFilePath);
        filesToClean.add(pluFilePath);
        logger?.info('ملف PLU: ${items.length} صنف');

        // HotKey file will be generated AFTER device detection so we can use
        // the scale's actual hotKeyCount for page wrapping.
        final hotKeyFilePath = '${tempDir.path}\\rongta_hotkey_$rongTs.txt';
        filesToClean.add(hotKeyFilePath);

        if (!AclasSDK.initialize()) {
          logger?.error('فشل تهيئة AclasSDK');
          errors.add('فشل FTP و AclasSDK — تأكد من إعدادات الميزان');
          failed = items.length;
        } else {
          logger?.success('تم تهيئة AclasSDK');

          // Try all AclasSDK protocol types to find one that reports pluStorage > 0
          // Protocol 1 = Pecr, 2 = Hecr, 3 = Tsecr — different firmwares respond
          // differently. pluStorage=0 = "this protocol is not supported for writing"
          AclasDeviceInfo? deviceInfo;
          final protocolTypes = [
            {'type': 0, 'name': 'Auto'},
            {'type': 1, 'name': 'Pecr'},
            {'type': 2, 'name': 'Hecr'},
            {'type': 3, 'name': 'Tsecr'},
          ];

          for (final proto in protocolTypes) {
            final info = AclasSDK.getDeviceInfo(
              effectiveIp,
              protocolType: proto['type'] as int,
            );
            if (info != null) {
              logger?.info('بروتوكول ${proto['name']}: '
                  'منفذ=${info.port}, PLU أقصى=${info.pluStorage}, '
                  'hotKeys=${info.hotKeyCount}');
              // Prefer a protocol where the scale reports actual PLU capacity
              if (deviceInfo == null || info.pluStorage > deviceInfo.pluStorage) {
                deviceInfo = info;
              }
            }
          }

          if (deviceInfo != null) {
            logger?.success('تم اختيار البروتوكول الأفضل: '
                'نوع=${deviceInfo.protocolType}, منفذ=${deviceInfo.port}, '
                'PLU أقصى=${deviceInfo.pluStorage}');

            if (deviceInfo.pluStorage == 0) {
              logger?.error('⚠ كل بروتوكولات AclasSDK بترد PLU=0');
              logger?.error('⚠ ده معناه الميزان مش بيقبل ترحيل PLU من الشبكة حالياً');
              logger?.info('');
              logger?.info('═══ الإجراء المطلوب على الميزان ═══');
              logger?.info('1. اضغط SET / SETUP على الميزان');
              logger?.info('2. ادخل كلمة المرور (عادة 000000 أو 888888)');
              logger?.info('3. افتح Communication Settings أو الإعدادات الشبكية');
              logger?.info('4. فعّل FTP Server = ON');
              logger?.info('5. تأكد من PLU Storage > 0 (لو فى خيار للسعة)');
              logger?.info('6. احفظ الإعدادات وأعد تشغيل الميزان');
              logger?.info('7. ثم أعد محاولة الترحيل');
              logger?.info('═══════════════════════════════════');
            }

            onProgress?.call(0, items.length);

            // ── Upload full sequence ──
            // Step 1: Departments
            logger?.section('ترحيل الأقسام (Department)');
            final deptResult = await AclasSDK.uploadDataFile(
              effectiveIp, deptFilePath, AclasDataType.department, 'Department',
              deviceInfo: deviceInfo,
            );
            logger?.info(deptResult.success ? 'الأقسام ✓' : 'الأقسام ✗: ${deptResult.message}');

            // Step 2: Units
            logger?.section('ترحيل الوحدات (Unit)');
            final unitResult = await AclasSDK.uploadDataFile(
              effectiveIp, unitFilePath, AclasDataType.unit, 'Unit',
              deviceInfo: deviceInfo,
            );
            logger?.info(unitResult.success ? 'الوحدات ✓' : 'الوحدات ✗: ${unitResult.message}');

            // Step 2b: Groups
            final groupResult = await AclasSDK.uploadDataFile(
              effectiveIp, groupFilePath, AclasDataType.group, 'Group',
              deviceInfo: deviceInfo,
            );
            logger?.info(groupResult.success ? 'المجموعات ✓' : 'المجموعات ✗: ${groupResult.message}');

            // Step 3: PLU
            logger?.section('ترحيل PLU');
            logger?.info('بدء ترحيل ${items.length} صنف إلى $effectiveIp ...');
            final result = await AclasSDK.uploadPLU(
              effectiveIp, pluFilePath, deviceInfo: deviceInfo,
            );

            if (result.success) {
              // IMPORTANT: When pluStorage=0, the SDK reports "success" but the
              // scale doesn't actually store the data. We need to flag this
              // clearly — otherwise the user thinks upload worked.
              if (deviceInfo.pluStorage == 0) {
                success = 0;
                failed = items.length;
                errors.add('الميزان أكد استلام البيانات لكنه مش بيحفظها '
                    '(pluStorage=0). راجع إعدادات الميزان.');
                logger?.error('⚠ الميزان رد "تم" لكن البيانات مش محفوظة فعلياً');
                logger?.error('⚠ الدليل: PLU أقصى=0 من الميزان نفسه');
                logger?.error('⚠ لازم تفعّل FTP أو تزود السعة من إعدادات الميزان');
              } else {
                success = items.length;
                failed = 0;
                logger?.success('تم ترحيل ${items.length} صنف '
                    '(السعة المتاحة: ${deviceInfo.pluStorage})');
                logger?.info('التفاصيل: ${result.message}');
              }

              // Step 4: HotKeys — build mapping using scale's actual button count
              logger?.section('ترحيل مفاتيح الاختصار (HotKeys)');
              try {
                final btnCount = deviceInfo.hotKeyCount;
                logger?.info('عدد أزرار الاختصار بالميزان: '
                    '${btnCount > 0 ? btnCount : "غير معروف (استخدام 112)"}');
                final hkMappings = AclasHotKeyMapping.buildSequentialMappings(
                  items.map((e) => e.pluNumber).toList(),
                  buttonsPerPage: btnCount > 0 ? btnCount : null,
                );
                await AclasSDK.generateHotKeyFile(hkMappings, hotKeyFilePath);
                logger?.info('تم إنشاء ${hkMappings.length} مفتاح (${hkMappings.map((m) => m.mode).toSet().length} صفحة)');
                final hkResult = await AclasSDK.uploadHotKeys(
                  effectiveIp, hotKeyFilePath, deviceInfo: deviceInfo,
                );
                logger?.info(hkResult.success
                    ? 'تم ترحيل ${hkMappings.length} مفتاح اختصار ✓'
                    : 'فشل ترحيل مفاتيح الاختصار: ${hkResult.message}');
              } catch (e) {
                logger?.error('خطأ في ترحيل مفاتيح الاختصار: $e');
              }

              if (deviceInfo.pluStorage == 0) {
                logger?.info('');
                logger?.info('⚠ تنبيه: الميزان قد يبلغ عن نجاح الترحيل لكن البيانات لا تصل فعلياً');
                logger?.info('⚠ إذا الميزان فاضي — غيّر طريقة الاتصال إلى FTP في إعدادات الميزان');
              }
            } else {
              failed = items.length;
              errors.add(result.message);
              logger?.error('فشل الترحيل: ${result.message}');
            }
            onProgress?.call(items.length, items.length);
          } else {
            logger?.error('لم يتم كشف الميزان في $effectiveIp');
            failed = items.length;
            errors.add('لم يتم كشف الميزان — تأكد من IP والاتصال');
          }

          AclasSDK.finalizeSdk();
          logger?.info('تم إغلاق AclasSDK');
        }

        for (final path in filesToClean) {
          try { await File(path).delete(); } catch (_) {}
        }

      } else if (conn == LabelScaleConnection.serial) {
        // ── Serial Mode ──
        logger?.info('Serial ترحيل عبر إلى ${com ?? "COM3"} @ ${baud ?? 9600}');
        final csvContent = _buildRongtaCSV(items);
        final csvBytes = transport.encodeCP1256(csvContent);
        logger?.info('بيانات CSV: ${csvBytes.length} بايت');

        serialPort = SerialPort(com ?? 'COM3', openNow: false, BaudRate: baud ?? 9600);
        await transport.configureSerial(serialPort, baud ?? 9600, dataBits, parity, stopBits);
        serialPort.open();
        logger?.success('تم فتح المنفذ التسلسلي');

        serialPort.writeBytesFromUint8List(Uint8List.fromList(csvBytes));
        logger?.sentBytes('بيانات CSV', Uint8List.fromList(csvBytes));
        await Future.delayed(const Duration(milliseconds: 500));

        // Check for response
        final resp = await serialPort.readBytes(64, timeout: const Duration(milliseconds: 2000));
        if (resp.isNotEmpty) {
          logger?.receivedBytes('رد Serial', Uint8List.fromList(resp));
          success = items.length;
        } else {
          failed = items.length;
          errors.add('لا استجابة من الميزان عبر Serial');
          logger?.error('لا استجابة عبر Serial');
        }

        logger?.info('تم إغلاق المنفذ التسلسلي');
      }
    } catch (e) {
      logger?.error('خطأ عام: $e');
      return PLUUploadResult(
        total: items.length, success: 0, failed: items.length,
        errors: ['خطأ في الاتصال: $e'],
      );
    } finally {
      try { await socket?.close(); } catch (_) {}
      try { serialPort?.close(); } catch (_) {}
    }

    return PLUUploadResult(
      total: items.length, success: success, failed: failed, errors: errors,
    );
  }

  /// Try FTP upload to Rongta scale using LabelScaleService's FTP implementation.
  Future<PLUUploadResult?> _tryRongtaFTP(
    String ip, int port, List<ScalePLUItem> items, String csvContent,
  ) async {
    try {
      debugPrint('[LabelScale] Trying Rongta FTP upload to $ip:$port...');

      // Check if FTP port is reachable first
      Socket? socket;
      try {
        socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 3));
        await socket.close();
      } catch (e) {
        // Surface the reachability failure so the user knows WHY FTP was skipped
        // (firewall, wrong IP, scale off, …) rather than silently falling through.
        final msg = 'FTP المنفذ $port غير قابل للوصول على $ip ($e)';
        debugPrint('[LabelScale] $msg');
        logger?.error(msg);
        return null;
      }

      // Delegate to LabelScaleService which has the ftpconnect package
      final result = await _connectAndUploadFTP(ip, port, items);
      return result;
    } catch (e) {
      final msg = 'FTP: خطأ غير متوقع — $e';
      debugPrint('[LabelScale] $msg');
      logger?.error(msg);
      return null;
    }
  }

  /// Delegate FTP upload to LabelScaleService which has the ftpconnect package.
  Future<PLUUploadResult?> _connectAndUploadFTP(
    String ip, int port, List<ScalePLUItem> items,
    {String? username, String? password}
  ) async {
    try {
      debugPrint('[LabelScale] Delegating FTP upload to LabelScaleService: $ip:$port');
      final result = await LabelScaleService.instance.uploadViaFTP(
        scale: LabelScale(
          id: 0,
          name: 'Rongta FTP',
          brand: 'rongta',
          connectionType: 'ftp',
          ipAddress: ip,
          port: port,
          maxPlu: 9999,
          ftpUsername: username ?? 'anonymous',
          ftpPassword: password ?? '',
          isActive: true,
          baudRate: 9600,
          dataBits: 8,
          parity: 'none',
          stopBits: 'one',
          handShake: 'none',
          createdAt: DateTime.now(),
        ),
        items: items,
      );
      return result;
    } catch (e) {
      // Authentication errors or protocol mismatches surface here — make
      // them visible in the progress log so the user can fix credentials.
      final msg = 'FTP: فشل تسجيل الدخول أو رفع الملف — $e';
      debugPrint('[LabelScale] $msg');
      logger?.error(msg);
      return null;
    }
  }

  /// Probe a list of TCP ports on the scale and report which are open.
  /// Useful for diagnosing which upload protocols the scale supports.
  ///
  /// Returns list of open ports. Each port gets a 2-second timeout.
  Future<List<int>> _probePorts(String ip, List<int> ports) async {
    final open = <int>[];
    logger?.info('فحص البورتات على $ip: ${ports.join(", ")}');
    // Run probes in parallel — much faster than serial (was 40+ sec)
    final results = await Future.wait(ports.map((port) async {
      try {
        final sock = await Socket.connect(
          ip, port,
          timeout: const Duration(seconds: 2),
        );
        await sock.close();
        return port;
      } catch (_) {
        return -1;
      }
    }));
    for (int i = 0; i < ports.length; i++) {
      if (results[i] > 0) {
        open.add(ports[i]);
        logger?.success('  Port ${ports[i]}: مفتوح ✓');
      } else {
        logger?.info('  Port ${ports[i]}: مغلق');
      }
    }
    return open;
  }

  /// Grab banner from an open port to identify the service (FTP, SSH, HTTP, etc.)
  /// Returns the banner text (first line) or null if no banner received.
  Future<String?> _grabBanner(String ip, int port) async {
    Socket? sock;
    try {
      sock = await Socket.connect(
        ip, port,
        timeout: const Duration(seconds: 3),
      );
      final completer = Completer<String?>();
      final buf = BytesBuilder();
      final sub = sock.listen(
        buf.add,
        onDone: () {
          if (!completer.isCompleted) completer.complete(_decodeBanner(buf.toBytes()));
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
      );
      // Wait up to 2 seconds for a banner
      Timer(const Duration(seconds: 2), () {
        if (!completer.isCompleted) {
          completer.complete(buf.length > 0 ? _decodeBanner(buf.toBytes()) : null);
        }
      });
      final banner = await completer.future;
      await sub.cancel();
      return banner;
    } catch (_) {
      return null;
    } finally {
      try { await sock?.close(); } catch (_) {}
    }
  }

  String _decodeBanner(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final text = String.fromCharCodes(bytes.take(200)).trim();
    // Keep just first line for clarity
    final firstLine = text.split(RegExp(r'[\r\n]')).first;
    return firstLine;
  }

  /// Identify services on open ports by grabbing their banners.
  /// Reports what each port is running: FTP, SSH, HTTP, unknown, etc.
  Future<Map<int, String>> _identifyServices(String ip, List<int> openPorts) async {
    final services = <int, String>{};
    logger?.info('تحديد نوع الخدمة على كل بورت مفتوح...');
    for (final port in openPorts) {
      final banner = await _grabBanner(ip, port);
      String service;
      if (banner == null || banner.isEmpty) {
        service = 'silent (بلا banner)';
      } else if (banner.startsWith('220')) {
        service = 'FTP: $banner';
      } else if (banner.startsWith('SSH-')) {
        service = 'SSH: $banner';
      } else if (banner.startsWith('HTTP/')) {
        service = 'HTTP: $banner';
      } else if (banner.contains('login') || banner.contains('Login')) {
        service = 'Telnet: $banner';
      } else {
        service = 'unknown: $banner';
      }
      services[port] = service;
      logger?.info('  Port $port → $service');
    }
    return services;
  }

  /// Probe HTTP endpoint to identify server type (nginx, embedded, etc.).
  /// Returns Server header + body preview for diagnosis.
  Future<String?> _probeHttpServer(String ip, int port) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(Uri.parse('http://$ip:$port/'));
      final response = await request.close().timeout(const Duration(seconds: 5));
      final server = response.headers.value('server') ?? 'unknown';
      final body = await response.transform(utf8.decoder).take(1).join();
      final preview = body.length > 120 ? '${body.substring(0, 120)}...' : body;
      logger?.info('  GET / → HTTP ${response.statusCode}, Server: $server');
      if (preview.isNotEmpty) {
        logger?.info('  محتوى الصفحة: $preview');
      }
      return '$server | ${response.statusCode}';
    } catch (e) {
      logger?.info('  GET / فشل: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// Try HTTP upload on common ports/endpoints used by Chinese label scales.
  ///
  /// Tests multiple upload patterns:
  ///   1. Multipart form-data POST (web admin style)
  ///   2. Raw CSV POST (REST API style)
  ///   3. PUT request (direct file upload)
  ///
  /// Tries ports 80, 8080, 8888 and common endpoints. Each successful
  /// attempt returns a PLUUploadResult; failures are logged and continue.
  Future<PLUUploadResult?> _tryHttpUpload(
    String ip,
    List<ScalePLUItem> items,
    String csvContent, {
    List<int>? ports,
    List<String>? endpoints,
  }) async {
    // Scan ALL common ports used by Chinese label scales + user-configured
    final testPorts = ports ?? [
      80, 8080, 8888, 8000, 5000,        // HTTP common
      4001, 4000, 9100, 9101, 9200,      // Scale/printer TCP
      5001, 5002, 6001, 7001,            // Aclas UDP/TCP
      8001, 8010, 443, 23, 22,           // Extra + auth
    ];
    final testEndpoints = endpoints ?? [
      '/plu',
      '/upload',
      '/uploadplu',
      '/uploadPLU',
      '/upload_plu',
      '/uploadfile',
      '/upload_file',
      '/cgi-bin/plu',
      '/cgi-bin/plu.cgi',
      '/cgi-bin/uploadplu.cgi',
      '/cgi-bin/upload.cgi',
      '/api/plu',
      '/api/v1/plu',
      '/api/plu/upload',
      '/data/plu',
      '/data/plu.txt',
      '/webadmin/plu',
      '/admin/plu',
      '/setting/plu',
    ];

    // Step 1: Probe open ports
    logger?.info('مرحلة 1: فحص البورتات المتاحة...');
    final openPorts = await _probePorts(ip, testPorts);
    if (openPorts.isEmpty) {
      logger?.error('لا يوجد بورت HTTP مفتوح على $ip');
      return null;
    }

    final csvBytes = utf8.encode(csvContent);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);

    try {
      for (final port in openPorts) {
        logger?.section('HTTP على Port $port');

        // Step 2: Identify the server to help diagnosis
        await _probeHttpServer(ip, port);

        // Step 3: Try each endpoint with different upload strategies
        for (final path in testEndpoints) {
          final url = 'http://$ip:$port$path';

          // ── Strategy A: Multipart form-data POST ──
          final multipartResult = await _tryHttpPostMultipart(
            client, url, csvContent, items.length,
          );
          if (multipartResult != null) return multipartResult;

          // ── Strategy B: Raw CSV POST ──
          final rawResult = await _tryHttpPostRaw(
            client, url, csvBytes, items.length,
          );
          if (rawResult != null) return rawResult;
        }
      }
    } finally {
      client.close();
    }

    logger?.error('كل محاولات HTTP فشلت على البورتات: ${openPorts.join(", ")}');
    return null;
  }

  /// Send multipart/form-data POST with the CSV as a file part.
  Future<PLUUploadResult?> _tryHttpPostMultipart(
    HttpClient client,
    String url,
    String csvContent,
    int itemCount,
  ) async {
    try {
      final request = await client.postUrl(Uri.parse(url));
      final boundary = '----UralCash${DateTime.now().microsecondsSinceEpoch}';
      request.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');

      final body = StringBuffer();
      body.write('--$boundary\r\n');
      body.write('Content-Disposition: form-data; name="file"; filename="plu.csv"\r\n');
      body.write('Content-Type: text/csv\r\n\r\n');
      body.write(csvContent);
      body.write('\r\n--$boundary--\r\n');

      final bodyBytes = utf8.encode(body.toString());
      request.headers.set('Content-Length', bodyBytes.length.toString());
      request.add(bodyBytes);

      final response = await request.close().timeout(const Duration(seconds: 5));
      final respBody = await response.transform(utf8.decoder).join();
      final preview = respBody.length > 100 ? '${respBody.substring(0, 100)}...' : respBody;

      logger?.info('POST multipart $url → ${response.statusCode}${preview.isNotEmpty ? " ($preview)" : ""}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        logger?.success('✓ ترحيل ناجح عبر HTTP multipart: $url');
        return PLUUploadResult(
          total: itemCount, success: itemCount, failed: 0,
        );
      }
    } catch (_) {
      // Silent — endpoint may not exist; keep trying others
    }
    return null;
  }

  /// Send raw CSV as POST body (REST API style).
  Future<PLUUploadResult?> _tryHttpPostRaw(
    HttpClient client,
    String url,
    List<int> csvBytes,
    int itemCount,
  ) async {
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.set('Content-Type', 'text/csv; charset=utf-8');
      request.headers.set('Content-Length', csvBytes.length.toString());
      request.add(csvBytes);

      final response = await request.close().timeout(const Duration(seconds: 5));
      final respBody = await response.transform(utf8.decoder).join();
      final preview = respBody.length > 100 ? '${respBody.substring(0, 100)}...' : respBody;

      logger?.info('POST raw $url → ${response.statusCode}${preview.isNotEmpty ? " ($preview)" : ""}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        logger?.success('✓ ترحيل ناجح عبر HTTP raw: $url');
        return PLUUploadResult(
          total: itemCount, success: itemCount, failed: 0,
        );
      }
    } catch (_) {
      // Silent
    }
    return null;
  }

  /// Try Rongta RLS 0110 binary TCP upload on the configured port.
  ///
  /// Tries 4 frame variants since different Rongta RLS firmwares differ:
  ///   V1: STX + "0110" + PLU(99) + ETX + LRC
  ///   V2: STX + "0110" + PLU(99) + ETX (no LRC)
  ///   V3: "0110" + PLU(99) + CR LF
  ///   V4: Just the 99-byte PLU record + CR LF (simplest)
  ///
  /// Returns success if ANY variant gets ACK (0x06) or echo-confirmation
  /// from the scale for ALL items.
  Future<PLUUploadResult?> _tryRongtaTCP0110(
    String ip, int port, List<ScalePLUItem> items,
  ) async {
    // Try the 4 frame variants in order of likelihood
    final variants = [
      _RongtaFrame.stxCmdDataEtxLrc,
      _RongtaFrame.stxCmdDataEtx,
      _RongtaFrame.cmdDataCrLf,
      _RongtaFrame.dataCrLf,
    ];

    for (final variant in variants) {
      logger?.info('تجربة صيغة الإطار: ${variant.name}');
      Socket? socket;
      try {
        socket = await transport.connectTCP(ip, port);
        logger?.success('تم الاتصال TCP بـ $ip:$port (${variant.name})');

        // Drain any banner/welcome bytes
        final banner = await transport.readResponse(
          socket, timeout: const Duration(seconds: 1),
        );
        if (banner.isNotEmpty) {
          logger?.receivedBytes('ترحيب', banner);
        }

        int success = 0;
        int failed = 0;
        final errors = <String>[];

        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          logger?.pluItem(i + 1, items.length, item.pluNumber, item.name,
              item.unitPrice, item.isByWeight, item.barcode ?? '');
          try {
            final record99 = _buildRongtaPLURecord(item);
            final frame = _wrapRongtaFrame(record99, variant);
            logger?.sentBytes('PLU ${item.pluNumber} (${variant.name})', frame);

            socket.add(frame);
            await socket.flush();

            final response = await transport.readResponse(
              socket, timeout: const Duration(seconds: 3),
            );

            if (response.isEmpty) {
              failed++;
              errors.add('PLU ${item.pluNumber}: لا استجابة');
              logger?.error('PLU ${item.pluNumber}: لا رد');
              // If scale doesn't respond at all → variant is probably wrong, abort early
              if (i == 0) {
                logger?.info('الميزان لا يرد على ${variant.name} — تجربة الصيغة التالية');
                break;
              }
              continue;
            }

            logger?.receivedBytes('رد PLU ${item.pluNumber}', response);

            // Check for ACK, NAK, or echo-back success
            final first = response[0];
            if (first == 0x06) {
              success++;
              logger?.success('PLU ${item.pluNumber}: ACK ✓');
            } else if (first == 0x15) {
              failed++;
              errors.add('PLU ${item.pluNumber}: NAK');
              logger?.error('PLU ${item.pluNumber}: NAK');
            } else if (_isEchoBackSuccess(frame, response)) {
              // IMPORTANT: Echo-back is TCP buffer reflection, NOT a protocol ACK.
              // On Fire Bird scales, echo was received but HotKey says "not
              // define PLU" — proving the data was received but not stored.
              // Count as FAILURE so we fall through to other strategies.
              failed++;
              errors.add('PLU ${item.pluNumber}: echo-back فقط (بدون تأكيد تخزين)');
              logger?.warning('PLU ${item.pluNumber}: echo-back فقط — التخزين غير مؤكد ✗');
            } else {
              failed++;
              final txt = String.fromCharCodes(response.where((b) => b >= 0x20 && b < 0x7F));
              errors.add('PLU ${item.pluNumber}: رد غير معروف (${response.length} بايت): $txt');
              logger?.warning('PLU ${item.pluNumber}: رد: $txt');
            }
          } catch (e) {
            failed++;
            errors.add('PLU ${item.pluNumber}: $e');
            logger?.error('PLU ${item.pluNumber}: خطأ — $e');
          }
          onProgress?.call(i + 1, items.length);
        }

        await socket.close();

        // If we got any successes, this variant works — return result
        if (success > 0) {
          logger?.success('صيغة ${variant.name} نجحت: $success من ${items.length}');
          return PLUUploadResult(
            total: items.length, success: success, failed: failed, errors: errors,
          );
        }

        logger?.info('صيغة ${variant.name} فشلت (كلها): ${errors.isNotEmpty ? errors.first : "لا استجابة"}');
      } catch (e) {
        logger?.error('خطأ فى ${variant.name}: $e');
      } finally {
        try { await socket?.close(); } catch (_) {}
      }
    }

    return null;  // All variants failed
  }

  /// Try CSV-over-TCP upload on the configured port (default 4001).
  ///
  /// Sends the entire CSV as a single TCP payload with various framing:
  ///   V1: Raw CSV (no wrapper)
  ///   V2: "UPLOAD\r\n" + CSV + "END\r\n"
  ///   V3: STX + "PLU_CSV" + CSV + ETX
  ///   V4: "PLUSTART\r\n" + CSV + "PLUEND\r\n"
  ///
  /// Since the scale doesn't ACK individual PLUs in CSV mode, we upload
  /// everything at once and then verify by requesting a PLU back (if supported).
  Future<PLUUploadResult?> _tryCsvOverTcp(
    String ip, int port, List<ScalePLUItem> items,
  ) async {
    final csv = _buildRongtaCSV(items);
    // Use UTF-16 LE + BOM (matches PLU Manager export format verified from 2.xls)
    final csvBytes = _encodeRongtaCsvUtf16(csv);

    final variants = <_CsvFrame>[
      _CsvFrame('Raw CSV', (b) => b),
      _CsvFrame('UPLOAD header', (b) => [
        ...utf8.encode('UPLOAD\r\n'), ...b, ...utf8.encode('END\r\n'),
      ]),
      _CsvFrame('STX PLU_CSV wrapper', (b) => [
        0x02, ...utf8.encode('PLU_CSV\r\n'), ...b, 0x03,
      ]),
      _CsvFrame('PLUSTART/PLUEND', (b) => [
        ...utf8.encode('PLUSTART\r\n'), ...b, ...utf8.encode('PLUEND\r\n'),
      ]),
    ];

    for (final variant in variants) {
      logger?.info('تجربة صيغة CSV: ${variant.name}');
      Socket? socket;
      try {
        socket = await transport.connectTCP(ip, port);
        logger?.success('تم الاتصال TCP بـ $ip:$port (${variant.name})');

        // Drain any welcome
        final banner = await transport.readResponse(
          socket, timeout: const Duration(seconds: 1),
        );
        if (banner.isNotEmpty) {
          logger?.receivedBytes('ترحيب', banner);
        }

        // Build framed payload and send
        final payload = Uint8List.fromList(variant.wrap(csvBytes));
        logger?.info('إرسال ${payload.length} بايت CSV (${items.length} صنف)');
        socket.add(payload);
        await socket.flush();

        // Give scale time to process
        await Future.delayed(const Duration(seconds: 2));

        // Read response
        final response = await transport.readResponse(
          socket, timeout: const Duration(seconds: 5),
        );

        if (response.isEmpty) {
          logger?.info('${variant.name}: لا استجابة — التجربة التالية');
          continue;
        }

        logger?.receivedBytes('رد ${variant.name}', response);
        final text = String.fromCharCodes(
          response.where((b) => b >= 0x20 && b < 0x7F),
        );

        // Look for success indicators in the response
        final lower = text.toLowerCase();
        final hasSuccess = response.contains(0x06) ||  // ACK
            lower.contains('ok') ||
            lower.contains('success') ||
            lower.contains('done') ||
            lower.contains('plu') && (lower.contains('${items.length}'));

        if (hasSuccess) {
          logger?.success('✓ ${variant.name} رد بنجاح: $text');
          return PLUUploadResult(
            total: items.length, success: items.length, failed: 0,
          );
        } else {
          logger?.info('${variant.name}: رد غير مؤكد: $text');
        }
      } catch (e) {
        logger?.info('${variant.name}: خطأ — $e');
      } finally {
        try { await socket?.close(); } catch (_) {}
      }
    }

    return null;
  }

  /// Wrap a 99-char PLU record in one of 4 Rongta TCP frame formats.
  Uint8List _wrapRongtaFrame(String record99, _RongtaFrame variant) {
    final dataBytes = <int>[];
    // Encode record as ASCII — it's all printable chars
    for (final c in record99.codeUnits) {
      dataBytes.add(c & 0xFF);
    }

    switch (variant) {
      case _RongtaFrame.stxCmdDataEtxLrc:
        // STX + "0110" + data + ETX + LRC (XOR of all bytes between STX/ETX exclusive)
        final body = <int>[...'0110'.codeUnits, ...dataBytes];
        int lrc = 0;
        for (final b in body) {
          lrc ^= b;
        }
        lrc ^= 0x03; // Include ETX in LRC per common scale conventions
        return Uint8List.fromList([0x02, ...body, 0x03, lrc]);

      case _RongtaFrame.stxCmdDataEtx:
        return Uint8List.fromList([
          0x02, ...'0110'.codeUnits, ...dataBytes, 0x03,
        ]);

      case _RongtaFrame.cmdDataCrLf:
        return Uint8List.fromList([
          ...'0110'.codeUnits, ...dataBytes, 0x0D, 0x0A,
        ]);

      case _RongtaFrame.dataCrLf:
        return Uint8List.fromList([...dataBytes, 0x0D, 0x0A]);
    }
  }

  /// Build a single PLU record in Rongta RLS official ASCII HEX format.
  /// Total: 99 ASCII chars per record (command 0110 data payload).
  ///
  /// Fields from RLS1000 Software Manual Section 2.5:
  ///   Operate(1) + Rank(2) + Name(36) + FreshCode(6) + ArtNo(10) +
  ///   BarcodeType(2) + UnitPrice(8) + WeighUnit(1) + Dept(2) +
  /// Check if a response is just an echo of the sent data (port 4001 behavior).
  /// Strip echo prefix from port 4001 responses.
  /// Port 4001 echoes sent data (sometimes with 1-byte offset) followed by
  /// zero-padding, then the scale's real response.
  /// Returns the non-echo portion (may be empty if truly just echo).
  List<int> _stripEcho(Uint8List sent, Uint8List received) {
    if (received.isEmpty) return [];

    // Find where the echo ends — check direct match and 1-byte offset
    int echoEnd = 0;

    // Direct match: received starts with sent bytes
    if (received.length >= sent.length) {
      bool match = true;
      for (int i = 0; i < sent.length; i++) {
        if (sent[i] != received[i]) { match = false; break; }
      }
      if (match) echoEnd = sent.length;
    }

    // 1-byte offset match: received starts with sent[1:]
    if (echoEnd == 0 && received.length >= sent.length - 1 && sent.length > 1) {
      bool match = true;
      for (int i = 0; i < sent.length - 1; i++) {
        if (sent[i + 1] != received[i]) { match = false; break; }
      }
      if (match) echoEnd = sent.length - 1;
    }

    if (echoEnd == 0) return received.toList(); // No echo detected

    // Skip zero-padding after echo
    int dataStart = echoEnd;
    while (dataStart < received.length && received[dataStart] == 0x00) {
      dataStart++;
    }

    if (dataStart >= received.length) return []; // Only echo + zeros
    return received.sublist(dataStart).toList();
  }

  ///   TareWeight(6) + SavingPeriod(3) + PackType(1) + PackWeight(6) +
  ///   PackError(2) + Msg1(3) + Msg2(3) + MultiBarcode(3) +
  ///   Discount(3) + SalesMark(1) + DiscountMark(1) = 99
  String _buildRongtaPLURecord(ScalePLUItem item) {
    final buf = StringBuffer();

    // Operate: 'I' = insert/update, 'D' = delete
    buf.write('I');

    // Rank: PLU number (2 chars, zero-padded)
    buf.write(item.pluNumber.toString().padLeft(2, '0'));

    // Name: 36 chars, padded with spaces
    // Use CP1256 hex representation for Arabic names
    String name = item.name;
    if (name.length > 36) name = name.substring(0, 36);
    buf.write(name.padRight(36));

    // Fresh food code: 6 chars (PLU number padded)
    buf.write(item.pluNumber.toString().padLeft(6, '0'));

    // Art. No.: 10 chars (product code or barcode)
    final artNo = item.productCode ?? item.pluNumber.toString();
    buf.write(artNo.padLeft(10, '0'));

    // Barcode type: 2 chars
    // Refer to barcode format: "02" for weight, "01" for count
    buf.write(item.isByWeight ? '02' : '01');

    // Unit price: 8 chars, no decimal
    // e.g., 3.49 → 349, 1.50 → 150
    final priceInt = (item.unitPrice * 100).round();
    buf.write(priceInt.toString().padLeft(8, '0'));

    // Weighing unit: 1 char
    // 0=50g, 1=g, 2=10g, 3=100g, 4=kg, 5=oz, 6=lb,
    // 9=PCS(g), A=PCS(Kg)
    buf.write(item.isByWeight ? '4' : 'A');

    // Dept.: 2 chars
    buf.write(item.department.toString().padLeft(2, '0'));

    // Tare weight: 6 chars (within 15Kg, logic conversion)
    final tareInt = (item.tareWeight * 1000).round();
    buf.write(tareInt.toString().padLeft(6, '0'));

    // Saving period: 3 chars (0-365)
    buf.write('000');

    // Packing type: 1 char (0=normal)
    buf.write('0');

    // Packing weight: 6 chars
    buf.write('000000');

    // Packing error: 2 chars (0-20)
    buf.write('00');

    // Message 1: 3 chars (0-197)
    buf.write('000');

    // Message 2: 3 chars (0-197)
    buf.write('000');

    // Multi-barcode: 3 chars (0-255)
    buf.write('000');

    // Discount: 3 chars (0-99)
    buf.write('000');

    // Sales mark: 1 char
    buf.write('0');

    // Discount mark: 1 char
    buf.write('0');

    return buf.toString();
  }

  /// Build Rongta PLU Manager file in the EXACT official format.
  ///
  /// Verified against real `release_trial/2.xls` export (2026-04-13):
  ///   - **TAB-separated** (not CSV)
  ///   - **UTF-16 LE with BOM** + **CRLF** line endings
  ///   - **24 columns** (not 20)
  ///   - Column names with SPACES: "Unit Price", "Barcode Type", etc.
  ///   - No leading "NUM" column — "Hotkey" is the first column
  ///
  /// Header columns (order matters):
  ///   Hotkey | Name | LFCode | Code | Barcode Type | Unit Price |
  ///   Unit Weight | Unit Amount | Department | PT Weight | Shelf Time |
  ///   Pack Type | Tare | Error(%) | Message1 | Message2 | Label |
  ///   Discount/Table | Account | sPluFieldTitle20 | Account |
  ///   Recommend days | nutrition | Ice(%)
  String _buildRongtaCSV(List<ScalePLUItem> items) {
    final buf = StringBuffer();

    // Header — exact columns from PLU Manager export, TAB-separated, CRLF
    buf.write(
      'Hotkey\tName\tLFCode\tCode\tBarcode Type\tUnit Price\t'
      'Unit Weight\tUnit Amount\tDepartment\tPT Weight\tShelf Time\t'
      'Pack Type\tTare\tError(%)\tMessage1\tMessage2\tLabel\t'
      'Discount/Table\tAccount\tsPluFieldTitle20\tAccount\t'
      'Recommend days\tnutrition\tIce(%)\r\n',
    );

    for (final item in items) {
      final plu = item.pluNumber;
      final reversedName = ScaleTransport.reverseArabicForScale(item.name);
      // PLU Manager uses tab-separated fields — no CSV quoting, but must
      // sanitize embedded tabs in product name to prevent column break.
      final name = reversedName.replaceAll('\t', ' ').replaceAll('\r', '')
          .replaceAll('\n', ' ');
      final price = item.unitPrice.toStringAsFixed(AppConstants.decimalPlaces);
      final dept = item.department;
      final unit = item.isByWeight ? 'Kg' : 'PCS';
      final tare = item.tareWeight.toStringAsFixed(3);
      final barcodeType = item.isByWeight ? 2 : 1;
      final packType = item.isByWeight ? 15 : 0;
      final lfCode = plu;
      final code = (item.barcode != null && item.barcode!.isNotEmpty)
          ? item.barcode!
          : '${dept.toString().padLeft(2, '0')}${plu.toString().padLeft(5, '0')}';

      buf.write(
        '$plu\t'           // Hotkey (physical button position)
        '$name\t'          // Name
        '$lfCode\t'        // LFCode (label format code)
        '$code\t'          // Code (7-digit scale barcode)
        '$barcodeType\t'   // Barcode Type (2=weight, 1=price)
        '$price\t'         // Unit Price
        '$unit\t'          // Unit Weight ("Kg" or "PCS")
        '0\t'              // Unit Amount
        '$dept\t'          // Department
        '0.000\t'          // PT Weight (pre-tare)
        '\t'               // Shelf Time (empty)
        '$packType\t'      // Pack Type
        '$tare\t'          // Tare
        '0.000\t'          // Error(%)
        '0\t'              // Message1
        '0\t'              // Message2
        '0\t'              // Label
        '0\t'              // Discount/Table
        '0\t'              // Account
        '0\t'              // sPluFieldTitle20
        '0\t'              // Account (duplicated in PLU Manager!)
        '0\t'              // Recommend days
        '0\t'              // nutrition
        '0\r\n',           // Ice(%) + CRLF
      );
    }
    return buf.toString();
  }

  /// Encode Rongta CSV content as UTF-16 LE with BOM (matches PLU Manager output).
  /// Returns bytes ready to write to disk or send over TCP.
  Uint8List _encodeRongtaCsvUtf16(String csvContent) {
    final bytes = <int>[0xFF, 0xFE]; // UTF-16 LE BOM
    for (final cu in csvContent.codeUnits) {
      bytes.add(cu & 0xFF);
      bytes.add((cu >> 8) & 0xFF);
    }
    return Uint8List.fromList(bytes);
  }

  // ═══════════════════════════════════════════════════════════════
  // Aclas LS2X/LS6X Protocol
  // ═══════════════════════════════════════════════════════════════

  Future<PLUUploadResult> _uploadAclas(
    List<ScalePLUItem> items,
    LabelScaleConnection conn,
    String? ip, int? port, String? com, int? baud,
    int? dataBits, String? parity, String? stopBits,
  ) async {
    int success = 0;
    int failed = 0;
    final errors = <String>[];

    logger?.section('Aclas — بدء الاتصال');
    logger?.info('الهدف: ${conn == LabelScaleConnection.serial ? (com ?? "COM3") : "${ip ?? "192.168.1.100"}:${port ?? 8000}"} | الاتصال: $conn');

    Socket? socket;
    dynamic serialPort;
    try {
      if (conn == LabelScaleConnection.serial) {
        serialPort = SerialPort(com ?? 'COM3', openNow: false, BaudRate: baud ?? 9600);
        await transport.configureSerial(serialPort, baud ?? 9600, dataBits, parity, stopBits);
        serialPort.open();
        logger?.success('تم فتح المنفذ التسلسلي ${com ?? "COM3"}');

        final startCmd = Uint8List.fromList([0x02, ...utf8.encode('PLUSTART'), 0x03]);
        serialPort.writeBytesFromUint8List(startCmd);
        logger?.sentBytes('PLUSTART', startCmd);
        await Future.delayed(const Duration(milliseconds: 300));

        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          logger?.pluItem(i + 1, items.length, item.pluNumber, item.name, item.unitPrice, item.isByWeight, item.barcode ?? '');
          try {
            final cmd = _buildAclasPLURecord(item);
            logger?.sentBytes('PLU ${item.pluNumber}', cmd);
            serialPort.writeBytesFromUint8List(cmd);
            await Future.delayed(const Duration(milliseconds: 100));

            final resp = await serialPort.readBytes(64, timeout: const Duration(milliseconds: 1500));
            final respStr = resp.isNotEmpty ? String.fromCharCodes(resp).trim() : '';
            if (resp.isNotEmpty) logger?.receivedBytes('رد PLU ${item.pluNumber}', Uint8List.fromList(resp));
            if (respStr.startsWith('OK')) {
              success++;
              logger?.success('PLU ${item.pluNumber}: OK — تم القبول');
            } else if (respStr.startsWith('ER')) {
              failed++;
              errors.add('PLU ${item.pluNumber}: رفض الميزان (ER)');
              logger?.error('PLU ${item.pluNumber}: ER — رفض');
            } else if (resp.isNotEmpty) {
              failed++;
              errors.add('PLU ${item.pluNumber}: رد غير معروف: $respStr');
              logger?.warning('PLU ${item.pluNumber}: رد غير معروف: $respStr — فشل');
            } else {
              failed++;
              errors.add('PLU ${item.pluNumber}: لا استجابة من الميزان');
              logger?.error('PLU ${item.pluNumber}: لا استجابة — فشل');
            }
          } catch (e) {
            failed++;
            errors.add('PLU ${item.pluNumber}: $e');
            logger?.error('PLU ${item.pluNumber}: خطأ — $e');
          }
          onProgress?.call(i + 1, items.length);
        }

        final endCmd = Uint8List.fromList([0x02, ...utf8.encode('PLUEND'), 0x03]);
        serialPort.writeBytesFromUint8List(endCmd);
        logger?.sentBytes('PLUEND', endCmd);
        await Future.delayed(const Duration(milliseconds: 200));
        logger?.info('تم إغلاق المنفذ التسلسلي');
      } else {
        logger?.info('جاري الاتصال TCP...');
        socket = await transport.connectTCP(ip ?? '192.168.1.100', port ?? 8000);
        logger?.success('تم الاتصال TCP بنجاح');

        final startCmd = Uint8List.fromList(utf8.encode('\x02PLUSTART\x03'));
        socket.add(startCmd);
        await socket.flush();
        logger?.sentBytes('PLUSTART', startCmd);
        await Future.delayed(const Duration(milliseconds: 300));

        final r = await _uploadPLUOverTCP(
          socket: socket, items: items,
          buildRecord: _buildAclasPLURecord,
          interpret: _interpretTextOKER,
          delimiter: 0x03,
        );
        success = r.success; failed = r.failed; errors.addAll(r.errors);

        socket.add(utf8.encode('\x02PLUEND\x03'));
        await socket.flush();
        logger?.sentBytes('PLUEND', Uint8List.fromList(utf8.encode('\x02PLUEND\x03')));
        logger?.info('تم إغلاق اتصال TCP');
      }
    } catch (e) {
      logger?.error('خطأ في الاتصال: $e');
      return PLUUploadResult(
        total: items.length, success: 0, failed: items.length,
        errors: ['خطأ في الاتصال: $e'],
      );
    } finally {
      try { await socket?.close(); } catch (_) {}
      try { serialPort?.close(); } catch (_) {}
    }

    return PLUUploadResult(
      total: items.length, success: success, failed: failed, errors: errors,
    );
  }

  /// Build an Aclas PLU record
  /// Format: <STX>PLU:<plu>,<dept>,<type>,<name>,<price>,<tare><ETX>
  Uint8List _buildAclasPLURecord(ScalePLUItem item) {
    final type = item.isByWeight ? 'W' : 'C';
    final price = (item.unitPrice * 100).round();
    final tare = (item.tareWeight * 1000).round();
    final nameEncoded = transport.encodeCP1256(transport.padRight(
      ScaleTransport.reverseArabicForScale(item.name), 24,
    ));

    final List<int> bytes = [];
    bytes.addAll(utf8.encode('\x02PLU:${item.pluNumber},${item.department},$type,'));
    bytes.addAll(nameEncoded);
    bytes.addAll(utf8.encode(',$price,$tare\x03'));

    return Uint8List.fromList(bytes);
  }

  // ═══════════════════════════════════════════════════════════════
  // Mettler Toledo bPlus/bRite Protocol
  // ═══════════════════════════════════════════════════════════════

  Future<PLUUploadResult> _uploadMettlerToledo(
    List<ScalePLUItem> items,
    LabelScaleConnection conn,
    String? ip, int? port, String? com, int? baud,
    int? dataBits, String? parity, String? stopBits,
  ) async {
    int success = 0;
    int failed = 0;
    final errors = <String>[];

    logger?.section('Mettler Toledo — بدء الاتصال');
    logger?.info('الهدف: ${conn == LabelScaleConnection.serial ? (com ?? "COM3") : "${ip ?? "192.168.1.100"}:${port ?? 252}"} | الاتصال: $conn');

    Socket? socket;
    dynamic serialPort;
    try {
      if (conn == LabelScaleConnection.serial) {
        serialPort = SerialPort(com ?? 'COM3', openNow: false, BaudRate: baud ?? 9600);
        await transport.configureSerial(serialPort, baud ?? 9600, dataBits, parity, stopBits);
        serialPort.open();
        logger?.success('تم فتح المنفذ التسلسلي ${com ?? "COM3"}');

        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          logger?.pluItem(i + 1, items.length, item.pluNumber, item.name, item.unitPrice, item.isByWeight, item.barcode ?? '');
          try {
            final cmd = _buildMettlerToledoPLURecord(item);
            logger?.sentBytes('PLU ${item.pluNumber}', cmd);
            serialPort.writeBytesFromUint8List(cmd);
            await Future.delayed(const Duration(milliseconds: 100));

            final resp = await serialPort.readBytes(64, timeout: const Duration(milliseconds: 1500));
            if (resp.isNotEmpty) {
              logger?.receivedBytes('رد PLU ${item.pluNumber}', Uint8List.fromList(resp));
              if (resp[0] == 0x06) {
                success++;
                logger?.success('PLU ${item.pluNumber}: ACK — تم القبول');
              } else if (resp[0] == 0x15) {
                failed++;
                errors.add('PLU ${item.pluNumber}: رفض الميزان (NAK)');
                logger?.error('PLU ${item.pluNumber}: NAK — رفض');
              } else {
                failed++;
                errors.add('PLU ${item.pluNumber}: رد غير معروف 0x${resp[0].toRadixString(16)}');
                logger?.warning('PLU ${item.pluNumber}: رد غير معروف — فشل');
              }
            } else {
              failed++;
              errors.add('PLU ${item.pluNumber}: لا استجابة من الميزان');
              logger?.error('PLU ${item.pluNumber}: لا استجابة — فشل');
            }
          } catch (e) {
            failed++;
            errors.add('PLU ${item.pluNumber}: $e');
            logger?.error('PLU ${item.pluNumber}: خطأ — $e');
          }
          onProgress?.call(i + 1, items.length);
        }

        logger?.info('تم إغلاق المنفذ التسلسلي');
      } else {
        logger?.info('جاري الاتصال TCP...');
        socket = await transport.connectTCP(ip ?? '192.168.1.100', port ?? 252);
        logger?.success('تم الاتصال TCP بنجاح');

        final r = await _uploadPLUOverTCP(
          socket: socket, items: items,
          buildRecord: _buildMettlerToledoPLURecord,
          interpret: _interpretACKNAK,
          delimiter: 0x0A,
        );
        success = r.success; failed = r.failed; errors.addAll(r.errors);

        logger?.info('تم إغلاق اتصال TCP');
      }
    } catch (e) {
      logger?.error('خطأ في الاتصال: $e');
      return PLUUploadResult(
        total: items.length, success: 0, failed: items.length,
        errors: ['خطأ في الاتصال: $e'],
      );
    } finally {
      try { await socket?.close(); } catch (_) {}
      try { serialPort?.close(); } catch (_) {}
    }

    return PLUUploadResult(
      total: items.length, success: success, failed: failed, errors: errors,
    );
  }

  /// Build a Mettler Toledo PLU record
  /// Format: PLU|plu_no|dept|type|name|unit_price|tare|barcode\r\n
  Uint8List _buildMettlerToledoPLURecord(ScalePLUItem item) {
    final type = item.isByWeight ? 'W' : 'C';
    final price = (item.unitPrice * 100).round();
    final tare = (item.tareWeight * 1000).round();
    final name = transport.padRight(
      ScaleTransport.reverseArabicForScale(item.name), 30,
    );
    final bc = item.barcode ?? '';

    final record = 'PLU|${item.pluNumber}|${item.department}|$type|$name|$price|$tare|$bc\r\n';
    return Uint8List.fromList(utf8.encode(record));
  }

  // ═══════════════════════════════════════════════════════════════
  // TEM Protocol (Serial-only, ASCII)
  // ═══════════════════════════════════════════════════════════════

  Future<PLUUploadResult> _uploadTEM(
    List<ScalePLUItem> items,
    LabelScaleConnection conn,
    String? ip, int? port, String? com, int? baud,
    int? dataBits, String? parity, String? stopBits,
  ) async {
    int success = 0;
    int failed = 0;
    final errors = <String>[];

    final effectiveIp = ip ?? '192.168.1.100';
    final effectivePort = port ?? 9100;

    logger?.section('TEM — بدء الاتصال');
    logger?.info('الهدف: ${conn == LabelScaleConnection.serial ? (com ?? "COM3") : "$effectiveIp:$effectivePort"} | الاتصال: $conn');

    Socket? socket;
    dynamic serialPort;
    try {
      if (conn == LabelScaleConnection.serial) {
        // ── Serial Mode ──
        serialPort = SerialPort(com ?? 'COM3', openNow: false, BaudRate: baud ?? 9600);
        await transport.configureSerial(serialPort, baud ?? 9600, dataBits, parity, stopBits);
        serialPort.open();
        logger?.success('تم فتح المنفذ التسلسلي ${com ?? "COM3"} بسرعة ${baud ?? 9600}');

        final startCmd = Uint8List.fromList([0x02, ...utf8.encode('PLUSTART'), 0x03]);
        serialPort.writeBytesFromUint8List(startCmd);
        logger?.sentBytes('PLUSTART', startCmd);
        await Future.delayed(const Duration(milliseconds: 300));

        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          logger?.pluItem(i + 1, items.length, item.pluNumber, item.name, item.unitPrice, item.isByWeight, item.barcode ?? '');
          try {
            final cmd = _buildTEMPLURecord(item);
            logger?.sentBytes('PLU ${item.pluNumber}', cmd);

            serialPort.writeBytesFromUint8List(cmd);
            await Future.delayed(const Duration(milliseconds: 100));

            final resp = await serialPort.readBytes(64, timeout: const Duration(milliseconds: 1500));
            if (resp.isNotEmpty) {
              logger?.receivedBytes('رد PLU ${item.pluNumber}', Uint8List.fromList(resp));
              if (resp[0] == 0x06) {
                success++;
                logger?.success('PLU ${item.pluNumber}: ACK — تم القبول');
              } else if (resp[0] == 0x15) {
                failed++;
                errors.add('PLU ${item.pluNumber}: رفض الميزان (NAK)');
                logger?.error('PLU ${item.pluNumber}: NAK — رفض');
              } else {
                failed++;
                errors.add('PLU ${item.pluNumber}: رد غير معروف 0x${resp[0].toRadixString(16)}');
                logger?.warning('PLU ${item.pluNumber}: رد غير معروف 0x${resp[0].toRadixString(16)} — فشل');
              }
            } else {
              failed++;
              errors.add('PLU ${item.pluNumber}: لا استجابة من الميزان');
              logger?.error('PLU ${item.pluNumber}: لا استجابة — فشل');
            }
          } catch (e) {
            failed++;
            errors.add('PLU ${item.pluNumber}: $e');
            logger?.error('PLU ${item.pluNumber}: خطأ — $e');
          }
          onProgress?.call(i + 1, items.length);
        }

        final endCmd = Uint8List.fromList([0x02, ...utf8.encode('PLUEND'), 0x03]);
        serialPort.writeBytesFromUint8List(endCmd);
        logger?.sentBytes('PLUEND', endCmd);
        await Future.delayed(const Duration(milliseconds: 200));
        logger?.info('تم إغلاق المنفذ التسلسلي');
      } else {
        // ══════════════════════════════════════════════════════════════
        // TEM TCP Upload Strategy:
        //   1. Try AclasSDK (UDP) with full sequence — works for Fire Bird,
        //      Rongta, and most Chinese Aclas-compatible scales
        //   2. Fallback to W36F01 binary over raw TCP (legacy CAS/TEM method)
        //
        // Most Chinese label scales (Fire Bird, etc.) use Aclas-compatible
        // firmware. The W36F01 binary protocol over raw TCP often just echoes
        // data without storing it. AclasSDK with prerequisite tables is the
        // reliable method.
        // ══════════════════════════════════════════════════════════════

        // ── Strategy 0: HTTP Upload (check for modern scale web admin) ──
        logger?.section('محاولة 1: HTTP (البورتات 8080/80/8888)');
        logger?.info('فحص إمكانية الترحيل عبر HTTP قبل AclasSDK...');
        final temHttpResult = await _tryHttpUpload(
          effectiveIp, items, _buildRongtaCSV(items),
        );
        if (temHttpResult != null && temHttpResult.success > 0) {
          logger?.success('HTTP: تم رفع ${temHttpResult.success} صنف بنجاح!');
          success = temHttpResult.success;
          return PLUUploadResult(
            total: items.length, success: success, failed: 0, errors: errors,
          );
        }
        logger?.info('HTTP غير متاح — جاري تجربة AclasSDK...');

        // ── Strategy 1: AclasSDK with full sequence (Department → Unit → PLU → HotKey) ──
        logger?.section('محاولة 2: AclasSDK (UDP) — التسلسل الكامل');
        logger?.info('جاري تجربة AclasSDK مع جداول المتطلبات (الأقسام/الوحدات/المجموعات)...');
        bool aclasAttempted = false;
        bool aclasSucceeded = false;

        try {
          if (AclasSDK.load() && AclasSDK.initialize()) {
            aclasAttempted = true;
            final deviceInfo = AclasSDK.getDeviceInfo(effectiveIp);
            if (deviceInfo != null) {
              logger?.success('تم كشف الميزان عبر AclasSDK: بروتوكول=${deviceInfo.protocolType}, '
                  'منفذ=${deviceInfo.port}');

              final temTs = DateTime.now().millisecondsSinceEpoch;
              final temTempDir = Directory.systemTemp;
              final temFilesToClean = <String>[];

              // Generate prerequisite files
              final deptIds = items.map((e) => e.department).toSet();
              final temDeptPath = '${temTempDir.path}\\tem_dept_$temTs.txt';
              await AclasSDK.generateDepartmentFile(
                deptIds.map((id) => AclasDepartment(id: id, name: 'قسم $id')).toList(),
                temDeptPath,
              );
              temFilesToClean.add(temDeptPath);

              final temUnitPath = '${temTempDir.path}\\tem_unit_$temTs.txt';
              await AclasSDK.generateUnitFile([
                AclasUnit(id: 4, name: 'kg'),
                AclasUnit(id: 10, name: 'pcs'),
              ], temUnitPath);
              temFilesToClean.add(temUnitPath);

              final temGroupPath = '${temTempDir.path}\\tem_group_$temTs.txt';
              await AclasSDK.generateGroupFile([
                AclasGroup(id: 1, name: 'عام'),
              ], temGroupPath);
              temFilesToClean.add(temGroupPath);

              final temPluItems = items.map((item) => AclasPLUItem(
                id: item.pluNumber,
                itemCode: item.pluNumber.toString(),
                departmentId: item.department,
                name: item.name,
                price: item.unitPrice,
                unitId: (item.isByWeight) ? 4 : 10,
                barcodeType1: 7, barcodeType2: 7,
                tareWeight: item.tareWeight,
              )).toList();
              final temPluPath = '${temTempDir.path}\\tem_plu_$temTs.txt';
              await AclasSDK.generatePLUFile(temPluItems, temPluPath);
              temFilesToClean.add(temPluPath);

              // HotKey mappings use the scale's actual button count (if known).
              // Sequential KeyNo = physical button position, wraps to Mode pages.
              final temBtnCount = deviceInfo.hotKeyCount;
              logger?.info('عدد أزرار الاختصار: '
                  '${temBtnCount > 0 ? temBtnCount : "غير معروف (استخدام 112)"}');
              final temHkMappings = AclasHotKeyMapping.buildSequentialMappings(
                items.map((e) => e.pluNumber).toList(),
                buttonsPerPage: temBtnCount > 0 ? temBtnCount : null,
              );
              final temHkPath = '${temTempDir.path}\\tem_hotkey_$temTs.txt';
              await AclasSDK.generateHotKeyFile(temHkMappings, temHkPath);
              temFilesToClean.add(temHkPath);

              // Upload sequence: Dept → Unit → Group → PLU → HotKey
              onProgress?.call(0, items.length);

              final deptR = await AclasSDK.uploadDataFile(
                effectiveIp, temDeptPath, AclasDataType.department, 'Department',
                deviceInfo: deviceInfo);
              logger?.info(deptR.success ? 'الأقسام ✓' : 'الأقسام ✗');

              final unitR = await AclasSDK.uploadDataFile(
                effectiveIp, temUnitPath, AclasDataType.unit, 'Unit',
                deviceInfo: deviceInfo);
              logger?.info(unitR.success ? 'الوحدات ✓' : 'الوحدات ✗');

              final groupR = await AclasSDK.uploadDataFile(
                effectiveIp, temGroupPath, AclasDataType.group, 'Group',
                deviceInfo: deviceInfo);
              logger?.info(groupR.success ? 'المجموعات ✓' : 'المجموعات ✗');

              final pluR = await AclasSDK.uploadPLU(
                effectiveIp, temPluPath, deviceInfo: deviceInfo);
              logger?.info(pluR.success ? 'PLU ✓' : 'PLU ✗: ${pluR.message}');

              if (pluR.success) {
                final hkR = await AclasSDK.uploadHotKeys(
                  effectiveIp, temHkPath, deviceInfo: deviceInfo);
                logger?.info(hkR.success ? 'مفاتيح الاختصار ✓' : 'مفاتيح الاختصار ✗');

                success = items.length;
                aclasSucceeded = true;
                logger?.success('تم الترحيل بنجاح عبر AclasSDK (${items.length} صنف)');
              }

              onProgress?.call(items.length, items.length);
              for (final p in temFilesToClean) {
                try { await File(p).delete(); } catch (_) {}
              }
            } else {
              logger?.info('لم يتم كشف الميزان عبر AclasSDK — سيتم تجربة W36F01 TCP');
            }
            AclasSDK.finalizeSdk();
          }
        } catch (e) {
          logger?.info('AclasSDK غير متاح: $e');
          try { AclasSDK.finalizeSdk(); } catch (_) {}
        }

        // ── Strategy 3: W36F01 binary over TCP (fallback) ──
        if (!aclasSucceeded) {
          if (aclasAttempted) {
            logger?.section('محاولة 3: W36F01 TCP (بروتوكول CAS/TEM)');
            logger?.warning(
              '⚠️ تحذير: AclasSDK فشل. سيتم تجربة W36F01 كاحتياطي. '
              'هذا البروتوكول قد يُرجع ACK دون حفظ البيانات على بعض موديلات TEM. '
              'يُنصَح باستخدام Serial أو التحقق يدوياً بعد الترحيل عبر ميزان.',
            );
          }
          logger?.info('جاري الاتصال TCP بـ $effectiveIp:$effectivePort...');
          socket = await transport.connectTCP(effectiveIp, effectivePort);
          logger?.success('تم الاتصال TCP بنجاح');

          // Drain any welcome/banner data from the scale
          final banner = await transport.readResponse(
            socket, timeout: const Duration(seconds: 1),
          );
          if (banner.isNotEmpty) {
            logger?.receivedBytes('بيانات ترحيب من الميزان', banner);
          }

          // Send each PLU record using W36F01 binary format
          for (int i = 0; i < items.length; i++) {
            final item = items[i];
            logger?.pluItem(i + 1, items.length, item.pluNumber, item.name, item.unitPrice, item.isByWeight, item.barcode ?? '');
            try {
              final cmd = _buildTEMPLURecord(item);
              logger?.sentBytes('PLU ${item.pluNumber}', cmd);

              socket.add(cmd);
              await socket.flush();

              var response = await transport.readResponse(
                socket, timeout: const Duration(seconds: 3),
              );

              if (response.isEmpty) {
                logger?.info('PLU ${item.pluNumber}: لا رد — إعادة محاولة...');
                socket.add(cmd);
                await socket.flush();
                response = await transport.readResponse(
                  socket, timeout: const Duration(seconds: 3),
                );
              }

              if (response.isNotEmpty) {
                logger?.receivedBytes('رد PLU ${item.pluNumber}', response);
                final firstByte = response[0];

                if (firstByte == 0x06) {
                  success++;
                  logger?.success('PLU ${item.pluNumber}: ACK — تم القبول');
                } else if (firstByte == 0x15) {
                  failed++;
                  errors.add('PLU ${item.pluNumber}: رفض الميزان (NAK)');
                  logger?.error('PLU ${item.pluNumber}: NAK — رفض');
                } else if (_isEchoBackSuccess(cmd, response)) {
                  success++;
                  logger?.success('PLU ${item.pluNumber}: Echo-back — تم القبول ✓');
                } else {
                  final fullResp = String.fromCharCodes(response).replaceAll(RegExp(r'[^\x20-\x7E]'), '.');
                  failed++;
                  errors.add('PLU ${item.pluNumber}: رد غير متوقع 0x${firstByte.toRadixString(16)} ($fullResp)');
                  logger?.warning('PLU ${item.pluNumber}: رد: "$fullResp" (0x${firstByte.toRadixString(16)}) — فشل');
                }
              } else {
                failed++;
                errors.add('PLU ${item.pluNumber}: لا استجابة من الميزان');
                logger?.error('PLU ${item.pluNumber}: لا استجابة — فشل');
              }
            } catch (e) {
              failed++;
              errors.add('PLU ${item.pluNumber}: $e');
              logger?.error('PLU ${item.pluNumber}: خطأ — $e');
            }
            onProgress?.call(i + 1, items.length);
          }

          logger?.info('تم إغلاق اتصال TCP');
        }
      }
    } catch (e) {
      logger?.error('خطأ في الاتصال: $e');
      return PLUUploadResult(
        total: items.length, success: 0, failed: items.length,
        errors: ['خطأ في الاتصال: $e'],
      );
    } finally {
      try { await socket?.close(); } catch (_) {}
      try { serialPort?.close(); } catch (_) {}
    }

    return PLUUploadResult(
      total: items.length, success: success, failed: failed, errors: errors,
    );
  }

  /// Build a TEM PLU record — uses CAS-compatible binary format
  /// Many TEM scales (especially Chinese models) accept CAS protocol
  Uint8List _buildTEMPLURecord(ScalePLUItem item) {
    // Try CAS-compatible format first (most TEM scales accept this)
    return _buildCASPLURecord(item);
  }

  // ═══════════════════════════════════════════════════════════════
  // Dibal G310 Protocol
  // ═══════════════════════════════════════════════════════════════

  Future<PLUUploadResult> _uploadDibal(
    List<ScalePLUItem> items,
    LabelScaleConnection conn,
    String? ip, int? port, String? com, int? baud,
    int? dataBits, String? parity, String? stopBits,
  ) async {
    int success = 0;
    int failed = 0;
    final errors = <String>[];

    logger?.section('Dibal — بدء الاتصال');
    logger?.info('الهدف: ${conn == LabelScaleConnection.serial ? (com ?? "COM3") : "${ip ?? "192.168.1.100"}:${port ?? 3000}"} | الاتصال: $conn');

    Socket? socket;
    dynamic serialPort;
    try {
      if (conn == LabelScaleConnection.serial) {
        serialPort = SerialPort(com ?? 'COM3', openNow: false, BaudRate: baud ?? 9600);
        await transport.configureSerial(serialPort, baud ?? 9600, dataBits, parity, stopBits);
        serialPort.open();
        logger?.success('تم فتح المنفذ التسلسلي ${com ?? "COM3"}');

        final startCmd = Uint8List.fromList([0x02, ...utf8.encode('START'), 0x03]);
        serialPort.writeBytesFromUint8List(startCmd);
        logger?.sentBytes('START', startCmd);
        await Future.delayed(const Duration(milliseconds: 300));

        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          logger?.pluItem(i + 1, items.length, item.pluNumber, item.name, item.unitPrice, item.isByWeight, item.barcode ?? '');
          try {
            final cmd = _buildDibalPLURecord(item);
            logger?.sentBytes('PLU ${item.pluNumber}', cmd);
            serialPort.writeBytesFromUint8List(cmd);
            await Future.delayed(const Duration(milliseconds: 150));

            final resp = await serialPort.readBytes(64, timeout: const Duration(milliseconds: 1500));
            if (resp.isNotEmpty) {
              logger?.receivedBytes('رد PLU ${item.pluNumber}', Uint8List.fromList(resp));
              if (resp[0] == 0x06) {
                success++;
                logger?.success('PLU ${item.pluNumber}: ACK — تم القبول');
              } else if (resp[0] == 0x15) {
                failed++;
                errors.add('PLU ${item.pluNumber}: رفض الميزان (NAK)');
                logger?.error('PLU ${item.pluNumber}: NAK — رفض');
              } else {
                failed++;
                errors.add('PLU ${item.pluNumber}: رد غير معروف 0x${resp[0].toRadixString(16)}');
                logger?.warning('PLU ${item.pluNumber}: رد غير معروف — فشل');
              }
            } else {
              failed++;
              errors.add('PLU ${item.pluNumber}: لا استجابة من الميزان');
              logger?.error('PLU ${item.pluNumber}: لا استجابة — فشل');
            }
          } catch (e) {
            failed++;
            errors.add('PLU ${item.pluNumber}: $e');
            logger?.error('PLU ${item.pluNumber}: خطأ — $e');
          }
          onProgress?.call(i + 1, items.length);
        }

        final endCmd = Uint8List.fromList([0x02, ...utf8.encode('END'), 0x03]);
        serialPort.writeBytesFromUint8List(endCmd);
        logger?.sentBytes('END', endCmd);
        await Future.delayed(const Duration(milliseconds: 200));
        logger?.info('تم إغلاق المنفذ التسلسلي');
      } else {
        logger?.info('جاري الاتصال TCP...');
        socket = await transport.connectTCP(ip ?? '192.168.1.100', port ?? 3000);
        logger?.success('تم الاتصال TCP بنجاح');

        final startCmd = Uint8List.fromList(utf8.encode('\x02START\x03'));
        socket.add(startCmd);
        await socket.flush();
        logger?.sentBytes('START', startCmd);
        await Future.delayed(const Duration(milliseconds: 300));

        final r = await _uploadPLUOverTCP(
          socket: socket, items: items,
          buildRecord: _buildDibalPLURecord,
          interpret: _interpretACKNAK,
          delimiter: 0x03,
        );
        success = r.success; failed = r.failed; errors.addAll(r.errors);

        socket.add(utf8.encode('\x02END\x03'));
        await socket.flush();
        logger?.sentBytes('END', Uint8List.fromList(utf8.encode('\x02END\x03')));
        logger?.info('تم إغلاق اتصال TCP');
      }
    } catch (e) {
      logger?.error('خطأ في الاتصال: $e');
      return PLUUploadResult(
        total: items.length, success: 0, failed: items.length,
        errors: ['خطأ في الاتصال: $e'],
      );
    } finally {
      try { await socket?.close(); } catch (_) {}
      try { serialPort?.close(); } catch (_) {}
    }

    return PLUUploadResult(
      total: items.length, success: success, failed: failed, errors: errors,
    );
  }

  /// Build a Dibal G310 PLU record
  /// Format: <STX>W<plu_no(3)><type(1)><name(20)><price(8)><tare(4)><ETX>
  Uint8List _buildDibalPLURecord(ScalePLUItem item) {
    final plu = item.pluNumber.toString().padLeft(3, '0');
    final type = item.isByWeight ? '0' : '1';
    final nameEncoded = transport.encodeCP1256(transport.padRight(
      ScaleTransport.reverseArabicForScale(item.name), 20,
    ));
    final price = (item.unitPrice * 100).round().toString().padLeft(8, '0');
    final tare = (item.tareWeight * 1000).round().toString().padLeft(4, '0');

    final List<int> bytes = [];
    bytes.add(0x02); // STX
    bytes.addAll(utf8.encode('W$plu$type'));
    bytes.addAll(nameEncoded);
    bytes.addAll(utf8.encode('$price$tare'));
    bytes.add(0x03); // ETX

    return Uint8List.fromList(bytes);
  }

  // ═══════════════════════════════════════════════════════════════
  // NVK TMA Protocol (Ethernet/RS232, up to 10,000 PLU)
  // ═══════════════════════════════════════════════════════════════

  Future<PLUUploadResult> _uploadNVK(
    List<ScalePLUItem> items,
    LabelScaleConnection conn,
    String? ip, int? port, String? com, int? baud,
    int? dataBits, String? parity, String? stopBits,
  ) async {
    int success = 0;
    int failed = 0;
    final errors = <String>[];

    logger?.section('NVK TMA — بدء الاتصال');
    logger?.info('الهدف: ${conn == LabelScaleConnection.serial ? (com ?? "COM3") : "${ip ?? "192.168.1.100"}:${port ?? 8000}"} | الاتصال: $conn');

    Socket? socket;
    dynamic serialPort;
    try {
      if (conn == LabelScaleConnection.serial) {
        serialPort = SerialPort(com ?? 'COM3', openNow: false, BaudRate: baud ?? 9600);
        await transport.configureSerial(serialPort, baud ?? 9600, dataBits, parity, stopBits);
        serialPort.open();
        logger?.success('تم فتح المنفذ التسلسلي ${com ?? "COM3"}');

        final startCmd = Uint8List.fromList([0x02, ...utf8.encode('PLUSTART'), 0x03]);
        serialPort.writeBytesFromUint8List(startCmd);
        logger?.sentBytes('PLUSTART', startCmd);
        await Future.delayed(const Duration(milliseconds: 300));

        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          logger?.pluItem(i + 1, items.length, item.pluNumber, item.name, item.unitPrice, item.isByWeight, item.barcode ?? '');
          try {
            final cmd = _buildNVKPLURecord(item);
            logger?.sentBytes('PLU ${item.pluNumber}', cmd);
            serialPort.writeBytesFromUint8List(cmd);
            await Future.delayed(const Duration(milliseconds: 80));

            final resp = await serialPort.readBytes(64, timeout: const Duration(milliseconds: 1500));
            if (resp.isNotEmpty) {
              logger?.receivedBytes('رد PLU ${item.pluNumber}', Uint8List.fromList(resp));
              if (resp[0] == 0x06) {
                success++;
                logger?.success('PLU ${item.pluNumber}: ACK — تم القبول');
              } else if (resp[0] == 0x15) {
                failed++;
                errors.add('PLU ${item.pluNumber}: رفض الميزان (NAK)');
                logger?.error('PLU ${item.pluNumber}: NAK — رفض');
              } else {
                failed++;
                errors.add('PLU ${item.pluNumber}: رد غير معروف 0x${resp[0].toRadixString(16)}');
                logger?.warning('PLU ${item.pluNumber}: رد غير معروف — فشل');
              }
            } else {
              failed++;
              errors.add('PLU ${item.pluNumber}: لا استجابة من الميزان');
              logger?.error('PLU ${item.pluNumber}: لا استجابة — فشل');
            }
          } catch (e) {
            failed++;
            errors.add('PLU ${item.pluNumber}: $e');
            logger?.error('PLU ${item.pluNumber}: خطأ — $e');
          }
          onProgress?.call(i + 1, items.length);
        }

        final endCmd = Uint8List.fromList([0x02, ...utf8.encode('PLUEND'), 0x03]);
        serialPort.writeBytesFromUint8List(endCmd);
        logger?.sentBytes('PLUEND', endCmd);
        await Future.delayed(const Duration(milliseconds: 200));
        logger?.info('تم إغلاق المنفذ التسلسلي');
      } else {
        logger?.info('جاري الاتصال TCP...');
        socket = await transport.connectTCP(ip ?? '192.168.1.100', port ?? 8000);
        logger?.success('تم الاتصال TCP بنجاح');

        final startCmd = Uint8List.fromList(utf8.encode('\x02PLUSTART\x03'));
        socket.add(startCmd);
        await socket.flush();
        logger?.sentBytes('PLUSTART', startCmd);
        await Future.delayed(const Duration(milliseconds: 300));

        final r = await _uploadPLUOverTCP(
          socket: socket, items: items,
          buildRecord: _buildNVKPLURecord,
          interpret: _interpretACKNAK,
          delimiter: 0x03,
        );
        success = r.success; failed = r.failed; errors.addAll(r.errors);

        socket.add(utf8.encode('\x02PLUEND\x03'));
        await socket.flush();
        logger?.sentBytes('PLUEND', Uint8List.fromList(utf8.encode('\x02PLUEND\x03')));
        logger?.info('تم إغلاق اتصال TCP');
      }
    } catch (e) {
      logger?.error('خطأ في الاتصال: $e');
      return PLUUploadResult(
        total: items.length, success: 0, failed: items.length,
        errors: ['خطأ في الاتصال: $e'],
      );
    } finally {
      try { await socket?.close(); } catch (_) {}
      try { serialPort?.close(); } catch (_) {}
    }

    return PLUUploadResult(
      total: items.length, success: success, failed: failed, errors: errors,
    );
  }

  /// Build an NVK TMA PLU record
  /// Format: <STX>PLU:<plu_no>,<dept>,<type>,<name>,<unit_price>,<tare>,<barcode><ETX>
  Uint8List _buildNVKPLURecord(ScalePLUItem item) {
    final type = item.isByWeight ? 'W' : 'C';
    final price = (item.unitPrice * 100).round();
    final tare = (item.tareWeight * 1000).round();
    final nameEncoded = transport.encodeCP1256(transport.padRight(
      ScaleTransport.reverseArabicForScale(item.name), 24,
    ));

    String cleanBc = item.barcode?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    if (cleanBc.isEmpty) {
      cleanBc = '20${item.pluNumber.toString().padLeft(5, '0')}';
    }
    final bc = cleanBc.padRight(13);

    final List<int> fullBytes = [];
    fullBytes.addAll(
      utf8.encode('\x02PLU:${item.pluNumber},${item.department},$type,'),
    );
    fullBytes.addAll(nameEncoded);
    fullBytes.addAll(utf8.encode(',$price,$tare,$bc\x03'));

    return Uint8List.fromList(fullBytes);
  }

  // ═══════════════════════════════════════════════════════════════
  // @visibleForTesting — expose record builders for unit tests
  // ═══════════════════════════════════════════════════════════════

  @visibleForTesting
  Uint8List buildCASRecord(ScalePLUItem item) => _buildCASPLURecord(item);
  @visibleForTesting
  Uint8List buildDIGIRecord(ScalePLUItem item) => _buildDIGIPLURecord(item);
  @visibleForTesting
  Uint8List buildAclasRecord(ScalePLUItem item) => _buildAclasPLURecord(item);
  @visibleForTesting
  Uint8List buildMettlerToledoRecord(ScalePLUItem item) => _buildMettlerToledoPLURecord(item);
  @visibleForTesting
  Uint8List buildDibalRecord(ScalePLUItem item) => _buildDibalPLURecord(item);
  @visibleForTesting
  Uint8List buildNVKRecord(ScalePLUItem item) => _buildNVKPLURecord(item);

  @visibleForTesting
  String interpretACKNAK(Uint8List response, ScalePLUItem item) => _interpretACKNAK(response, item);
  @visibleForTesting
  String interpretTextOKER(Uint8List response, ScalePLUItem item) => _interpretTextOKER(response, item);
}