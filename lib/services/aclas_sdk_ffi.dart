// ═══════════════════════════════════════════════════════════════════════════
// AclasSDK FFI — Dart bindings for AclasSDK.dll (Aclas/Rongta scale SDK)
// ═══════════════════════════════════════════════════════════════════════════
//
// Native x64 DLL for uploading/downloading PLU data to Aclas-compatible
// label scales (including Rongta RLS series) over UDP.

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../core/logging/diagnostic_logger.dart';
import 'scale_transport.dart';
import '../core/config/brand.dart';

export 'aclas_models.dart';
import 'aclas_models.dart';


// ─────────────────────────────────────────────────────────────────────
// Structs
// ─────────────────────────────────────────────────────────────────────

/// TASSDKDeviceInfo — 256 bytes, packed.
///
/// F-PLU-2: @Packed(1) is required — without it Dart FFI naturally aligns the
/// Uint64 `printerDot` to an 8-byte boundary, padding the struct to 264 bytes
/// and shifting every field after it (pluStorage/hotKeyCount/...) one-or-more
/// bytes high. The packed layout sums to exactly the documented 256 bytes.
@Packed(1)
final class TASSDKDeviceInfo extends Struct {
  @Uint32() external int protocolType;
  @Uint32() external int addr;
  @Uint32() external int port;
  @Array(16) external Array<Uint8> name;
  @Uint32() external int id;
  @Uint32() external int version;
  @Uint8() external int country;
  @Uint8() external int departmentID;
  @Uint8() external int keyType;
  @Uint64() external int printerDot;
  @Int64() external int prnStartDate;
  @Uint32() external int labelPage;
  @Uint32() external int printerNo;
  @Uint16() external int pluStorage;
  @Uint16() external int hotKeyCount;
  @Uint16() external int nutritionStorage;
  @Uint16() external int discountStorage;
  @Uint16() external int note1Storage;
  @Uint16() external int note2Storage;
  @Uint16() external int note3Storage;
  @Uint16() external int note4Storage;
  @Array(12) external Array<Uint8> firmwareVersion;
  @Uint8() external int defaultProtocol;
  @Uint8() external int lfCodeLen;
  @Array(4) external Array<Uint8> deviceId;
  @Array(4) external Array<Uint8> stockId;
  @Array(155) external Array<Uint8> adjunct;
}

// ─────────────────────────────────────────────────────────────────────
// Native function typedefs
// ─────────────────────────────────────────────────────────────────────

// void (__stdcall *)(uint32_t nErrorCode, uint32_t Index, uint32_t Total, void* lpUserData)
typedef NativeProgressCallback = Void Function(
    Uint32 nErrorCode, Uint32 index, Uint32 total, Pointer<Void> lpUserData);

typedef _InitializeNative = Bool Function(Pointer<Void> adjunct);
typedef _InitializeDart = bool Function(Pointer<Void> adjunct);

typedef _FinalizeNative = Void Function();
typedef _FinalizeDart = void Function();

typedef _GetDevicesInfoNative = Bool Function(
    Uint32 addr, Uint32 port, Uint32 protocolType, Pointer<TASSDKDeviceInfo> deviceInfo);
typedef _GetDevicesInfoDart = bool Function(
    int addr, int port, int protocolType, Pointer<TASSDKDeviceInfo> deviceInfo);

typedef _ExecTaskANative = Pointer<Void> Function(
    Uint32 addr, Uint32 port, Uint32 protocolType, Uint32 procType,
    Uint32 dataType, Pointer<Utf8> fileName,
    Pointer<NativeFunction<NativeProgressCallback>> onProgress,
    Pointer<Void> lpUserData);
typedef _ExecTaskADart = Pointer<Void> Function(
    int addr, int port, int protocolType, int procType,
    int dataType, Pointer<Utf8> fileName,
    Pointer<NativeFunction<NativeProgressCallback>> onProgress,
    Pointer<Void> lpUserData);

typedef _WaitForTaskNative = Void Function(Pointer<Void> taskHandle);
typedef _WaitForTaskDart = void Function(Pointer<Void> taskHandle);

typedef _GetLastTaskErrorNative = Int32 Function();
typedef _GetLastTaskErrorDart = int Function();

typedef _StopTaskNative = Void Function(Pointer<Void> taskHandle);
typedef _StopTaskDart = void Function(Pointer<Void> taskHandle);

// ─────────────────────────────────────────────────────────────────────
// SDK Wrapper
// ─────────────────────────────────────────────────────────────────────

