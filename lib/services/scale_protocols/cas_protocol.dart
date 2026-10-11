// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

// CAS CL5000 / CL5200 protocol

extension _CasProtocol on ScaleProtocolHandler {
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
}
