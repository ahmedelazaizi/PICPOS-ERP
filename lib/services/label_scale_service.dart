// ═══════════════════════════════════════════════════════════════════════════
// LABEL SCALE SERVICE — Public API, Models, Settings, FTP, CSV
// ═══════════════════════════════════════════════════════════════════════════
//
// Core service for PLU upload to label printing scales.
// Protocol implementations are in scale_protocols.dart.
// Transport layer (TCP/Serial/CP1256) is in scale_transport.dart.
//
// Split for maintainability (PIR C-01):
//   - scale_transport.dart: TCP, Serial, CP1256 encoding
//   - scale_protocols.dart: 8 brand-specific upload implementations

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:serial_port_win32/serial_port_win32.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/database/database.dart';
import 'scale_transport.dart';
import 'scale_protocols.dart';
import 'scale_upload_logger.dart';
import 'aclas_sdk_ffi.dart';

// ═══════════════════════════════════════════════════════════════
// AclasSDK Isolate Helpers (top-level — required by Isolate.run)
// ═══════════════════════════════════════════════════════════════

/// Runs AclasSDK device detection in a background isolate.
/// Returns a plain Map so no FFI objects cross isolate boundaries.
/// Tries auto-detect (port=0) first, then well-known Aclas UDP ports.
Map<String, dynamic> _aclasDetectInIsolate(String ip) {
  if (!AclasSDK.load()) {
    return {'found': false, 'error': 'فشل تحميل AclasSDK.dll — تأكد من وجود الملف'};
  }
  if (!AclasSDK.initialize()) {
    return {'found': false, 'error': 'فشل تهيئة AclasSDK'};
  }
  try {
    // Try auto-detect first, then known Aclas UDP ports
    AclasDeviceInfo? info = AclasSDK.getDeviceInfo(ip);
    int? triedPort;
    if (info == null) {
      for (final p in [9001, 9002, 10000, 3000, 8008]) {
        info = AclasSDK.getDeviceInfo(ip, port: p);
        if (info != null) { triedPort = p; break; }
      }
    }
    if (info != null) {
      return {
        'found': true,
        'protocolType': info.protocolType,
        'port': info.port,
        'pluStorage': info.pluStorage,
        'triedPort': triedPort,
      };
    }
    return {'found': false, 'error': 'لم يتم العثور على الميزان — تأكد من الـ IP، وأن الميزان مُشغّل'};
  } finally {
    AclasSDK.finalizeSdk();
  }
}

// ═══════════════════════════════════════════════════════════════
// Enums & Models
// ═══════════════════════════════════════════════════════════════

/// Supported label printing scale brands
enum LabelScaleBrand {
  cas, // CAS CL5000, CL5200, CL7200
  digi, // DIGI SM-100, SM-120, SM-5300
  rongta, // Rongta RLS1100, RLS1000
  aclas, // Aclas LS2X, LS6X
  mettlerToledo, // Mettler Toledo bPlus, bRite
  tem, // TEM (serial only, ASCII command/response)
  dibal, // Dibal G310 (serial only, up to 100 PLU)
  nvkTma, // NVK TMA (Ethernet/RS232/FTP, up to 10,000 PLU)
}

/// Connection/transfer method for label scales
enum LabelScaleConnection {
  tcp, // TCP/IP direct commands via Ethernet
  serial, // RS232 Serial COM port direct commands
  ftp, // FTP file upload (Rongta RLS, Mettler Toledo, etc.)
  file, // Export PLU as CSV file (universal fallback)
  aclasSDK, // AclasSDK auto-detect (IP only, no port needed)
}

// ═══════════════════════════════════════════════════════════════════════════
// هل الصنف ده بيتباع بالوزن على الميزان؟
// ═══════════════════════════════════════════════════════════════════════════
//
// `scaleType` في جدول الأصناف له أربع قيم، واللي بتحدد الإجابة اتنين منهم:
//
//   'count'          عدد          — مش صنف ميزان أصلاً
//   'weight'         ميزان        — بالوزن (كيلو)          → true
//   'weightByPiece'  ميزان بالحبة — بالحبة (عدد)           → **false**
//   'display'        عرض
//
// و`isSoldByWeight` **مش كافية لوحدها**: شاشة تعديل الصنف بتضبطها بـ
// `scaleType == 'weight' || scaleType == 'weightByPiece'`، يعني بتبقى `true`
// للاتنين. فأي كود بيقرا `isSoldByWeight` من غير ما يستثني `weightByPiece`
// بيعتبر أصناف الحبة أصناف وزن.
//
// ── الباج اللي الدالة دي موجودة عشانه ────────────────────────────────────
// الحساب ده كان مكرر في أربع أماكن بتلات صيغ مختلفة، وتلاتة منهم غلط:
//
//   scale_logic.dart / scale_panels.dart   (شاشة ترحيل الأصناف للميزان)
//     scaleType == 'weight' || scaleType == 'weightByPiece' || isSoldByWeight
//     → 'weightByPiece' بيدي true. غلط.
//
//   plu_csv_mixin.dart / plu_scale_upload_mixin.dart
//     isSoldByWeight
//     → بتتجاهل scaleType خالص، و'weightByPiece' بيبقى isSoldByWeight=true.
//
//   categories_screen.dart / product_search_header.dart
//     scaleType != 'weightByPiece'   ← الصح
//
// والنتيجة عند العميل: **كل أصناف الميزان بتترحّل للميزان كأنها بالوزن،
// فالميزان بيطبع «كيلو» على أصناف الحبة.** وأخطر من الطباعة إن الباركود
// المولَّد بياخد **بادئة الوزن** (٢١) بدل بادئة السعر (٢٠) — فباركود صنف
// بالحبة بيتقرا على نقطة البيع كباركود وزن، والسعر بيتحسب غلط.
//
// عشان كده الحساب بقى هنا وبس — تكراره تاني معناه إن الصيغ تفترق من جديد.
bool scaleItemIsSoldByWeight({
  required String? scaleType,
  required bool isSoldByWeight,
}) {
  // «ميزان بالحبة» بيحسم الموضوع مهما كانت `isSoldByWeight`.
  if (scaleType == 'weightByPiece') return false;
  if (scaleType == 'weight') return true;
  // الأصناف القديمة اللي اتعملت قبل ما `scaleType` يتضاف بيبقى عندها
  // `isSoldByWeight` بس، فهي الاحتياطي.
  return isSoldByWeight;
}