/// ═══════════════════════════════════════════════════════════════════════════
/// File encoding for AclasSDK uploads
/// ═══════════════════════════════════════════════════════════════════════════
///
/// The official Rongta PLU Manager exports files as **UTF-16 LE + BOM**
/// (verified from `release_trial/2.xls`). `AclasSDK.dll` is built to read
/// exactly this format. CP1256 raw bytes were attempted but caused the DLL
/// to mis-read Arabic names (it interprets the stream as 16-bit code units
/// and garbles single-byte CP1256 data).
///
/// The DLL performs its own UTF-16 → CP1256 conversion internally using
/// the Windows ANSI code page, so Arabic systems (locale = Arabic/Egypt,
/// ANSI = 1256) get a correct conversion. On non-Arabic locales the DLL
/// produces wrong CP1256 bytes — on those systems the user must set the
/// "Language for non-Unicode programs" to Arabic in Windows Region
/// settings. This is the same requirement as the official PLU Manager
/// software, so it is expected behavior.
///
/// Text direction (RTL rendering) is handled by the scale firmware itself
/// — Fire Bird / Rongta RLS LCDs read logical-order Arabic and render it
/// right-to-left. Pre-reversing the text in Dart causes double-reversal
/// ("ستيك بلدى" → "ىدلب كيتس" on the LCD). [_prepareNameForScale] is
/// therefore a pass-through, kept only as an extension point for a
/// hypothetical future scale with a dumb LTR-only LCD.
class AclasSDK {
  static DynamicLibrary? _lib;
  static bool _initialized = false;
  static final ScaleTransport _transport = ScaleTransport();

  /// Encode a string as UTF-16 LE + BOM — the format `AclasSDK.dll` and the
  /// official Rongta PLU Manager both use. Verified against the reference
  /// template file `release_trial/2.xls`.
  static Uint8List _encodeUtf16LeBomBytes(String content) {
    final bytes = <int>[0xFF, 0xFE]; // UTF-16 LE BOM
    for (final cu in content.codeUnits) {
      bytes.add(cu & 0xFF);
      bytes.add((cu >> 8) & 0xFF);
    }
    return Uint8List.fromList(bytes);
  }

  /// Prepare an Arabic-containing name field for the scale LCD.
  ///
  /// The Fire Bird / Rongta RLS LCDs actually DO apply their own RTL
  /// rendering — they read Arabic logical-order input and display it
  /// visually right-to-left. Empirically verified (2026-04): pre-reversing
  /// the text caused it to appear double-reversed on the scale display
  /// (e.g., "ستيك بلدى" → "ىدلب كيتس"). So we pass Arabic names through
  /// in their original logical order.
  ///
  /// This function is kept as an extension point: if a different scale
  /// model is added later that has a dumb LTR-only LCD, we can add a
  /// brand-based flag and re-enable reversal here.
  static String _prepareNameForScale(String name) {
    return name;
  }

  static _InitializeDart? _initialize;
  static _FinalizeDart? _finalize;
  static _GetDevicesInfoDart? _getDevicesInfo;
  static _ExecTaskADart? _execTaskA;
  static _WaitForTaskDart? _waitForTask;
  static _GetLastTaskErrorDart? _getLastTaskError;
  static _StopTaskDart? _stopTask;

  /// Load the native library. Returns false if not found.
  static bool load() {
    if (_lib != null) return true;
    try {
      // Try loading from same directory as executable (bundled by CMake)
      _lib = DynamicLibrary.open('AclasSDK.dll');
    } catch (_) {
      try {
        // Fallback: look in windows/aclas_sdk/
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        _lib = DynamicLibrary.open('$exeDir/AclasSDK.dll');
      } catch (e) {
        debugPrint('[AclasSDK] Failed to load: $e');
        return false;
      }
    }

    _initialize = _lib!.lookupFunction<_InitializeNative, _InitializeDart>('AclasSDK_Initialize');
    _finalize = _lib!.lookupFunction<_FinalizeNative, _FinalizeDart>('AclasSDK_Finalize');
    _getDevicesInfo = _lib!.lookupFunction<_GetDevicesInfoNative, _GetDevicesInfoDart>('AclasSDK_GetDevicesInfo');
    _execTaskA = _lib!.lookupFunction<_ExecTaskANative, _ExecTaskADart>('AclasSDK_ExecTaskA');
    _waitForTask = _lib!.lookupFunction<_WaitForTaskNative, _WaitForTaskDart>('AclasSDK_WaitForTask');
    _getLastTaskError = _lib!.lookupFunction<_GetLastTaskErrorNative, _GetLastTaskErrorDart>('AclasSDK_GetLastTaskError');
    _stopTask = _lib!.lookupFunction<_StopTaskNative, _StopTaskDart>('AclasSDK_StopTask');

    debugPrint('[AclasSDK] Loaded successfully');
    return true;
  }

