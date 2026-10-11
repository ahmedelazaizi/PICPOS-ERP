// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

// Rongta RLS1100 protocol - main upload flow

extension _RongtaUpload on ScaleProtocolHandler {
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
  // ignore: dead_code
      try { await socket?.close(); } catch (_) {}
      try { serialPort?.close(); } catch (_) {}
    }

    return PLUUploadResult(
      total: items.length, success: success, failed: failed, errors: errors,
    );
  }
}
