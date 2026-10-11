// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

// TEM protocol (serial-only, ASCII)

extension _TemProtocol on ScaleProtocolHandler {
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
}