  /// Convert IP string "a.b.c.d" to uint32 (big-endian packed).
  static int ipToUint32(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return 0;
    int result = 0;
    for (int i = 0; i < 4; i++) {
      final v = int.tryParse(parts[i]) ?? 0;
      result += v << ((3 - i) * 8);
    }
    return result;
  }

  /// Initialize the SDK. Must be called before any other method.
  static bool initialize() {
    if (!load()) return false;
    if (_initialized) return true;
    _initialized = _initialize!(nullptr);
    debugPrint('[AclasSDK] Initialize: $_initialized');
    return _initialized;
  }

  /// Finalize the SDK. Call when done.
  static void finalizeSdk() {
    if (!_initialized) return;
    _finalize!();
    _initialized = false;
    debugPrint('[AclasSDK] Finalized');
  }

  /// منافذ UDP الاحتياطية لكشف موازين Aclas، مرتَّبة بالأشيَع أولاً.
  ///
  /// بلاغ العميل 2026-07-30: كانت هناك **قائمتان مختلفتان** لنفس الغرض —
  /// مسار «اختبار الاتصال» يجرّب `[9001, 9002, 10000, 3000, 8008]` بينما
  /// مسار الرفع الفعلي يجرّب `[9001, 5001]` فقط. النتيجة تناقض مباشر أمام
  /// المستخدم:
  ///
  ///   · ميزان على UDP 10000 ⇒ «اختبار الاتصال» ينجح، ثم الرفع يقول
  ///     «لم يتم كشف الميزان» على نفس الـ IP وفي نفس الدقيقة.
  ///   · ميزان على UDP 5001  ⇒ العكس: الاختبار يفشل فيظنّ المستخدم أن
  ///     الإعداد خطأ، بينما الرفع كان سينجح.
  ///
  /// قائمة واحدة الآن يقرأ منها المساران، فما يُكشَف في الاختبار يُكشَف في
  /// الرفع بالضرورة.
  static const List<int> fallbackUdpPorts = [9001, 5001, 9002, 10000, 3000, 8008];

  /// Get device info (auto-detect protocol and port).
  /// Returns null if device not found.
  static AclasDeviceInfo? getDeviceInfo(String ip, {int port = 0, int protocolType = 0}) {
    if (!_initialized) return null;
    final addr = ipToUint32(ip);
    final infoPtr = calloc<TASSDKDeviceInfo>();
    try {
      final found = _getDevicesInfo!(addr, port, protocolType, infoPtr);
      if (!found) {
        debugPrint('[AclasSDK] Device not found at $ip');
        return null;
      }
      final info = infoPtr.ref;
      final result = AclasDeviceInfo(
        protocolType: info.protocolType,
        addr: info.addr,
        port: info.port,
        pluStorage: info.pluStorage,
        version: info.version,
        defaultProtocol: info.defaultProtocol,
        hotKeyCount: info.hotKeyCount,
      );
      debugPrint('[AclasSDK] Device found: protocol=${result.protocolType}, '
          'port=${result.port}, maxPLU=${result.pluStorage}, '
          'hotKeys=${result.hotKeyCount}');
      return result;
    } finally {
      calloc.free(infoPtr);
    }
  }

  /// F-PLU-3: `ExecTaskA` is the ANSI entry point. A UTF-8 path with non-ASCII
  /// characters (e.g. an Arabic Windows username inside `%TEMP%`) can't be
  /// opened by the native side, so PLU upload/verify silently failed on
  /// Arabic-Windows installs. These helpers detect non-ASCII paths and stage
  /// the file in a guaranteed-ASCII directory before handing it to ExecTaskA.
  static bool isAsciiPath(String path) =>
      path.codeUnits.every((c) => c < 128);

  /// A guaranteed-ASCII, writable scratch dir. Prefers
  /// `C:\ProgramData\UralCash\scale_tmp`; falls back to the system temp dir.
  static Future<Directory> _asciiScaleTempDir() async {
    try {
      final dir = Directory('C:\\\\ProgramData\\\\${Brand.dataFolderName}\\\\scale_tmp');
      if (!await dir.exists()) await dir.create(recursive: true);
      if (isAsciiPath(dir.path)) return dir;
    } catch (_) {}
    return Directory.systemTemp;
  }

  /// Return an ASCII path for [path], copying the file into the ASCII scratch
  /// dir when the original contains non-ASCII characters. ASCII paths (the
  /// common case) are returned unchanged — no copy.
  static Future<String> _asciiInputPath(String path) async {
    if (isAsciiPath(path)) return path;
    final dir = await _asciiScaleTempDir();
    final dest =
        '${dir.path}\\plu_${DateTime.now().microsecondsSinceEpoch}.tmp';
    await File(path).copy(dest);
    return dest;
  }

