// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

// Rongta - frame wrapping and record/CSV encoding

extension _RongtaFormat on ScaleProtocolHandler {
  /// Wrap a 99-char PLU record in one of 4 Rongta TCP frame formats.
  Uint8List _wrapRongtaFrame(String record99, _RongtaFrame variant) {
    final dataBytes = <int>[];
    // Encode record as ASCII — it's all printable chars
    for (final c in record99.codeUnits) {
      dataBytes.add(c & 0xFF);
    }

    switch (variant) {
      case _RongtaFrame.stxCmdDataEtxLrc:
        // STX + "0110" + data + ETX + LRC (XOR of all bytes between STX/ETX exclusive)
        final body = <int>[...'0110'.codeUnits, ...dataBytes];
        int lrc = 0;
        for (final b in body) {
          lrc ^= b;
        }
        lrc ^= 0x03; // Include ETX in LRC per common scale conventions
        return Uint8List.fromList([0x02, ...body, 0x03, lrc]);

      case _RongtaFrame.stxCmdDataEtx:
        return Uint8List.fromList([
          0x02, ...'0110'.codeUnits, ...dataBytes, 0x03,
        ]);

      case _RongtaFrame.cmdDataCrLf:
        return Uint8List.fromList([
          ...'0110'.codeUnits, ...dataBytes, 0x0D, 0x0A,
        ]);

      case _RongtaFrame.dataCrLf:
        return Uint8List.fromList([...dataBytes, 0x0D, 0x0A]);
    }
  }

  /// Build a single PLU record in Rongta RLS official ASCII HEX format.
  /// Total: 99 ASCII chars per record (command 0110 data payload).
  ///
  /// Fields from RLS1000 Software Manual Section 2.5:
  ///   Operate(1) + Rank(2) + Name(36) + FreshCode(6) + ArtNo(10) +
  ///   BarcodeType(2) + UnitPrice(8) + WeighUnit(1) + Dept(2) +
  /// Check if a response is just an echo of the sent data (port 4001 behavior).
  /// Strip echo prefix from port 4001 responses.
  /// Port 4001 echoes sent data (sometimes with 1-byte offset) followed by
  /// zero-padding, then the scale's real response.
  /// Returns the non-echo portion (may be empty if truly just echo).
  // ignore: unused_element
  List<int> _stripEcho(Uint8List sent, Uint8List received) {
    if (received.isEmpty) return [];

    // Find where the echo ends — check direct match and 1-byte offset
    int echoEnd = 0;

    // Direct match: received starts with sent bytes
    if (received.length >= sent.length) {
      bool match = true;
      for (int i = 0; i < sent.length; i++) {
        if (sent[i] != received[i]) { match = false; break; }
      }
      if (match) echoEnd = sent.length;
    }

    // 1-byte offset match: received starts with sent[1:]
    if (echoEnd == 0 && received.length >= sent.length - 1 && sent.length > 1) {
      bool match = true;
      for (int i = 0; i < sent.length - 1; i++) {
        if (sent[i + 1] != received[i]) { match = false; break; }
      }
      if (match) echoEnd = sent.length - 1;
    }

    if (echoEnd == 0) return received.toList(); // No echo detected

    // Skip zero-padding after echo
    int dataStart = echoEnd;
    while (dataStart < received.length && received[dataStart] == 0x00) {
      dataStart++;
    }

    if (dataStart >= received.length) return []; // Only echo + zeros
    return received.sublist(dataStart).toList();
  }

  ///   TareWeight(6) + SavingPeriod(3) + PackType(1) + PackWeight(6) +
  ///   PackError(2) + Msg1(3) + Msg2(3) + MultiBarcode(3) +
  ///   Discount(3) + SalesMark(1) + DiscountMark(1) = 99
  String _buildRongtaPLURecord(ScalePLUItem item) {
    final buf = StringBuffer();

    // Operate: 'I' = insert/update, 'D' = delete
    buf.write('I');

    // Rank: PLU number (2 chars, zero-padded)
    buf.write(item.pluNumber.toString().padLeft(2, '0'));

    // Name: 36 chars, padded with spaces
    // Use CP1256 hex representation for Arabic names
    String name = item.name;
    if (name.length > 36) name = name.substring(0, 36);
    buf.write(name.padRight(36));

    // Fresh food code: 6 chars (PLU number padded)
    buf.write(item.pluNumber.toString().padLeft(6, '0'));

    // Art. No.: 10 chars (product code or barcode)
    final artNo = item.productCode ?? item.pluNumber.toString();
    buf.write(artNo.padLeft(10, '0'));

    // Barcode type: 2 chars
    // Refer to barcode format: "02" for weight, "01" for count
    buf.write(item.isByWeight ? '02' : '01');

    // Unit price: 8 chars, no decimal
    // e.g., 3.49 → 349, 1.50 → 150
    final priceInt = (item.unitPrice * 100).round();
    buf.write(priceInt.toString().padLeft(8, '0'));

    // Weighing unit: 1 char
    // 0=50g, 1=g, 2=10g, 3=100g, 4=kg, 5=oz, 6=lb,
    // 9=PCS(g), A=PCS(Kg)
    buf.write(item.isByWeight ? '4' : 'A');

    // Dept.: 2 chars
    buf.write(item.department.toString().padLeft(2, '0'));

    // Tare weight: 6 chars (within 15Kg, logic conversion)
    final tareInt = (item.tareWeight * 1000).round();
    buf.write(tareInt.toString().padLeft(6, '0'));

    // Saving period: 3 chars (0-365)
    buf.write('000');

    // Packing type: 1 char (0=normal)
    buf.write('0');

    // Packing weight: 6 chars
    buf.write('000000');

    // Packing error: 2 chars (0-20)
    buf.write('00');

    // Message 1: 3 chars (0-197)
    buf.write('000');

    // Message 2: 3 chars (0-197)
    buf.write('000');

    // Multi-barcode: 3 chars (0-255)
    buf.write('000');

    // Discount: 3 chars (0-99)
    buf.write('000');

    // Sales mark: 1 char
    buf.write('0');

    // Discount mark: 1 char
    buf.write('0');

    return buf.toString();
  }