/// PLU item to upload to scale
class ScalePLUItem {
  final int pluNumber; // PLU code (1-99999)
  final String name; // Product name (Arabic OK)
  final double unitPrice; // Price per kg / unit (selling price to consumer)
  final double tareWeight; // Tare weight in kg (default 0)
  final int department; // Department number (default 1)
  final bool isByWeight; // true = by weight, false = by count
  final String? barcode; // Optional EAN barcode
  final String? productCode; // Product item code from system (e.g. "10001")

  const ScalePLUItem({
    required this.pluNumber,
    required this.name,
    required this.unitPrice,
    this.tareWeight = 0,
    this.department = 1,
    this.isByWeight = true,
    this.barcode,
    this.productCode,
  });
}

/// Upload result
class PLUUploadResult {
  final int total;
  final int success;
  final int failed;
  final List<String> errors;

  PLUUploadResult({
    required this.total,
    required this.success,
    required this.failed,
    this.errors = const [],
  });

  bool get isFullSuccess => failed == 0;
}

// ═══════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════

/// Label printing scale service – handles PLU upload to various scale brands
class LabelScaleService {
  LabelScaleService._() {
    _transport = ScaleTransport();
    _protocols = ScaleProtocolHandler(_transport);
  }
  static final instance = LabelScaleService._();

  late final ScaleTransport _transport;
  late final ScaleProtocolHandler _protocols;

  // SharedPreferences keys
  static const _prefBrand = 'label_scale_brand';
  static const _prefConnection = 'label_scale_connection';
  static const _prefAddress = 'label_scale_address';
  static const _prefPort = 'label_scale_port';
  static const _prefComPort = 'label_scale_com_port';
  static const _prefBaudRate = 'label_scale_baud_rate';

  // Default ports per brand
  static const Map<LabelScaleBrand, int> defaultPorts = {
    LabelScaleBrand.cas: 20304,
    LabelScaleBrand.digi: 3001,
    LabelScaleBrand.rongta: 9100,
    LabelScaleBrand.aclas: 8000,
    LabelScaleBrand.mettlerToledo: 252,
    LabelScaleBrand.tem: 9100,
    LabelScaleBrand.dibal: 3000,
    LabelScaleBrand.nvkTma: 8000,
  };

  // Brand display names (Arabic)
  static const Map<LabelScaleBrand, String> brandNames = {
    LabelScaleBrand.cas: 'CAS (CL5000/CL5200)',
    LabelScaleBrand.digi: 'DIGI (SM-100/SM-120)',
    LabelScaleBrand.rongta: 'Rongta (RLS1100)',
    LabelScaleBrand.aclas: 'Aclas (LS2X/LS6X)',
    LabelScaleBrand.mettlerToledo: 'Mettler Toledo (bPlus)',
    LabelScaleBrand.tem: 'TEM',
    LabelScaleBrand.dibal: 'Dibal (G310)',
    LabelScaleBrand.nvkTma: 'NVK TMA',
  };

  // ═══════════════════════════════════════════════════════════════
  // Enum Converters
  // ═══════════════════════════════════════════════════════════════

  /// Convert brand string from DB to enum
  static LabelScaleBrand brandFromString(String brand) {
    switch (brand.toLowerCase()) {
      case 'cas': return LabelScaleBrand.cas;
      case 'digi': return LabelScaleBrand.digi;
      case 'rongta': return LabelScaleBrand.rongta;
      case 'aclas': return LabelScaleBrand.aclas;
      case 'mettlertoledo': return LabelScaleBrand.mettlerToledo;
      case 'tem': return LabelScaleBrand.tem;
      case 'dibal': return LabelScaleBrand.dibal;
      case 'nvktma': return LabelScaleBrand.nvkTma;
      default: return LabelScaleBrand.cas;
    }
  }