  /// Upload PLU data to scale using the already-initialized SDK.
  ///
  /// [ip] — Scale IP address.
  /// [pluFilePath] — Path to tab-separated PLU text file.
  /// [deviceInfo] — Optional pre-detected device info (skips re-detection).
  ///
  /// NOTE: Runs synchronously (WaitForTask blocks) but scale uploads are
  /// typically fast (seconds). The SDK manages its own internal threads
  /// for UDP communication, so it cannot be run in a Dart Isolate
  /// (Initialize fails when called twice across isolates).
  static Future<AclasUploadResult> uploadPLU(
    String ip,
    String pluFilePath, {
    AclasDeviceInfo? deviceInfo,
  }) async {
    if (!_initialized) {
      return AclasUploadResult(success: false, message: 'SDK not initialized');
    }

    // Use pre-detected device info or detect now
    int detectedAddr;
    int detectedPort;
    int detectedProtocol;
    int maxPlu;

    if (deviceInfo != null) {
      detectedAddr = deviceInfo.addr;
      detectedPort = deviceInfo.port;
      detectedProtocol = deviceInfo.protocolType;
      maxPlu = deviceInfo.pluStorage;
    } else {
      final addr = ipToUint32(ip);
      final infoPtr = calloc<TASSDKDeviceInfo>();
      try {
        final found = _getDevicesInfo!(addr, 0, AclasProtocol.none, infoPtr);
        if (!found) {
          return AclasUploadResult(
            success: false,
            message: 'Device not found at $ip (auto-detect failed)',
          );
        }
        final info = infoPtr.ref;
        detectedAddr = info.addr;
        detectedPort = info.port;
        detectedProtocol = info.protocolType;
        maxPlu = info.pluStorage;
      } finally {
        calloc.free(infoPtr);
      }
    }

    debugPrint('[AclasSDK] Uploading PLU to addr=$detectedAddr, '
        'port=$detectedPort, protocol=$detectedProtocol');

    // Execute PLU download (to scale) task. F-PLU-3: stage on an ASCII path so
    // the ANSI ExecTaskA can open it on Arabic-Windows installs.
    final asciiPluPath = await _asciiInputPath(pluFilePath);
    final fileNamePtr = asciiPluPath.toNativeUtf8();
    try {
      final taskHandle = _execTaskA!(
        detectedAddr,
        detectedPort,
        detectedProtocol,
        AclasProcType.down,
        AclasDataType.plu,
        fileNamePtr,
        nullptr, // progress callback (not used — would need NativeCallable)
        nullptr,
      );

      if (taskHandle == nullptr) {
        final err = _getLastTaskError!();
        await DiagnosticLogger.log(DiagnosticLogger.plu,
            'uploadPLU ExecTask null, errorCode=$err addr=$detectedAddr port=$detectedPort');
        return AclasUploadResult(
          success: false,
          message: 'ExecTask returned null, error code=$err',
        );
      }

      // WaitForTask blocks until the SDK finishes sending all PLU records.
      // The SDK uses its own internal threads for UDP I/O.
      _waitForTask!(taskHandle);

      final lastErr = _getLastTaskError!();
      debugPrint('[AclasSDK] Upload done, lastError=$lastErr');
      if (lastErr != AclasErr.success) {
        // Phase 1 diagnostics: scale rejected the PLU upload — persist the SDK
        // error code so field scale failures are traceable.
        await DiagnosticLogger.log(DiagnosticLogger.plu,
            'uploadPLU failed, errorCode=$lastErr protocol=$detectedProtocol port=$detectedPort');
      }

      return AclasUploadResult(
        success: lastErr == AclasErr.success,
        message: lastErr == AclasErr.success
            ? 'تم ترحيل PLU بنجاح (بروتوكول=$detectedProtocol, منفذ=$detectedPort, maxPLU=$maxPlu)'
            : 'فشل الترحيل — كود الخطأ: $lastErr',
        detectedProtocol: detectedProtocol,
        detectedPort: detectedPort,
        maxPlu: maxPlu,
      );
    } finally {
      calloc.free(fileNamePtr);
    }
  }

