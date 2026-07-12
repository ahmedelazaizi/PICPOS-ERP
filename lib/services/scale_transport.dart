// ═══════════════════════════════════════════════════════════════════════════
// SCALE TRANSPORT — TCP, Serial, FTP communication + CP1256 encoding
// ═══════════════════════════════════════════════════════════════════════════
//
// Extracted from LabelScaleService for maintainability (PIR C-01).

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:serial_port_win32/serial_port_win32.dart';
import 'label_scale_service.dart';

/// Low-level transport for scale communication.
class ScaleTransport {
  // ═══════════════════════════════════════════════════════════════
  // TCP
  // ═══════════════════════════════════════════════════════════════

  /// Cache of broadcast streams per socket, so multiple readResponse()
  /// calls on the same socket don't fail with "Stream already listened to".
  final _broadcastCache = Expando<Stream<Uint8List>>('socketBroadcast');

  /// Get or create a broadcast stream for a socket.
  Stream<Uint8List> _getBroadcast(Socket socket) {
    var bs = _broadcastCache[socket];
    if (bs == null) {
      bs = socket.asBroadcastStream();
      _broadcastCache[socket] = bs;
    }
    return bs;
  }

  Future<Socket> connectTCP(String ip, int port) async {
    return Socket.connect(ip, port, timeout: const Duration(seconds: 5));
  }

