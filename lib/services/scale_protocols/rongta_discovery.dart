// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

// Rongta - FTP/HTTP/TCP probing and fallback upload attempts

extension _RongtaDiscovery on ScaleProtocolHandler {
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
      final boundary = '----${Brand.name}${DateTime.now().microsecondsSinceEpoch}';
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
}
