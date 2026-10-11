// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

// Dibal G310 protocol

extension _DibalProtocol on ScaleProtocolHandler {
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
}