  /// Convert enum to DB string
  static String brandToString(LabelScaleBrand brand) {
    switch (brand) {
      case LabelScaleBrand.cas: return 'cas';
      case LabelScaleBrand.digi: return 'digi';
      case LabelScaleBrand.rongta: return 'rongta';
      case LabelScaleBrand.aclas: return 'aclas';
      case LabelScaleBrand.mettlerToledo: return 'mettlertoledo';
      case LabelScaleBrand.tem: return 'tem';
      case LabelScaleBrand.dibal: return 'dibal';
      case LabelScaleBrand.nvkTma: return 'nvktma';
    }
  }

  /// Connection type from DB string
  static LabelScaleConnection connectionFromString(String conn) {
    switch (conn.toLowerCase()) {
      case 'serial': return LabelScaleConnection.serial;
      case 'ftp': return LabelScaleConnection.ftp;
      case 'file': return LabelScaleConnection.file;
      case 'aclassdk': return LabelScaleConnection.aclasSDK;
      default: return LabelScaleConnection.tcp;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Public API — DB-backed LabelScale records
  // ═══════════════════════════════════════════════════════════════

  /// Upload PLU items using a DB-backed LabelScale record
  Future<PLUUploadResult> uploadToScaleRecord({
    required LabelScale scale,
    required List<ScalePLUItem> items,
  }) async {
    final brand = brandFromString(scale.brand);
    final conn = connectionFromString(scale.connectionType);

    // P5 (Issue #1): Filter out items whose PLU exceeds the scale's maxPlu
    // BEFORE shipping to the device.
    //
    // Symptom this catches: a product with code "20001" gets uploaded to a
    // scale with maxPlu=9999 (typical for older Aclas/Rongta firmware). The
    // scale silently drops the row OR truncates the PLU, so the cashier
    // selects the product on the scale touchscreen and gets "PLU not found"
    // — but the upload result claims success because the transport accepted
    // the bytes.
    //
    // The defensive filter:
    //   1. Removes invalid items from the list before upload (avoids the
    //      silent drop on the device).
    //   2. Reports them in the PLUUploadResult.errors so the operator sees
    //      EXACTLY which products were rejected and why.
    //
    // We DO NOT change the parsing on the POS side — the scale handler is
    // already configurable via settings (scale_weight_prefix, etc.) and
    // works correctly when the device actually contains the PLU. This fix
    // only ensures we don't ASK the device to store a PLU it can't.
    final maxPlu = scale.maxPlu;
    final filteredItems = <ScalePLUItem>[];
    final rejectedErrors = <String>[];
    if (maxPlu > 0) {
      for (final item in items) {
        if (item.pluNumber > maxPlu || item.pluNumber < 1) {
          rejectedErrors.add(
            'تم تخطّى صنف "${item.name}" برقم PLU=${item.pluNumber} '
            '(يتجاوز حد الميزان "${scale.name}" maxPlu=$maxPlu). '
            'الحل: عيّن رقم PLU ضمن النطاق 1..$maxPlu فى إعدادات الصنف.',
          );
        } else {
          filteredItems.add(item);
        }
      }
    } else {
      filteredItems.addAll(items);
    }
    if (rejectedErrors.isNotEmpty) {
      debugPrint('[LabelScaleService] ⚠ Filtered ${rejectedErrors.length} '
          'items exceeding maxPlu=$maxPlu for scale "${scale.name}"');
      for (final e in rejectedErrors) {
        debugPrint('[LabelScaleService]   - $e');
      }
    }
    if (filteredItems.isEmpty) {
      return PLUUploadResult(
        total: items.length,
        success: 0,
        failed: items.length,
        errors: rejectedErrors.isNotEmpty
            ? rejectedErrors
            : ['لا توجد أصناف صالحة للرفع — تحقق من نطاق PLU المسموح.'],
      );
    }

    // Route FTP uploads to dedicated handler
    if (conn == LabelScaleConnection.ftp) {
      final res = await uploadViaFTP(scale: scale, items: filteredItems);
      if (rejectedErrors.isEmpty) return res;
      return PLUUploadResult(
        total: items.length,
        success: res.success,
        failed: res.failed + rejectedErrors.length,
        errors: [...rejectedErrors, ...res.errors],
      );
    }

    // AclasSDK — route to protocol handler (it handles SDK internally)
    if (conn == LabelScaleConnection.aclasSDK) {
      final res = await uploadPLUItems(
        brand: brand,
        connection: conn,
        items: filteredItems,
        ipAddress: scale.ipAddress,
        port: scale.port,
      );
      if (rejectedErrors.isEmpty) return res;
      return PLUUploadResult(
        total: items.length,
        success: res.success,
        failed: res.failed + rejectedErrors.length,
        errors: [...rejectedErrors, ...res.errors],
      );
    }

    // File export is handled at the UI layer
    if (conn == LabelScaleConnection.file) {
      return PLUUploadResult(
        total: items.length,
        success: 0,
        failed: items.length,
        errors: ['File export should use generatePLUCsv() instead'],
      );
    }

    // Load barcode settings for CSV-over-TCP universal upload
    final prefs = await SharedPreferences.getInstance();
    final weightPrefix = prefs.getString('scale_weight_prefix') ?? '21';
    final pluCodeLen = int.tryParse(
      prefs.getString('scale_weight_item_code_len') ?? '5',
    ) ?? 5;

    final res = await uploadPLUItems(
      brand: brand,
      connection: conn,
      items: filteredItems,
      ipAddress: scale.ipAddress,
      port: scale.port,
      comPort: scale.comPort,
      baudRate: scale.baudRate,
      dataBits: scale.dataBits,
      parity: scale.parity,
      stopBits: scale.stopBits,
      weightPrefix: weightPrefix,
      pluCodeLen: pluCodeLen,
    );
    if (rejectedErrors.isEmpty) return res;
    return PLUUploadResult(
      total: items.length,
      success: res.success,
      failed: res.failed + rejectedErrors.length,
      errors: [...rejectedErrors, ...res.errors],
    );
  }

  /// Clear PLU using a DB-backed LabelScale record
  Future<bool> clearScaleRecord(LabelScale scale) async {
    final brand = brandFromString(scale.brand);
    final conn = connectionFromString(scale.connectionType);
    return clearAllPLU(
      brand: brand, connection: conn,
      ipAddress: scale.ipAddress, port: scale.port,
      comPort: scale.comPort, baudRate: scale.baudRate,
      dataBits: scale.dataBits, parity: scale.parity,
      stopBits: scale.stopBits,
    );
  }

  /// Test connection using a DB-backed LabelScale record
  Future<Map<String, dynamic>> testScaleRecord(LabelScale scale) async {
    final brand = brandFromString(scale.brand);
    final conn = connectionFromString(scale.connectionType);
    return testConnection(
      brand: brand, connection: conn,
      ipAddress: scale.ipAddress, port: scale.port,
      comPort: scale.comPort, baudRate: scale.baudRate,
      dataBits: scale.dataBits, parity: scale.parity,
      stopBits: scale.stopBits,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Core Upload — delegates to ScaleProtocolHandler
  // ═══════════════════════════════════════════════════════════════

  /// Upload PLU items to scale
  Future<PLUUploadResult> uploadPLUItems({
    required LabelScaleBrand brand,
    required LabelScaleConnection connection,
    required List<ScalePLUItem> items,
    String? ipAddress,
    int? port,
    String? comPort,
    int? baudRate,
    int? dataBits,
    String? parity,
    String? stopBits,
    String weightPrefix = '21',
    int pluCodeLen = 5,
  }) async {
    if (items.isEmpty) {
      return PLUUploadResult(total: 0, success: 0, failed: 0);
    }

    debugPrint(
      '[LabelScale] Uploading ${items.length} PLU items to ${brand.name}...',
    );

    return _protocols.upload(
      brand: brand, connection: connection, items: items,
      ip: ipAddress, port: port, com: comPort, baud: baudRate,
      dataBits: dataBits, parity: parity, stopBits: stopBits,
      weightPrefix: weightPrefix, pluCodeLen: pluCodeLen,
    );
  }

  /// Clear all PLU items from scale
  Future<bool> clearAllPLU({
    required LabelScaleBrand brand,
    required LabelScaleConnection connection,
    String? ipAddress,
    int? port,
    String? comPort,
    int? baudRate,
    int? dataBits,
    String? parity,
    String? stopBits,
  }) async {
    try {
      final data = _protocols.buildClearCommand(brand);
      if (data == null) return false;
      await _transport.send(
        data, connection, ipAddress,
        port ?? defaultPorts[brand] ?? 20304,
        comPort, baudRate, dataBits, parity, stopBits,
      );
      debugPrint('[LabelScale] PLU memory cleared');
      return true;
    } catch (e) {
      debugPrint('[LabelScale] Clear PLU failed: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // FTP Upload
  // ═══════════════════════════════════════════════════════════════

  /// Upload PLU items to a scale via FTP.
  Future<PLUUploadResult> uploadViaFTP({
    required LabelScale scale,
    required List<ScalePLUItem> items,
  }) async {
    final log = ScaleUploadLogger(
      scaleName: scale.name,
      brand: scale.brand.toUpperCase(),
      connection: 'FTP',
      address: '${scale.ipAddress ?? "—"}:${scale.port}',
    );

    log.pluTable(items);
    log.section('FTP — بدء الاتصال');

    final prefs = await SharedPreferences.getInstance();
    final autoOpen = prefs.getBool('scale_log_auto_open') ?? true;

    final ip = scale.ipAddress ?? '192.168.1.90';
    final ftpPort = scale.port > 0 ? scale.port : 21;
    final user = scale.ftpUsername ?? 'anonymous';
    final pass = scale.ftpPassword ?? '';

    log.info('الاتصال بـ $ip:$ftpPort كمستخدم "$user"');

    final brand = brandFromString(scale.brand);
    final csvContent = generatePLUCsv(items, brand: brand);
    final isRongta = brand == LabelScaleBrand.rongta;

    final tempDir = Directory.systemTemp;
    // PLU Manager exports as .xls (actually UTF-16 TSV) — match the exact
    // filename pattern the scale's firmware recognizes.
    final fileName = isRongta
        ? 'plu_${DateTime.now().millisecondsSinceEpoch}.xls'
        : 'plu_upload_${DateTime.now().millisecondsSinceEpoch}.csv';
    final tempFile = File('${tempDir.path}/$fileName');

    try {
        List<int> fileBytes;
        String encodingLabel;
        if (isRongta) {
          // Rongta PLU Manager uses UTF-16 LE + BOM (verified from 2.xls export)
          fileBytes = <int>[0xFF, 0xFE];  // UTF-16 LE BOM
          for (final cu in csvContent.codeUnits) {
            fileBytes.add(cu & 0xFF);
            fileBytes.add((cu >> 8) & 0xFF);
          }
          encodingLabel = 'UTF-16 LE + BOM (PLU Manager format)';
        } else {
          // Other brands expect CP1256 (Arabic Windows codepage)
          final t = ScaleTransport();
          final List<int> cp1256Bytes = [];
          for (final ch in csvContent.runes) {
            if (ch < 128) {
              cp1256Bytes.add(ch);
            } else {
              cp1256Bytes.addAll(t.encodeCP1256(String.fromCharCode(ch)));
            }
          }
          fileBytes = cp1256Bytes;
          encodingLabel = 'CP1256';
        }
        await tempFile.writeAsBytes(fileBytes);
        log.info('ملف $fileName مؤقت: ${tempFile.path} '
            '(${fileBytes.length} بايت، ترميز $encodingLabel)');

        final ftp = FTPConnect(
          ip, port: ftpPort, user: user, pass: pass, timeout: 30,
        );
        log.info('جاري الاتصال بخادم FTP...');
        final connected = await ftp.connect();
        if (!connected) {
          log.error('فشل اتصال FTP');
          log.result(items.length, 0, items.length, ['فشل اتصال FTP بـ $ip:$ftpPort']);
          await log.saveAndOpen(autoOpen: autoOpen);
          return PLUUploadResult(
            total: items.length, success: 0, failed: items.length,
            errors: ['فشل اتصال FTP بـ $ip:$ftpPort'],
          );
        }
        log.success('تم اتصال FTP بنجاح');

        try {
          await ftp.changeDirectory('/');
        } catch (_) {}

        // Remote filename: PLU Manager uses .xls on Rongta scales, .csv elsewhere
        final remoteName = isRongta ? 'plu.xls' : 'plu_data.csv';
        log.info('جاري رفع الملف $remoteName...');
        final uploaded = await ftp.uploadFile(
          tempFile, sRemoteName: remoteName,
        );
        await ftp.disconnect();

        if (uploaded) {
          log.success('تم رفع الملف بنجاح: ${items.length} صنف');
          log.result(items.length, items.length, 0, []);
          await log.saveAndOpen(autoOpen: autoOpen);
          return PLUUploadResult(
            total: items.length, success: items.length, failed: 0,
          );
        } else {
          log.error('فشل رفع الملف — الميزان رفض الملف');
          log.result(items.length, 0, items.length, ['فشل رفع الملف عبر FTP']);
          await log.saveAndOpen(autoOpen: autoOpen);
          return PLUUploadResult(
            total: items.length, success: 0, failed: items.length,
            errors: ['فشل رفع الملف عبر FTP — الميزان رفض الملف'],
          );
        }
      } catch (e) {
        log.error('خطأ FTP: $e');
        log.result(items.length, 0, items.length, ['FTP: $e']);
        await log.saveAndOpen(autoOpen: autoOpen);
        return PLUUploadResult(
          total: items.length, success: 0, failed: items.length,
          errors: ['خطأ FTP: $e'],
        );
      } finally {
        // Always clean up temp file
        try { await tempFile.delete(); } catch (_) {}
      }
  }

  // ═══════════════════════════════════════════════════════════════
  // CSV Export
  // ═══════════════════════════════════════════════════════════════

  /// Generate a PLU CSV file matching the CAS PLU Manager export format exactly.
  /// Format verified against actual scale CSV export (666.csv).
  /// [weightPrefix] and [pluCodeLen] control the full barcode generation.
  String generatePLUCsv(
    List<ScalePLUItem> items, {
    LabelScaleBrand brand = LabelScaleBrand.cas,
    String weightPrefix = '21',
    int pluCodeLen = 5,
  }) {
    final buf = StringBuffer();

    // Verified from PLU Manager export template (2.xls) — exactly 24 columns,
    // TAB-separated with header row, UTF-16 LE + BOM + CRLF.
    //
    // Header row matches PLU Manager export EXACTLY (column names with spaces):
    if (brand == LabelScaleBrand.rongta) {
      buf.write(
        'Hotkey\tName\tLFCode\tCode\tBarcode Type\tUnit Price\t'
        'Unit Weight\tUnit Amount\tDepartment\tPT Weight\tShelf Time\t'
        'Pack Type\tTare\tError(%)\tMessage1\tMessage2\tLabel\t'
        'Discount/Table\tAccount\tsPluFieldTitle20\tAccount\t'
        'Recommend days\tnutrition\tIce(%)\r\n',
      );
    }

    //
    // NUM column is AUTO-GENERATED by PLU Manager — do NOT include it.
    //
    // Column layout:
    //  [0] Hotkey           — PLU number (quick-access key on the scale)
    //  [1] Name             — item name (CP1256 encoded for Arabic)
    //  [2] LFCode           — label format code (empty = default)
    //  [3] Code             — barcode (full 7-digit, e.g. "2100001")
    //  [4] Barcode Type     — ONE column: type number (2=weight, 1=count)
    //  [5] Unit Price       — decimal price (e.g. "1.50")
    //  [6] Unit Weight      — "Kg" for weight, "PCS" for count
    //  [7] Unit Amount      — 0
    //  [8] Department       — department number (e.g. 21)
    //  [9] PT Weight        — pretare weight (0.000)
    // [10] Shelf Time       — 0
    // [11] Pack Type        — "Normal"
    // [12] Tare             — tare weight (0.000)
    // [13] Error(%)         — 0
    // [14] Message1         — 0
    // [15] Message2         — 0
    // [16] Label            — 0
    // [17] Discount/Table   — 0
    // [18] Account          — 0
    // [19] sPluFieldTitle20 — empty
    // [20] Account          — 0
    // [21] Recommend days   — 0
    // [22] nutrition        — 0
    // [23] Ice(%)           — 0
    int rowNum = 0;
    for (final item in items) {
      rowNum++;
      final plu = item.pluNumber;

      // [0] Hotkey: PLU number
      final hotkey = plu > 0 ? plu : rowNum;

      // [1] Name: no escaping needed — TSV uses tab separator (no comma/quote issues)
      final name = item.name;

      // [2] LFCode: empty = use default label format (per column layout spec)
      const lfCode = '';

      // [3] Code: كود الصنف من النظام (e.g. "10010")
      final code = item.productCode ?? plu;

      // [4] Barcode Type: 2 = weight (EAN with embedded weight), 1 = count
      final barcodeType = item.isByWeight ? 2 : 1;

      // [5] Unit Price: decimal (1.50)
      final price = item.unitPrice.toStringAsFixed(2);

      // [6] Unit Weight: "Kg" or "PCS"
      final unitWeight = item.isByWeight ? 'Kg' : 'PCS';
      final tare = item.tareWeight.toStringAsFixed(3);
      final dept = item.department;

      // Exactly 24 TAB-separated columns matching PLU Manager template (2.xls)
      // PLU Manager uses TSV (tab-separated), NOT CSV (comma-separated)
      // CRLF line endings required — matches PLU Manager UTF-16 LE output
      const t = '\t';
      buf.write(
        '$hotkey$t$name$t$lfCode$t$code$t$barcodeType$t$price$t'
        '$unitWeight${t}0$t$dept$t$tare${t}0${t}Normal$t$tare${t}0$t'
        '0${t}0${t}0${t}0${t}0$t${t}0${t}0${t}0${t}0\r\n',
      );
    }

    return buf.toString();
  }

  /// Reverse Arabic text for CAS scale visual order.
  ///
  /// Delegates to [ScaleTransport.reverseArabicForScale].
  String _reverseArabicForScale(String input) =>
      ScaleTransport.reverseArabicForScale(input);

  // ═══════════════════════════════════════════════════════════════
  // Connection Testing
  // ═══════════════════════════════════════════════════════════════

  /// Test connection to the label scale
  Future<Map<String, dynamic>> testConnection({
    required LabelScaleBrand brand,
    required LabelScaleConnection connection,
    String? ipAddress,
    int? port,
    String? comPort,
    int? baudRate,
    int? dataBits,
    String? parity,
    String? stopBits,
  }) async {
    try {
      if (connection == LabelScaleConnection.aclasSDK) {
        // ── AclasSDK: auto-detect device by IP only ──
        // ALL SDK calls run inside a background isolate to prevent UI freeze.
        // Do NOT call AclasSDK.load/initialize here — the isolate handles it.
        final effectiveIp = ipAddress?.isNotEmpty == true ? ipAddress! : '192.168.1.100';
        debugPrint('[LabelScale] Testing AclasSDK connection to $effectiveIp (via isolate)');

        final raw = await Isolate.run(() => _aclasDetectInIsolate(effectiveIp));
        if (raw['found'] == true) {
          final pt = raw['protocolType'] as int;
          final protocolName = pt == 1 ? 'Pecr' : pt == 2 ? 'Hecr' : pt == 3 ? 'Tsecr' : 'غير معروف ($pt)';
          final triedPort = raw['triedPort'];
          final portNote = triedPort != null ? ' (كُشف على UDP:$triedPort)' : '';
          return {
            'success': true, 'error': null,
            'ip': effectiveIp,
            'port': raw['port'],
            'protocol': protocolName,
            'maxPlu': raw['pluStorage'],
            'message': 'تم اكتشاف الميزان$portNote — بروتوكول: $protocolName, منفذ: ${raw['port']}, سعة PLU: ${raw['pluStorage']}',
          };
        } else {
          return {'success': false, 'error': raw['error']?.toString()};
        }
      }

      if (connection == LabelScaleConnection.ftp) {
        // ── FTP: verify FTP banner (220) ──
        final effectiveIp = ipAddress?.isNotEmpty == true ? ipAddress! : '192.168.1.100';
        final effectivePort = port ?? 21;
        debugPrint('[LabelScale] Testing FTP connection to $effectiveIp:$effectivePort');

        final ftp = FTPConnect(
          effectiveIp, port: effectivePort,
          user: 'anonymous', pass: '', timeout: 10,
        );
        final connected = await ftp.connect();
        if (connected) {
          await ftp.disconnect();
          debugPrint('[LabelScale] FTP connection OK: $effectiveIp:$effectivePort');
          return {
            'success': true, 'error': null,
            'ip': effectiveIp, 'port': effectivePort,
          };
        } else {
          return {
            'success': false,
            'error': 'فشل الاتصال بخادم FTP على $effectiveIp:$effectivePort',
            'ip': effectiveIp, 'port': effectivePort,
          };
        }
      } else if (connection == LabelScaleConnection.tcp) {
        // ── TCP: connect and send probe command to verify it's really a scale ──
        final effectiveIp = ipAddress?.isNotEmpty == true
            ? ipAddress!
            : '192.168.1.100';
        final effectivePort = port ?? defaultPorts[brand] ?? 20304;
        debugPrint(
          '[LabelScale] Testing TCP connection to $effectiveIp:$effectivePort (brand: ${brand.name})',
        );

        final socket = await Socket.connect(
          effectiveIp, effectivePort,
          timeout: const Duration(seconds: 5),
        );

        try {
          // Send brand-specific probe command
          final probe = _buildProbeCommand(brand);
          socket.add(probe);
          await socket.flush();

          // Wait for any response (proves device is a scale, not just an open port)
          final response = await _transport.readResponse(
            socket, timeout: const Duration(seconds: 3),
          );

          debugPrint(
            '[LabelScale] TCP probe response: ${response.length} bytes from $effectiveIp:$effectivePort',
          );

          // Any non-empty response = the device is alive and responsive
          final probeOk = response.isNotEmpty;
          return {
            'success': true, 'error': null,
            'ip': effectiveIp, 'port': effectivePort,
            'probeResponse': probeOk,
          };
        } finally {
          try { await socket.close(); } catch (_) {}
        }
      } else {
        // ── Serial: open port and send probe to verify ──
        final effectiveCom = comPort?.isNotEmpty == true ? comPort! : 'COM3';
        final effectiveBaud = baudRate ?? 9600;
        debugPrint(
          '[LabelScale] Testing Serial connection to $effectiveCom @ $effectiveBaud',
        );
        final p = SerialPort(
          effectiveCom, openNow: false, BaudRate: effectiveBaud,
        );
        await _transport.configureSerial(p, effectiveBaud, dataBits, parity, stopBits);
        p.open();

        try {
          // Send probe command
          final probe = _buildProbeCommand(brand);
          p.writeBytesFromUint8List(probe);
          await Future.delayed(const Duration(milliseconds: 500));

          final resp = await p.readBytes(64, timeout: const Duration(milliseconds: 1500));
          debugPrint('[LabelScale] Serial probe response: ${resp.length} bytes from $effectiveCom');
          return {'success': true, 'error': null, 'probeResponse': resp.isNotEmpty};
        } finally {
          try { p.close(); } catch (_) {}
        }
      }
    } catch (e) {
      final errorMsg = e.toString();
      debugPrint('[LabelScale] Connection test failed: $errorMsg');
      if (connection == LabelScaleConnection.tcp || connection == LabelScaleConnection.ftp) {
        final effectiveIp = ipAddress?.isNotEmpty == true
            ? ipAddress!
            : '192.168.1.100';
        final effectivePort = port ?? defaultPorts[brand] ?? 20304;
        return {
          'success': false,
          'error': 'فشل الاتصال بـ $effectiveIp:$effectivePort — تأكد أن الجهاز متصل ومشغَّل.\n$errorMsg',
          'ip': effectiveIp, 'port': effectivePort,
        };
      }
      return {'success': false, 'error': 'فشل فتح المنفذ: $errorMsg'};
    }
  }

  /// Build a lightweight probe command to verify a device is a scale.
  /// Each brand has a different status/identity query command.
  Uint8List _buildProbeCommand(LabelScaleBrand brand) {
    switch (brand) {
      case LabelScaleBrand.cas:
      case LabelScaleBrand.tem:
        // CAS/TEM: send ENQ (0x05) — universal enquiry, most CAS scales reply with ACK
        return Uint8List.fromList([0x05]);
      case LabelScaleBrand.digi:
        // DIGI: STX + STATUS + ETX
        return Uint8List.fromList([0x02, ...utf8.encode('STATUS'), 0x03]);
      case LabelScaleBrand.rongta:
        // Rongta: ENQ
        return Uint8List.fromList([0x05]);
      case LabelScaleBrand.aclas:
        // Aclas: STX + STATUS + ETX
        return Uint8List.fromList([0x02, ...utf8.encode('STATUS'), 0x03]);
      case LabelScaleBrand.mettlerToledo:
        // Mettler Toledo: S (send stable weight) or SI (send immediately)
        return Uint8List.fromList(utf8.encode('SI\r\n'));
      case LabelScaleBrand.dibal:
        // Dibal: ENQ
        return Uint8List.fromList([0x05]);
      case LabelScaleBrand.nvkTma:
        // NVK: ENQ
        return Uint8List.fromList([0x05]);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Port Scanner
  // ═══════════════════════════════════════════════════════════════

  /// Common scale TCP ports to scan
  static const List<int> _commonScalePorts = [
    21, 23, 80, 252, 443, 2000, 3000, 3001, 4001, 5000,
    8000, 8080, 8217, 9100, 9200, 20304, 20305,
  ];

  /// Ports known to be used by each brand (data + FTP).
  static const Map<LabelScaleBrand, List<int>> _brandPorts = {
    LabelScaleBrand.cas: [20304, 20305, 9100, 21],
    LabelScaleBrand.digi: [3001, 9100, 21],
    LabelScaleBrand.rongta: [9100, 4001, 21],
    LabelScaleBrand.aclas: [8000, 9100, 21],
    LabelScaleBrand.mettlerToledo: [252, 9100, 21],
    LabelScaleBrand.tem: [9100, 20304, 20305, 8000, 3001, 4001, 21],
    LabelScaleBrand.dibal: [3000, 9100, 21],
    LabelScaleBrand.nvkTma: [8000, 9100, 21],
  };

  /// Scan an IP address for open scale ports.
  /// Two-phase scan: brand ports → common ports.
  /// Fast — finishes in seconds instead of minutes.
  Future<List<int>> scanForOpenPort(String ipAddress, {LabelScaleBrand? brand}) async {
    // Phase 1: brand-specific ports (fast — 3-5 ports only)
    if (brand != null) {
      final brandSpecific = _brandPorts[brand] ?? _commonScalePorts;
      debugPrint('[LabelScale] Phase 1: Scanning ${brandSpecific.length} brand ports for ${brand.name} on $ipAddress...');
      final found = await _scanPorts(ipAddress, brandSpecific);
      if (found.isNotEmpty) return found;
    }

    // Phase 2: all common scale ports (~17 ports)
    debugPrint('[LabelScale] Phase 2: Scanning all ${_commonScalePorts.length} common ports on $ipAddress...');
    final common = await _scanPorts(ipAddress, _commonScalePorts);
    if (common.isNotEmpty) return common;

    // No wide-range scan — standard ports cover all known brands.
    // If not found, the user should enter the port manually.
    debugPrint('[LabelScale] No open ports found on $ipAddress among known scale ports.');
    return [];
  }

  Future<List<int>> _scanPorts(String ipAddress, List<int> ports, {int timeoutSeconds = 1}) async {
    final openPorts = <int>[];
    final futures = ports.map((port) async {
      try {
        final socket = await Socket.connect(
          ipAddress, port,
          timeout: Duration(seconds: timeoutSeconds),
        );
        await socket.close();
        debugPrint('[LabelScale] Port $port is OPEN on $ipAddress');
        return port;
      } catch (_) {
        return -1;
      }
    });

    final results = await Future.wait(futures);
    for (final port in results) {
      if (port > 0) openPorts.add(port);
    }

    openPorts.sort();
    if (openPorts.isNotEmpty) {
      debugPrint('[LabelScale] Open ports on $ipAddress: $openPorts');
    }
    return openPorts;
  }

  // ═══════════════════════════════════════════════════════════════
  // Settings Persistence
  // ═══════════════════════════════════════════════════════════════

  /// Save settings
  Future<void> saveSettings({
    required LabelScaleBrand brand,
    required LabelScaleConnection connection,
    String? ipAddress,
    int? port,
    String? comPort,
    int? baudRate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBrand, brand.name);
    await prefs.setString(_prefConnection, connection.name);
    if (ipAddress != null) await prefs.setString(_prefAddress, ipAddress);
    if (port != null) await prefs.setInt(_prefPort, port);
    if (comPort != null) await prefs.setString(_prefComPort, comPort);
    if (baudRate != null) await prefs.setInt(_prefBaudRate, baudRate);
  }

  /// Load saved settings
  Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final brandStr = prefs.getString(_prefBrand);
    final connStr = prefs.getString(_prefConnection);
    return {
      'brand': brandStr != null
          ? LabelScaleBrand.values.firstWhere(
              (b) => b.name == brandStr,
              orElse: () => LabelScaleBrand.cas,
            )
          : LabelScaleBrand.cas,
      'connection': connStr != null
          ? LabelScaleConnection.values.firstWhere(
              (c) => c.name == connStr,
              orElse: () => LabelScaleConnection.tcp,
            )
          : LabelScaleConnection.tcp,
      'ipAddress': prefs.getString(_prefAddress) ?? '192.168.1.100',
      'port': prefs.getInt(_prefPort) ?? 20304,
      'comPort': prefs.getString(_prefComPort) ?? 'COM3',
      'baudRate': prefs.getInt(_prefBaudRate) ?? 9600,
    };
  }
}