  /// Build Rongta PLU Manager file in the EXACT official format.
  ///
  /// Verified against real `release_trial/2.xls` export (2026-04-13):
  ///   - **TAB-separated** (not CSV)
  ///   - **UTF-16 LE with BOM** + **CRLF** line endings
  ///   - **24 columns** (not 20)
  ///   - Column names with SPACES: "Unit Price", "Barcode Type", etc.
  ///   - No leading "NUM" column — "Hotkey" is the first column
  ///
  /// Header columns (order matters):
  ///   Hotkey | Name | LFCode | Code | Barcode Type | Unit Price |
  ///   Unit Weight | Unit Amount | Department | PT Weight | Shelf Time |
  ///   Pack Type | Tare | Error(%) | Message1 | Message2 | Label |
  ///   Discount/Table | Account | sPluFieldTitle20 | Account |
  ///   Recommend days | nutrition | Ice(%)
  String _buildRongtaCSV(List<ScalePLUItem> items) {
    final buf = StringBuffer();

    // Header — exact columns from PLU Manager export, TAB-separated, CRLF
    buf.write(
      'Hotkey\tName\tLFCode\tCode\tBarcode Type\tUnit Price\t'
      'Unit Weight\tUnit Amount\tDepartment\tPT Weight\tShelf Time\t'
      'Pack Type\tTare\tError(%)\tMessage1\tMessage2\tLabel\t'
      'Discount/Table\tAccount\tsPluFieldTitle20\tAccount\t'
      'Recommend days\tnutrition\tIce(%)\r\n',
    );

    for (final item in items) {
      final plu = item.pluNumber;
      final reversedName = ScaleTransport.reverseArabicForScale(item.name);
      // PLU Manager uses tab-separated fields — no CSV quoting, but must
      // sanitize embedded tabs in product name to prevent column break.
      final name = reversedName.replaceAll('\t', ' ').replaceAll('\r', '')
          .replaceAll('\n', ' ');
      final price = item.unitPrice.toStringAsFixed(AppConstants.decimalPlaces);
      final dept = item.department;
      final unit = item.isByWeight ? 'Kg' : 'PCS';
      final tare = item.tareWeight.toStringAsFixed(3);
      final barcodeType = item.isByWeight ? 2 : 1;
      final packType = item.isByWeight ? 15 : 0;
      final lfCode = plu;
      final code = (item.barcode != null && item.barcode!.isNotEmpty)
          ? item.barcode!
          : '${dept.toString().padLeft(2, '0')}${plu.toString().padLeft(5, '0')}';

      buf.write(
        '$plu\t'           // Hotkey (physical button position)
        '$name\t'          // Name
        '$lfCode\t'        // LFCode (label format code)
        '$code\t'          // Code (7-digit scale barcode)
        '$barcodeType\t'   // Barcode Type (2=weight, 1=price)
        '$price\t'         // Unit Price
        '$unit\t'          // Unit Weight ("Kg" or "PCS")
        '0\t'              // Unit Amount
        '$dept\t'          // Department
        '0.000\t'          // PT Weight (pre-tare)
        '\t'               // Shelf Time (empty)
        '$packType\t'      // Pack Type
        '$tare\t'          // Tare
        '0.000\t'          // Error(%)
        '0\t'              // Message1
        '0\t'              // Message2
        '0\t'              // Label
        '0\t'              // Discount/Table
        '0\t'              // Account
        '0\t'              // sPluFieldTitle20
        '0\t'              // Account (duplicated in PLU Manager!)
        '0\t'              // Recommend days
        '0\t'              // nutrition
        '0\r\n',           // Ice(%) + CRLF
      );
    }
    return buf.toString();
  }

  /// Encode Rongta CSV content as UTF-16 LE with BOM (matches PLU Manager output).
  /// Returns bytes ready to write to disk or send over TCP.
  Uint8List _encodeRongtaCsvUtf16(String csvContent) {
    final bytes = <int>[0xFF, 0xFE]; // UTF-16 LE BOM
    for (final cu in csvContent.codeUnits) {
      bytes.add(cu & 0xFF);
      bytes.add((cu >> 8) & 0xFF);
    }
    return Uint8List.fromList(bytes);
  }
}
