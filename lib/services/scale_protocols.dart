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
import 'serial_port_compat.dart';
import '../core/constants/app_constants.dart';
import 'aclas_sdk_ffi.dart'
    if (dart.library.js_interop) 'aclas_sdk_web.dart';
import 'label_scale_service.dart';
import 'scale_transport.dart';
import 'scale_upload_logger.dart';
import '../core/logging/diagnostic_logger.dart';
import '../data/database/database.dart' show LabelScale;
import '../core/config/brand.dart';

part 'scale_protocols/aclas_isolate_and_cache.dart';
part 'scale_protocols/upload_types.dart';
part 'scale_protocols/brand_dispatch.dart';
part 'scale_protocols/aclas_sdk_upload.dart';
part 'scale_protocols/csv_upload.dart';
part 'scale_protocols/tcp_upload_helpers.dart';
part 'scale_protocols/cas_protocol.dart';
part 'scale_protocols/digi_protocol.dart';
part 'scale_protocols/rongta_upload.dart';
part 'scale_protocols/rongta_discovery.dart';
part 'scale_protocols/rongta_format.dart';
part 'scale_protocols/aclas_protocol.dart';
part 'scale_protocols/mettler_toledo_protocol.dart';
part 'scale_protocols/tem_protocol.dart';
part 'scale_protocols/dibal_protocol.dart';
part 'scale_protocols/nvk_protocol.dart';

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
