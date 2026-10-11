// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

// Universal CSV-over-TCP upload

extension _CsvUpload on ScaleProtocolHandler {
  // ═══════════════════════════════════════════════════════════════
  // Universal CSV-over-TCP Upload (PLU Manager approach)
  // ═══════════════════════════════════════════════════════════════

  /// Upload PLU items by sending CSV data over TCP.
  /// This is the universal approach used by PLU Manager software —
  /// it works with most modern label scales (CAS, TEM, Rongta, DIGI,
  /// Aclas, etc.) that can parse CSV data received on their TCP port.
  // ignore: unused_element
  Future<PLUUploadResult> _uploadViaCSV(
    List<ScalePLUItem> items,
    String ip,
    int port,
    String weightPrefix,
    int pluCodeLen,
  ) async {
    Socket? socket;
    try {
      // Generate CSV in the same format as our file export (CAS PLU Manager compatible)
      final csvContent = LabelScaleService.instance.generatePLUCsv(
        items,
        weightPrefix: weightPrefix,
        pluCodeLen: pluCodeLen,
      );

      debugPrint('[Scale-CSV] Generated CSV: ${csvContent.length} chars, ${items.length} items');

      // Encode to CP1256 for Arabic support (scales don't understand UTF-8)
      final List<int> bytes = [];
      for (final char in csvContent.runes) {
        if (char < 128) {
          bytes.add(char);
        } else {
          bytes.addAll(transport.encodeCP1256(String.fromCharCode(char)));
        }
      }

      debugPrint('[Scale-CSV] Encoded to ${bytes.length} bytes (CP1256), connecting to $ip:$port...');

      // Connect and send the entire CSV payload
      socket = await transport.connectTCP(ip, port);
      socket.add(Uint8List.fromList(bytes));
      await socket.flush();

      // Wait for the scale to acknowledge the data
      final response = await transport.readResponse(
        socket, timeout: const Duration(seconds: 3),
      );
      if (response.isNotEmpty) {
        debugPrint('[Scale-CSV] Response: ${response.length} bytes');
      } else {
        debugPrint('[Scale-CSV] No response from scale after CSV send');
      }

      if (response.isEmpty) {
        debugPrint('[Scale-CSV] CSV sent but no confirmation from scale — reporting as failed');
        return PLUUploadResult(
          total: items.length,
          success: 0,
          failed: items.length,
          errors: ['تم إرسال البيانات لكن الميزان لم يؤكد الاستلام'],
        );
      }

      debugPrint('[Scale-CSV] CSV upload complete with response: ${items.length} items sent to $ip:$port');
      onProgress?.call(items.length, items.length);

      return PLUUploadResult(
        total: items.length,
        success: items.length,
        failed: 0,
      );
    } catch (e) {
      debugPrint('[Scale-CSV] CSV upload failed: $e');
      return PLUUploadResult(
        total: items.length,
        success: 0,
        failed: items.length,
        errors: ['CSV upload failed: $e'],
      );
    } finally {
      try { await socket?.close(); } catch (_) {}
    }
  }
}
