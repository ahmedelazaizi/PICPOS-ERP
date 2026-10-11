// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

// Aclas LS2X/LS6X protocol

extension _AclasProtocol on ScaleProtocolHandler {
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
}
