// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

// Mettler Toledo bPlus/bRite protocol

extension _MettlerToledoProtocol on ScaleProtocolHandler {
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
}