  /// Generic data file upload — works for ANY AclasDataType.
  ///
  /// Uploads a tab-separated UTF-16 LE file to the scale using the
  /// specified [dataType]. This is the core method used for all data types:
  /// departments, units, PLU, hotkeys, groups, etc.
  ///
  /// The upload sequence for a full scale programming session should be:
  ///   1. Department (0x0002) — prerequisite, PLU records reference DepartmentID
  ///   2. Unit (0x0001)       — prerequisite, PLU records reference UnitID
  ///   3. PLU (0x0000)        — main product data
  ///   4. HotKey (0x0003)     — keyboard shortcuts mapped to PLU IDs
  ///
  /// [dataTypeName] is used only for logging (e.g. "Department", "Unit", "PLU").
  static Future<AclasUploadResult> uploadDataFile(
    String ip,
    String filePath,
    int dataType,
    String dataTypeName, {
    AclasDeviceInfo? deviceInfo,
  }) async {
    if (!_initialized) {
      return AclasUploadResult(success: false, message: 'SDK not initialized');
    }

    int detectedAddr;
    int detectedPort;
    int detectedProtocol;

    if (deviceInfo != null) {
      detectedAddr = deviceInfo.addr;
      detectedPort = deviceInfo.port;
      detectedProtocol = deviceInfo.protocolType;
    } else {
      final addr = ipToUint32(ip);
      final infoPtr = calloc<TASSDKDeviceInfo>();
      try {
        final found = _getDevicesInfo!(addr, 0, AclasProtocol.none, infoPtr);
        if (!found) {
          return AclasUploadResult(
            success: false,
            message: 'Device not found at $ip for $dataTypeName upload',
          );
        }
        final info = infoPtr.ref;
        detectedAddr = info.addr;
        detectedPort = info.port;
        detectedProtocol = info.protocolType;
      } finally {
        calloc.free(infoPtr);
      }
    }

    // ── Diagnostic: file size + head-bytes preview (helps identify
    // encoding issues, truncated files, or unexpected content) ──
    int fileSize = 0;
    String headPreview = '';
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final stat = await file.stat();
        fileSize = stat.size;
        final fileBytes = await file.readAsBytes();
        final head = fileBytes.take(120).toList();
        headPreview = head
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ');
      }
    } catch (e) {
      debugPrint('[AclasSDK] could not stat file $filePath: $e');
    }

    debugPrint('[AclasSDK] Uploading $dataTypeName (type=0x${dataType.toRadixString(16)}) '
        'to addr=$detectedAddr, port=$detectedPort, protocol=$detectedProtocol, '
        'fileSize=$fileSize bytes');
    if (headPreview.isNotEmpty) {
      debugPrint('[AclasSDK] $dataTypeName head: $headPreview');
    }

    // F-PLU-3: ASCII-safe path for the ANSI ExecTaskA.
    final asciiFilePath = await _asciiInputPath(filePath);
    final fileNamePtr = asciiFilePath.toNativeUtf8();
    try {
      final execStart = DateTime.now();
      final taskHandle = _execTaskA!(
        detectedAddr,
        detectedPort,
        detectedProtocol,
        AclasProcType.down,      // download TO scale
        dataType,
        fileNamePtr,
        nullptr,
        nullptr,
      );
      final execElapsed = DateTime.now().difference(execStart).inMilliseconds;
      debugPrint('[AclasSDK] $dataTypeName _execTaskA dispatched in ${execElapsed}ms');

      if (taskHandle == nullptr) {
        final err = _getLastTaskError!();
        return AclasUploadResult(
          success: false,
          message: '$dataTypeName ExecTask returned null, error code=$err',
        );
      }

      final waitStart = DateTime.now();
      _waitForTask!(taskHandle);
      final waitElapsed = DateTime.now().difference(waitStart).inMilliseconds;

      final lastErr = _getLastTaskError!();
      debugPrint('[AclasSDK] $dataTypeName upload done in ${waitElapsed}ms, '
          'lastError=$lastErr (0x${lastErr.toRadixString(16)})');

      return AclasUploadResult(
        success: lastErr == AclasErr.success,
        message: lastErr == AclasErr.success
            ? 'تم ترحيل $dataTypeName بنجاح (${waitElapsed}ms, $fileSize بايت)'
            : 'فشل ترحيل $dataTypeName — كود الخطأ: $lastErr (${waitElapsed}ms)',
        detectedProtocol: detectedProtocol,
        detectedPort: detectedPort,
      );
    } finally {
      calloc.free(fileNamePtr);
    }
  }

  /// Read back PLU records from the scale and count the lines present.
  ///
  /// Uses `AclasProcType.up` (upload FROM scale → download TO the PC) to
  /// request the current PLU table. Returns the number of data rows found
  /// (excluding the header line).
  ///
  /// Returns -1 if the SDK call fails (device not reachable / protocol
  /// error / timeout). In that case, the caller should NOT treat it as
  /// "zero items" — it's unknown, so skip verification.
  ///
  /// Used to verify that a multi-item PLU upload actually persisted on the
  /// scale. Some Aclas-compatible firmwares acknowledge the upload but
  /// silently drop records that reference missing prerequisites or that
  /// fail their internal validation.
  static Future<int> verifyPLUCount(
    String ip, {
    AclasDeviceInfo? deviceInfo,
  }) async {
    if (!_initialized) {
      debugPrint('[AclasSDK] verifyPLUCount: SDK not initialized');
      return -1;
    }

    int detectedAddr;
    int detectedPort;
    int detectedProtocol;

    if (deviceInfo != null) {
      detectedAddr = deviceInfo.addr;
      detectedPort = deviceInfo.port;
      detectedProtocol = deviceInfo.protocolType;
    } else {
      final addr = ipToUint32(ip);
      final infoPtr = calloc<TASSDKDeviceInfo>();
      try {
        final found = _getDevicesInfo!(addr, 0, AclasProtocol.none, infoPtr);
        if (!found) {
          debugPrint('[AclasSDK] verifyPLUCount: device not found at $ip');
          return -1;
        }
        final info = infoPtr.ref;
        detectedAddr = info.addr;
        detectedPort = info.port;
        detectedProtocol = info.protocolType;
      } finally {
        calloc.free(infoPtr);
      }
    }

    // F-PLU-3: ANSI ExecTaskA reads back through this path — keep it ASCII so
    // an Arabic Windows username in %TEMP% can't break the read.
    final tempDir = await _asciiScaleTempDir();
    final readBackPath =
        '${tempDir.path}\\aclas_verify_plu_${DateTime.now().microsecondsSinceEpoch}.txt';
    // Ensure the file doesn't exist before the SDK writes to it
    try { await File(readBackPath).delete(); } catch (_) {}

    final fileNamePtr = readBackPath.toNativeUtf8();
    try {
      final taskHandle = _execTaskA!(
        detectedAddr,
        detectedPort,
        detectedProtocol,
        AclasProcType.up,   // read FROM scale
        AclasDataType.plu,
        fileNamePtr,
        nullptr,
        nullptr,
      );
      if (taskHandle == nullptr) {
        debugPrint('[AclasSDK] verifyPLUCount: _execTaskA returned null');
        return -1;
      }
      _waitForTask!(taskHandle);
      final err = _getLastTaskError!();
      if (err != AclasErr.success) {
        debugPrint('[AclasSDK] verifyPLUCount: error $err (0x${err.toRadixString(16)})');
        return -1;
      }
    } finally {
      calloc.free(fileNamePtr);
    }

    // Count non-empty data rows in the retrieved file.
    // File is written in CP1256 or UTF-16 depending on the firmware — we
    // only need to count CRLF-delimited lines, which works with either.
    try {
      final file = File(readBackPath);
      if (!await file.exists()) {
        debugPrint('[AclasSDK] verifyPLUCount: readback file missing');
        return -1;
      }
      final bytes = await file.readAsBytes();
      // Count 0x0A (LF) bytes — CRLF terminated lines have one LF each.
      // Subtract 1 for the header row (if present).
      int lfCount = 0;
      for (final b in bytes) {
        if (b == 0x0A) lfCount++;
      }
      final dataLines = lfCount > 0 ? lfCount - 1 : 0;
      debugPrint('[AclasSDK] verifyPLUCount: $dataLines data rows in ${bytes.length} bytes');
      try { await file.delete(); } catch (_) {}
      return dataLines;
    } catch (e) {
      debugPrint('[AclasSDK] verifyPLUCount parse error: $e');
      return -1;
    }
  }

  /// Upload HotKey mapping to scale (convenience wrapper around uploadDataFile).
  static Future<AclasUploadResult> uploadHotKeys(
    String ip,
    String hotKeyFilePath, {
    AclasDeviceInfo? deviceInfo,
  }) async {
    return uploadDataFile(ip, hotKeyFilePath, AclasDataType.hotKey, 'HotKey',
        deviceInfo: deviceInfo);
  }

  /// Generate a HotKey mapping file in the AclasSDK format.
  ///
  /// Format: UTF-16 LE with BOM, Tab-separated, 3 columns.
  /// Columns: KeyNo (1-based physical button position) \t Mode \t PLU (PLU ID to assign)
  ///
  /// Mode=0 means default page (most scales have shift/page buttons for extra layers).
  /// KeyNo must be sequential starting from 1 — it represents the PHYSICAL button
  /// position on the scale's keyboard, NOT the PLU number. Most Aclas-compatible
  /// scales have 24-56 physical hotkey buttons; any KeyNo beyond that is ignored.
  static Future<String> generateHotKeyFile(
    List<AclasHotKeyMapping> mappings,
    String outputPath,
  ) async {
    final sb = StringBuffer();
    // Full header — 3-column format matches official AclasSDK HotKey Demo.txt.
    // CRLF line endings required by Aclas-compatible firmware.
    sb.write('KeyNo\tMode\tPLU\t\r\n');

    for (final m in mappings) {
      sb.write('${m.keyNo}\t${m.mode}\t${m.pluId}\t\r\n');
    }

    // Encode as UTF-16 LE + BOM (matches AclasSDK/PLU Manager format)
    final bytes = _encodeUtf16LeBomBytes(sb.toString());

    final file = File(outputPath);
    await file.writeAsBytes(bytes);
    debugPrint('[AclasSDK] Generated HotKey file: $outputPath '
        '(${mappings.length} keys, ${bytes.length} bytes, UTF-16 LE)');
    for (final m in mappings.take(5)) {
      debugPrint('[AclasSDK]   Key ${m.keyNo} (mode=${m.mode}) -> PLU ${m.pluId}');
    }
    return outputPath;
  }

  /// Generate a Department file in the AclasSDK format.
  ///
  /// Format: UTF-16 LE with BOM, Tab-separated.
  /// Columns: ID \t Name
  ///
  /// PLU records reference DepartmentID — the department MUST exist in the
  /// scale's memory before PLU data is uploaded. Without it, PLU records
  /// that reference a non-existent department are silently rejected.
  static Future<String> generateDepartmentFile(
    List<AclasDepartment> departments,
    String outputPath,
  ) async {
    final sb = StringBuffer();
    sb.write('ID\tName\t\r\n');
    for (final dept in departments) {
      sb.write('${dept.id}\t${_prepareNameForScale(dept.name)}\t\r\n');
    }

    // Encode as UTF-16 LE + BOM (matches AclasSDK/PLU Manager format)
    final bytes = _encodeUtf16LeBomBytes(sb.toString());

    final file = File(outputPath);
    await file.writeAsBytes(bytes);
    debugPrint('[AclasSDK] Generated Department file: $outputPath '
        '(${departments.length} depts, ${bytes.length} bytes, UTF-16 LE)');
    return outputPath;
  }

  /// Generate a Unit file in the AclasSDK format.
  ///
  /// Format: UTF-16 LE with BOM, Tab-separated.
  /// Columns: ID \t Name
  ///
  /// PLU records reference UnitID (4=kg, 10=pcs) — the unit MUST exist in
  /// the scale's memory before PLU data is uploaded. Without it, PLU records
  /// that reference a non-existent unit are silently rejected.
  static Future<String> generateUnitFile(
    List<AclasUnit> units,
    String outputPath,
  ) async {
    final sb = StringBuffer();
    sb.write('ID\tName\t\r\n');
    for (final unit in units) {
      sb.write('${unit.id}\t${_prepareNameForScale(unit.name)}\t\r\n');
    }

    // Encode as UTF-16 LE + BOM (matches AclasSDK/PLU Manager format)
    final bytes = _encodeUtf16LeBomBytes(sb.toString());

    final file = File(outputPath);
    await file.writeAsBytes(bytes);
    debugPrint('[AclasSDK] Generated Unit file: $outputPath '
        '(${units.length} units, ${bytes.length} bytes, UTF-16 LE)');
    return outputPath;
  }

  /// Generate a Group file in the AclasSDK format.
  ///
  /// Format: UTF-16 LE with BOM, Tab-separated.
  /// Columns: ID \t Name
  ///
  /// PLU records reference GroupID — should exist in scale memory.
  static Future<String> generateGroupFile(
    List<AclasGroup> groups,
    String outputPath,
  ) async {
    final sb = StringBuffer();
    sb.write('ID\tName\t\r\n');
    for (final group in groups) {
      sb.write('${group.id}\t${_prepareNameForScale(group.name)}\t\r\n');
    }

    // Encode as UTF-16 LE + BOM (matches AclasSDK/PLU Manager format)
    final bytes = _encodeUtf16LeBomBytes(sb.toString());

    final file = File(outputPath);
    await file.writeAsBytes(bytes);
    debugPrint('[AclasSDK] Generated Group file: $outputPath '
        '(${groups.length} groups, ${bytes.length} bytes, UTF-16 LE)');
    return outputPath;
  }

  /// Generate a PLU text file in the AclasSDK format.
  ///
  /// Format: UTF-16 LE with BOM, Tab-separated, 60 columns.
  /// The SDK auto-detects column count — we use the full 60-column format
  /// from the official PLU Demo.txt for maximum compatibility.
  static Future<String> generatePLUFile(
    List<AclasPLUItem> items,
    String outputPath,
  ) async {
    final sb = StringBuffer();
    // Full 60-column header (official AclasSDK format)
    // IMPORTANT: Use CRLF (\r\n) — Chinese scale software (PLU Manager, Aclas)
    // expects Windows line endings. Dart's writeln() emits only \n which causes
    // the scale to parse all rows as one line → only the first PLU gets stored.
    sb.write('ID\tItemCode\tDepartmentID\tGroupID\tName1\tName2\tName3\t'
        'Price\tUnitID\tBarcodeType1\tBarcodeType2\tLabel1ID\tLabel2ID\t'
        'ProducedDate\tFreshnessDate\tValidDate\tPackageType\tPackageWeight\t'
        'PackagePrice\tPackageRange\tPackageDays\tPackageHours\tText1ID\t'
        'Text2ID\tText3ID\tText4ID\tText5ID\tText6ID\tText7ID\tText8ID\t'
        'DiscountID\tDiscountRate\tHalfDiscount\tQuarterDiscount\tTareID\t'
        'TareValue\tIceID\tICEValue\tOriginID\tTraceabilityID\tLimitPrice\t'
        'Tax1\tTax2\tTax3\tTax4\tFlag1\tFlag2\tFlag3\tProducedDateRule\t'
        'FreshnessDateFrom\tValidDateFrom\tPackageDateFrom\tSpeedCode\t'
        'Position1\tSalesCategory\tDiscountBeginTime\tDiscountEndTime\t'
        'DiscountPrice\tDiscountFlag\t\r\n');

    final now = DateTime.now();
    final dateStr = '${now.year}/${now.month}/${now.day} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final position = i + 1;  // 1-based position on the keyboard layout
      // Reverse Arabic runs so the name renders correctly on the scale's
      // LTR LCD (no bidi engine on the firmware).
      final scaleName = _prepareNameForScale(item.name);
      // Fill all 60 columns (missing = 0). Use CRLF line endings.
      //
      // CRITICAL:
      //   - SpeedCode = item.id (unique, used for scale's numeric keypad entry)
      //   - Position1 = (i+1) UNIQUE per item. Previously 0 for all → caused all
      //     items to map to same keyboard slot → only 1 item visible on scale.
      //   - SalesCategory = 1 marks the item as active/sellable (was empty → some
      //     scale firmwares treat empty as "disabled").
      sb.write(
        '${item.id}\t'                // ID
        '${item.itemCode}\t'          // ItemCode
        '${item.departmentId}\t'      // DepartmentID
        '1\t'                         // GroupID
        '$scaleName\t'                // Name1 (Arabic reversed for LTR LCD)
        '\t'                          // Name2
        '\t'                          // Name3
        '${item.price}\t'             // Price
        '${item.unitId}\t'            // UnitID (4=kg, 10=pcs)
        '${item.barcodeType1}\t'      // BarcodeType1
        '${item.barcodeType2}\t'      // BarcodeType2
        '1\t'                         // Label1ID
        '0\t'                         // Label2ID
        '$dateStr\t'                  // ProducedDate
        '0\t0\t'                      // FreshnessDate, ValidDate
        '0\t0\t0\t0\t0\t0\t'         // Package fields
        '0\t0\t0\t0\t0\t0\t0\t0\t'   // Text IDs
        '0\t0\t0\t0\t'               // Discount
        '0\t${item.tareWeight}\t'     // TareID, TareValue
        '0\t0\t'                      // IceID, ICEValue
        '0\t0\t0\t'                   // Origin, Traceability, LimitPrice
        '0\t0\t0\t0\t'               // Tax1-4
        '0\t0\t0\t'                   // Flag1-3
        '0\t0\t0\t0\t'               // DateRules
        '${item.id}\t'               // SpeedCode
        '$position\t1\t'              // Position1 (unique!), SalesCategory=1 (active)
        '1899/12/30\t1899/12/30\t'    // DiscountBeginTime, DiscountEndTime
        '0\t0\t\r\n'                  // DiscountPrice, DiscountFlag
      );
    }

    // Encode as UTF-16 LE + BOM — the format AclasSDK.dll expects. Arabic
    // names require Windows locale set to Arabic for correct display.
    final bytes = _encodeUtf16LeBomBytes(sb.toString());

    final file = File(outputPath);
    await file.writeAsBytes(bytes);
    debugPrint('[AclasSDK] Generated PLU file: $outputPath '
        '(${items.length} items, ${bytes.length} bytes, UTF-16 LE)');
    return outputPath;
  }
}

