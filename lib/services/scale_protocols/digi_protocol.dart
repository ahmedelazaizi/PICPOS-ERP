// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

// DIGI SM-100/SM-120 protocol

extension _DigiProtocol on ScaleProtocolHandler {
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
}