  /// Read a response from a TCP socket, accumulating chunks until:
  /// - A [delimiter] byte is found (e.g. ETX 0x03, LF 0x0A), or
  /// - [maxBytes] are received, or
  /// - [timeout] expires with no new data.
  ///
  /// Returns the accumulated bytes (may be empty if nothing arrived).
  /// This replaces the unreliable `socket.first` pattern that only
  /// captures the first TCP segment.
  ///
  /// Safe to call multiple times on the same socket — internally uses
  /// a cached broadcast stream to avoid "Stream already listened to" errors.
  Future<Uint8List> readResponse(
    Socket socket, {
    int? delimiter,
    int maxBytes = 1024,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final buffer = <int>[];
    final completer = Completer<Uint8List>();
    Timer? timer;
    StreamSubscription<Uint8List>? sub;

    void finish() {
      timer?.cancel();
      sub?.cancel();
      if (!completer.isCompleted) {
        completer.complete(Uint8List.fromList(buffer));
      }
    }

    // Start a timeout that fires if no data arrives within [timeout]
    timer = Timer(timeout, finish);

    final stream = _getBroadcast(socket);
    sub = stream.listen(
      (chunk) {
        buffer.addAll(chunk);
        // Reset timeout on each chunk
        timer?.cancel();
        timer = Timer(timeout, finish);

        // Check for delimiter
        if (delimiter != null && chunk.contains(delimiter)) {
          finish();
          return;
        }
        // Check max bytes
        if (buffer.length >= maxBytes) {
          finish();
        }
      },
      onError: (_) => finish(),
      onDone: finish,
      cancelOnError: true,
    );

    return completer.future;
  }

  // ═══════════════════════════════════════════════════════════════
  // Unified Send (TCP or Serial)
  // ═══════════════════════════════════════════════════════════════

  Future<void> send(
    Uint8List data,
    LabelScaleConnection conn,
    String? ip,
    int port,
    String? com,
    int? baud, [
    int? dataBits,
    String? parity,
    String? stopBits,
  ]) async {
    debugPrint('[ScaleTransport] send() called: conn=$conn, ip=$ip, port=$port, com=$com, baud=$baud, dataLen=${data.length}');
    logPayload(conn.toString(), data);

    if (conn == LabelScaleConnection.tcp) {
      Socket? socket;
      try {
        socket = await connectTCP(ip ?? '192.168.1.100', port);
        socket.add(data);
        await socket.flush();

        // Try to listen for simple ACK/NAK or error codes for 2000ms
        var response = await readResponse(
          socket, timeout: const Duration(milliseconds: 2000),
        );

        // Retry once if no response on first attempt
        if (response.isEmpty) {
          debugPrint('[ScaleRawResponse] No response, retrying...');
          response = await readResponse(
            socket, timeout: const Duration(milliseconds: 2000),
          );
        }

        if (response.isNotEmpty) {
          debugPrint(
            '[ScaleRawResponse] Received ${response.length} bytes: ${response.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
          );
        }
      } catch (e) {
        debugPrint('[ScaleSendError] TCP Error: $e');
      } finally {
        await socket?.close();
      }
    } else {
      try {
        final serialPort = SerialPort(
          com ?? 'COM3',
          openNow: false,
          BaudRate: baud ?? 9600,
        );
        await configureSerial(
          serialPort,
          baud ?? 9600,
          dataBits,
          parity,
          stopBits,
        );
        serialPort.open();
        serialPort.writeBytesFromUint8List(data);

        // Wait and try to read any response (1500ms timeout)
        await Future.delayed(const Duration(milliseconds: 200));
        var resp = await serialPort.readBytes(
          64,
          timeout: const Duration(milliseconds: 1500),
        );

        // Retry once if no response on first attempt
        if (resp.isEmpty) {
          debugPrint('[ScaleRawResponse] Serial: No response, retrying...');
          await Future.delayed(const Duration(milliseconds: 200));
          resp = await serialPort.readBytes(
            64,
            timeout: const Duration(milliseconds: 1500),
          );
        }

        if (resp.isNotEmpty) {
          debugPrint(
            '[ScaleRawResponse] Serial Received: ${resp.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
          );
        }

        serialPort.close();
      } catch (e) {
        debugPrint('[ScaleSendError] Serial Error: $e');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Serial Configuration
  // ═══════════════════════════════════════════════════════════════

  /// Configure serial port with advanced settings
  Future<void> configureSerial(
    SerialPort p,
    int baud, [
    int? dataBits,
    String? parity,
    String? stopBits,
  ]) async {
    p.BaudRate = baud;

    if (dataBits != null) p.ByteSize = dataBits;

    if (parity != null) {
      switch (parity.toLowerCase()) {
        case 'even':
          p.Parity = 2;
          break;
        case 'odd':
          p.Parity = 1;
          break;
        case 'mark':
          p.Parity = 3;
          break;
        case 'space':
          p.Parity = 4;
          break;
        default:
          p.Parity = 0; // none
      }
    }

    if (stopBits != null) {
      switch (stopBits.toLowerCase()) {
        case 'two':
          p.StopBits = 2;
          break;
        case 'onepointfive':
          p.StopBits = 1;
          break;
        default:
          p.StopBits = 0; // one
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Logging
  // ═══════════════════════════════════════════════════════════════

  void logPayload(String source, Uint8List data) {
    debugPrint(
      '[ScalePayloadDiag] Source: $source, Total: ${data.length} bytes',
    );
    if (data.length <= 256) {
      final hex = data
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      debugPrint('[ScalePayloadDiag] Content: $hex');
    } else {
      final head = data
          .take(128)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      final tail = data
          .skip(data.length - 128)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      debugPrint('[ScalePayloadDiag] Head: $head');
      debugPrint('[ScalePayloadDiag] Tail: $tail');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // String Utilities
  // ═══════════════════════════════════════════════════════════════

  String padRight(String s, int width) {
    String result = s;
    if (result.length > width) {
      result = result.substring(0, width);
    }
    return result.padRight(width);
  }

  /// Encode a string to UTF-16 LE with BOM — matches PLU Manager's native format.
  /// PLU Manager (CAS) exports/imports .xls/.csv as UTF-16 LE tab-separated.
  Uint8List encodeUtf16LE(String input) {
    final bytes = <int>[0xFF, 0xFE]; // UTF-16 LE BOM
    for (final cu in input.codeUnits) {
      bytes.add(cu & 0xFF);        // low byte
      bytes.add((cu >> 8) & 0xFF); // high byte
    }
    return Uint8List.fromList(bytes);
  }

  /// Reverse Arabic runs for scale firmware display.
  ///
  /// CAS / Dibal / most label scales store text in "visual LTR" order.
  /// Arabic is RTL, so "موز" (logical: م-و-ز) must become "زوم"
  /// (visual: ز-و-م) so the scale LCD shows it correctly.
  ///
  /// Strategy: split into Arabic vs non-Arabic runs, reverse each Arabic
  /// run, keep digits/Latin in place.
  static String reverseArabicForScale(String input) {
    if (input.isEmpty) return input;

    bool isArabicChar(int cp) =>
        (cp >= 0x0600 && cp <= 0x06FF) ||
        (cp >= 0xFE70 && cp <= 0xFEFF) ||
        cp == 0x200C || cp == 0x200D || // zero-width joiners
        cp == 0x0020; // space (keep with Arabic run)

    final segments = <({bool isArabic, String text})>[];
    final buf = StringBuffer();
    bool? currentIsArabic;

    for (final rune in input.runes) {
      final arabic = isArabicChar(rune);
      if (currentIsArabic == null) {
        currentIsArabic = arabic;
        buf.writeCharCode(rune);
      } else if (arabic == currentIsArabic) {
        buf.writeCharCode(rune);
      } else {
        segments.add((isArabic: currentIsArabic, text: buf.toString()));
        buf.clear();
        buf.writeCharCode(rune);
        currentIsArabic = arabic;
      }
    }
    if (buf.isNotEmpty) {
      segments.add((isArabic: currentIsArabic!, text: buf.toString()));
    }

    return segments.map((s) {
      if (s.isArabic) {
        return String.fromCharCodes(s.text.runes.toList().reversed);
      }
      return s.text;
    }).join();
  }

  /// Encode a string to Windows-1256 (CP1256) for Arabic scale compatibility.
  /// Standard scales do not support UTF-8.
  Uint8List encodeCP1256(String input) {
    final List<int> bytes = [];
    for (int i = 0; i < input.length; i++) {
      int codeUnit = input.codeUnitAt(i);

      // Basic ASCII (0-127) matches
      if (codeUnit < 128) {
        bytes.add(codeUnit);
        continue;
      }

      // CP1256 Arabic Mapping (Windows-1256)
      int? cpValue;
      switch (codeUnit) {
        case 0x060C: cpValue = 0xA1; break; // Arabic Comma
        case 0x061B: cpValue = 0xBA; break; // Arabic Semicolon
        case 0x061F: cpValue = 0xBF; break; // Arabic Question Mark
        case 0x0621: cpValue = 0xC1; break; // Hamza
        case 0x0622: cpValue = 0xC2; break; // Alif with Madda
        case 0x0623: cpValue = 0xC3; break; // Alif with Hamza Above
        case 0x0624: cpValue = 0xC4; break; // Waw with Hamza
        case 0x0625: cpValue = 0xC5; break; // Alif with Hamza Below
        case 0x0626: cpValue = 0xC6; break; // Ya with Hamza
        case 0x0627: cpValue = 0xC7; break; // Alif
        case 0x0628: cpValue = 0xC8; break; // Ba
        case 0x0629: cpValue = 0xC9; break; // Ta Marbuta
        case 0x062A: cpValue = 0xCA; break; // Ta
        case 0x062B: cpValue = 0xCB; break; // Tha
        case 0x062C: cpValue = 0xCC; break; // Jeem
        case 0x062D: cpValue = 0xCD; break; // Hha
        case 0x062E: cpValue = 0xCE; break; // Kha
        case 0x062F: cpValue = 0xCF; break; // Dal
        case 0x0630: cpValue = 0xD0; break; // Thal
        case 0x0631: cpValue = 0xD1; break; // Ra
        case 0x0632: cpValue = 0xD2; break; // Zay
        case 0x0633: cpValue = 0xD3; break; // Seen
        case 0x0634: cpValue = 0xD4; break; // Sheen
        case 0x0635: cpValue = 0xD5; break; // Sad
        case 0x0636: cpValue = 0xD6; break; // Dad
        // F-PLU-1: Windows-1256 is NOT contiguous here — Latin-1 bytes are
        // interleaved among the Arabic letters (× at 0xD7, à at 0xE0, â at
        // 0xE2, ç/è at 0xE7/0xE8, ë at 0xEB, etc). The previous table assumed
        // contiguity from ط and was one-or-more bytes low for every letter
        // from ط on, corrupting Arabic PLU names. Values below are the
        // authoritative CP1256 mapping (Unicode.org CP1256.TXT).
        case 0x0637: cpValue = 0xD8; break; // Tah      ط  (0xD7 = ×)
        case 0x0638: cpValue = 0xD9; break; // Zah      ظ
        case 0x0639: cpValue = 0xDA; break; // Ain      ع
        case 0x063A: cpValue = 0xDB; break; // Ghain    غ
        case 0x0640: cpValue = 0xDC; break; // Tatweel  ـ
        case 0x0641: cpValue = 0xDD; break; // Fa       ف
        case 0x0642: cpValue = 0xDE; break; // Qaf      ق
        case 0x0643: cpValue = 0xDF; break; // Kaf      ك  (0xE0 = à)
        case 0x0644: cpValue = 0xE1; break; // Lam      ل  (0xE2 = â)
        case 0x0645: cpValue = 0xE3; break; // Meem     م
        case 0x0646: cpValue = 0xE4; break; // Noon     ن
        case 0x0647: cpValue = 0xE5; break; // Ha       ه
        case 0x0648: cpValue = 0xE6; break; // Waw      و  (0xE7 ç, 0xE8 è)
        case 0x0649: cpValue = 0xE9; break; // Alif Maksura ى
        case 0x064A: cpValue = 0xEA; break; // Ya       ي  (0xEB = ë)
        case 0x064B: cpValue = 0xEC; break; // Fathatan ً
        case 0x064C: cpValue = 0xED; break; // Dammatan ٌ
        case 0x064D: cpValue = 0xEE; break; // Kasratan ٍ
        case 0x064E: cpValue = 0xEF; break; // Fatha    َ
        case 0x064F: cpValue = 0xF0; break; // Damma    ُ
        case 0x0650: cpValue = 0xF1; break; // Kasra    ِ  (0xF2 = ò)
        case 0x0651: cpValue = 0xF3; break; // Shadda   ّ
        case 0x0652: cpValue = 0xF8; break; // Sukun    ْ
        case 0x00BB: cpValue = 0xBB; break; // »
        case 0x00AB: cpValue = 0xAB; break; // «
        default:
          cpValue = 0x3F; // Fallback '?'
      }
      bytes.add(cpValue);
    }
    return Uint8List.fromList(bytes);
  }
}
