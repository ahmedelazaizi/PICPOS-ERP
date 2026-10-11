// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

// Shared TCP PLU upload loop and ACK/NAK interpreters

extension _TcpUploadHelpers on ScaleProtocolHandler {
  // ═══════════════════════════════════════════════════════════════
  // Shared TCP PLU upload loop — eliminates duplication across brands
  // ═══════════════════════════════════════════════════════════════

  /// Standard ACK/NAK interpreter for binary protocols.
  /// Also recognizes echo-back pattern (Fire Bird, Chinese scales).
  /// [sentCmd] is optional — if provided, enables echo-back detection.
  /// Returns empty string on success, error message on failure.
  String _interpretACKNAK(Uint8List response, ScalePLUItem item, {Uint8List? sentCmd}) {
    if (response.isNotEmpty) {
      logger?.receivedBytes('رد PLU ${item.pluNumber}', response);
      if (response[0] == 0x06) {
        logger?.success('PLU ${item.pluNumber}: ACK — تم القبول');
        return ''; // success
      } else if (response[0] == 0x15) {
        logger?.error('PLU ${item.pluNumber}: NAK — رفض');
        return 'PLU ${item.pluNumber}: رفض الميزان (NAK)';
      } else if (sentCmd != null && _isEchoBackSuccess(sentCmd, response)) {
        logger?.success('PLU ${item.pluNumber}: Echo-back — تم القبول ✓');
        return ''; // success — echo-back confirmation
      } else {
        logger?.warning('PLU ${item.pluNumber}: رد غير متوقع — فشل');
        return 'PLU ${item.pluNumber}: رد غير متوقع 0x${response[0].toRadixString(16)}';
      }
    }
    logger?.error('PLU ${item.pluNumber}: لا استجابة — فشل');
    return 'PLU ${item.pluNumber}: لا استجابة من الميزان';
  }

  /// Text OK/ER interpreter for Aclas-style protocols.
  String _interpretTextOKER(Uint8List response, ScalePLUItem item) {
    final respStr = response.isNotEmpty
        ? String.fromCharCodes(response).trim()
        : '';
    if (response.isNotEmpty) {
      logger?.receivedBytes('رد PLU ${item.pluNumber}', response);
    }
    if (respStr.startsWith('OK')) {
      logger?.success('PLU ${item.pluNumber}: OK — تم القبول');
      return '';
    } else if (respStr.startsWith('ER')) {
      logger?.error('PLU ${item.pluNumber}: ER — رفض');
      return 'PLU ${item.pluNumber}: رفض الميزان (ER)';
    } else if (response.isNotEmpty) {
      logger?.warning('PLU ${item.pluNumber}: رد غير معروف — فشل');
      return 'PLU ${item.pluNumber}: رد غير معروف: $respStr';
    }
    logger?.error('PLU ${item.pluNumber}: لا استجابة — فشل');
    return 'PLU ${item.pluNumber}: لا استجابة من الميزان';
  }

  /// Detect echo-back response pattern used by Fire Bird, Rongta, and many
  /// Chinese label scales. The scale echoes the sent command (minus the leading
  /// 'W' byte) and terminates with CR LF ETX (0x0D 0x0A 0x03).
  ///
  /// Example:
  ///   Sent:     W 36F01,000004L0063:21000004...checksum  (83 bytes)
  ///   Response: 36F01,000004L0063:21000004...checksum + padding + 0D 0A 03
  bool _isEchoBackSuccess(Uint8List sent, Uint8List response) {
    if (response.length < 10) return false;

    // Check 1: Response ends with ETX (0x03) — the standard end marker.
    // Look for 0x03 near the end (may be the last non-zero byte).
    bool hasETX = false;
    for (int i = response.length - 1; i >= response.length - 5 && i >= 0; i--) {
      if (response[i] == 0x03) { hasETX = true; break; }
    }
    if (!hasETX) return false;

    // Check 2: Response starts with same data as sent (skipping the 'W' prefix).
    // The sent command starts with 'W' (0x57), the echo starts at sent[1].
    if (sent.length < 5) return false;
    final matchLen = (response.length < sent.length - 1) ? response.length : sent.length - 1;
    // Compare first 10 bytes (enough to confirm it's the same record)
    final checkLen = matchLen < 10 ? matchLen : 10;
    int matching = 0;
    for (int i = 0; i < checkLen; i++) {
      if (response[i] == sent[i + 1]) matching++;
    }
    // At least 80% of checked bytes should match
    return matching >= (checkLen * 0.8).ceil();
  }

  /// Generic TCP PLU upload loop.
  ///
  /// Sends each item's record to [socket], reads the response,
  /// and interprets it via [interpret]. Returns aggregated counters.
  Future<({int success, int failed, List<String> errors})> _uploadPLUOverTCP({
    required Socket socket,
    required List<ScalePLUItem> items,
    required Uint8List Function(ScalePLUItem) buildRecord,
    required String Function(Uint8List response, ScalePLUItem item) interpret,
    int? delimiter,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    int success = 0;
    int failed = 0;
    final errors = <String>[];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      logger?.pluItem(i + 1, items.length, item.pluNumber, item.name,
          item.unitPrice, item.isByWeight, item.barcode ?? '');
      try {
        final cmd = buildRecord(item);
        logger?.sentBytes('PLU ${item.pluNumber}', cmd);
        socket.add(cmd);
        await socket.flush();

        final response = await transport.readResponse(
          socket, timeout: timeout, delimiter: delimiter,
        );

        final error = interpret(response, item);
        if (error.isEmpty) {
          success++;
        } else {
          failed++;
          errors.add(error);
        }
      } catch (e) {
        failed++;
        errors.add('PLU ${item.pluNumber}: $e');
        logger?.error('PLU ${item.pluNumber}: خطأ — $e');
      }
      onProgress?.call(i + 1, items.length);
    }

    return (success: success, failed: failed, errors: errors);
  }
}
