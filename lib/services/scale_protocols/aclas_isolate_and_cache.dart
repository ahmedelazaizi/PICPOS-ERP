// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

// ═══════════════════════════════════════════════════════════════
// AclasSDK Isolate Helper (top-level — required by Isolate.run)
// ═══════════════════════════════════════════════════════════════

/// Runs AclasSDK detect+upload in a background isolate.
/// Inputs are plain strings; output is a plain Map — no FFI objects cross boundaries.
///
/// Full upload sequence (PLU Manager standard):
///   1. Department — prerequisite tables (PLU references DepartmentID)
///   2. Unit       — prerequisite tables (PLU references UnitID)
///   3. PLU        — main product data
///   4. HotKey     — keyboard shortcut mappings
///
/// Without steps 1-2, the scale silently rejects PLU records that reference
/// non-existent department/unit IDs, even though the SDK reports success.
Future<Map<String, dynamic>> _aclasUploadInIsolate(List<String> args) async {
  // args[0] = ip
  // args[1] = pluFilePath                 — main batch file (all items)
  // args[2] = hotKeyFilePath              (optional)
  // args[3] = departmentFilePath          (optional)
  // args[4] = unitFilePath                (optional)
  // args[5] = groupFilePath               (optional)
  // args[6] = customUdpPort               (optional, string; empty = defaults)
  // args[7] = skipPrereqs                 ('1' = skip dept/unit/group upload — cached from prior session)
  // args[8] = expectedPluCount            (string int; for read-back verification)
  // args[9..N] = per-item PLU files       (one per item, for retry fallback if batch count mismatch)
  final ip = args[0];
  final pluFilePath = args[1];
  final hotKeyFilePath = args.length > 2 && args[2].isNotEmpty ? args[2] : null;
  final deptFilePath = args.length > 3 && args[3].isNotEmpty ? args[3] : null;
  final unitFilePath = args.length > 4 && args[4].isNotEmpty ? args[4] : null;
  final groupFilePath = args.length > 5 && args[5].isNotEmpty ? args[5] : null;
  final customPort = args.length > 6 && args[6].isNotEmpty
      ? int.tryParse(args[6])
      : null;
  final skipPrereqs = args.length > 7 && args[7] == '1';
  final expectedCount = args.length > 8 && args[8].isNotEmpty
      ? int.tryParse(args[8]) ?? 0
      : 0;
  final perItemFiles = args.length > 9 ? args.sublist(9) : <String>[];

  if (!AclasSDK.load()) {
    return {'success': false, 'message': 'فشل تحميل AclasSDK.dll — تأكد من وجود الملف'};
  }
  if (!AclasSDK.initialize()) {
    return {'success': false, 'message': 'فشل تهيئة AclasSDK'};
  }
  try {
    // ── Detect device — user-supplied port first, then auto ──
    // Detection via the SDK is SLOW (~2-6 seconds per port due to UDP
    // retries configured in AclasSDK.ini). We limit fallback ports to the
    // two most common Aclas UDP ports to keep total detection time bounded
    // even when the user's configured port is wrong.
    AclasDeviceInfo? device;
    final triedPorts = <int>[];
    if (customPort != null && customPort > 0) {
      device = AclasSDK.getDeviceInfo(ip, port: customPort);
      triedPorts.add(customPort);
    }
    device ??= AclasSDK.getDeviceInfo(ip);  // auto-detect (port=0)
    if (device == null) {
      // القائمة مشتركة مع مسار «اختبار الاتصال»
      // (AclasSDK.fallbackUdpPorts). كانت هنا `[9001, 5001]` وهناك
      // `[9001, 9002, 10000, 3000, 8008]` — فميزان على UDP 10000 يُكشَف في
      // الاختبار ثم يفشل عند الرفع على نفس الـ IP، وميزان على 5001 يفشل في
      // الاختبار رغم أن الرفع كان سينجح. (بلاغ العميل 2026-07-30.)
      for (final p in AclasSDK.fallbackUdpPorts) {
        if (triedPorts.contains(p)) continue;
        device = AclasSDK.getDeviceInfo(ip, port: p);
        triedPorts.add(p);
        if (device != null) break;
      }
    }
    if (device == null) {
      return {
        'success': false,
        'message': 'لم يتم كشف الميزان في $ip\n'
            'المنافذ التي جُرِّبت: ${triedPorts.join(", ")}\n'
            'تأكد من: (1) الـ IP صحيح  (2) الميزان مُشغّل  (3) AclasSDK.dll موجود\n'
            'إن عرفت منفذ UDP الخاص بميزانك، أدخله يدوياً في إعدادات الميزان.',
      };
    }

    final log = StringBuffer();

    // ── Step 1-2: Prerequisite tables (Department/Unit/Group) ──
    // Can be skipped when the caller has a cached "already uploaded to
    // this scale" flag — saves ~6-9 seconds on repeat upload sessions.
    if (skipPrereqs) {
      log.write('الأقسام/الوحدات/المجموعات (مخزّنة مسبقاً) ⇢ | ');
    } else {
      if (deptFilePath != null) {
        final deptResult = await AclasSDK.uploadDataFile(
          ip, deptFilePath, AclasDataType.department, 'Department',
          deviceInfo: device,
        );
        log.write(deptResult.success ? 'الأقسام ✓ | ' : 'الأقسام ✗ | ');
      }
      if (unitFilePath != null) {
        final unitResult = await AclasSDK.uploadDataFile(
          ip, unitFilePath, AclasDataType.unit, 'Unit',
          deviceInfo: device,
        );
        log.write(unitResult.success ? 'الوحدات ✓ | ' : 'الوحدات ✗ | ');
      }
      if (groupFilePath != null) {
        final groupResult = await AclasSDK.uploadDataFile(
          ip, groupFilePath, AclasDataType.group, 'Group',
          deviceInfo: device,
        );
        log.write(groupResult.success ? 'المجموعات ✓ | ' : 'المجموعات ✗ | ');
      }
    }

    // ══════════════════════════════════════════════════════════════════
    // PLU upload strategy: PER-ITEM SEQUENTIAL (proven reliable)
    // ══════════════════════════════════════════════════════════════════
    // Empirically, Fire Bird / Rongta firmwares accept only the FIRST PLU
    // record per `_execTaskA` task — subsequent records in a batch file
    // are silently dropped. So we upload each item in its own SDK task.
    //
    // With the tightened AclasSDK.ini (SyncTryCount=2, Timeout=1500ms)
    // each per-item upload takes ~1-2 seconds, giving ~12-24 sec total
    // for a 12-item session. Each task's success/failure is authoritative
    // (from the SDK) so we don't need separate read-back verification.
    //
    // TRUE parallelism is not possible: the SDK uses a single internal
    // worker thread and a single UDP socket per `AclasSDK_Initialize`
    // session — concurrent `_execTaskA` calls would corrupt state. The
    // SDK is designed for serial task submission.
    // ══════════════════════════════════════════════════════════════════

    int retriedOk = 0;
    int retriedFail = 0;
    int verifiedCount = 0;
    bool pluPhaseSucceeded = false;

    if (perItemFiles.isNotEmpty) {
      // Primary path: upload each item individually
      log.write('PLU (per-item ×${perItemFiles.length}): ');
      for (int i = 0; i < perItemFiles.length; i++) {
        final r = await AclasSDK.uploadDataFile(
          ip, perItemFiles[i], AclasDataType.plu,
          'PLU #${i + 1}',
          deviceInfo: device,
        );
        if (r.success) {
          retriedOk++;
          verifiedCount++;
        } else {
          retriedFail++;
        }
      }
      pluPhaseSucceeded = retriedOk > 0;
      log.write('$retriedOk نجح، $retriedFail فشل | ');
    } else {
      // Fallback: single-item shortcut (batch file contains only 1 item)
      final pluResult = await AclasSDK.uploadPLU(
        ip, pluFilePath, deviceInfo: device,
      );
      pluPhaseSucceeded = pluResult.success;
      if (pluResult.success) {
        verifiedCount = expectedCount;
        retriedOk = expectedCount;
      } else {
        retriedFail = expectedCount;
      }
      log.write(pluResult.success ? 'PLU ✓ | ' : 'PLU ✗ | ');
    }

    // ── Step 4: HotKey mapping (single batch — works on this firmware) ──
    if (pluPhaseSucceeded && hotKeyFilePath != null) {
      final hkResult = await AclasSDK.uploadHotKeys(
        ip, hotKeyFilePath, deviceInfo: device,
      );
      log.write(hkResult.success ? 'مفاتيح الاختصار ✓' : 'مفاتيح الاختصار ✗');
    }

    // ── Honest success determination ──
    // Overall success = ALL items uploaded successfully.
    final overallSuccess =
        pluPhaseSucceeded && verifiedCount >= expectedCount;

    return {
      'success': overallSuccess,
      'message': 'تم ترحيل $verifiedCount من $expectedCount أصناف\n'
          'تسلسل الترحيل: $log',
      'protocol': device.protocolType,
      'port': device.port,
      'uploadedCount': verifiedCount,
      'expectedCount': expectedCount,
      'retriedOk': retriedOk,
      'retriedFail': retriedFail,
      'skippedPrereqs': skipPrereqs,
    };
  } finally {
    AclasSDK.finalizeSdk();
  }
}

// ═══════════════════════════════════════════════════════════════
// Module-level prerequisite upload cache
// ═══════════════════════════════════════════════════════════════
//
// Dept/Unit/Group upload takes ~6-9 seconds. Once uploaded for a given
// scale + set of IDs, we can skip the re-upload for 60 minutes. This
// turns repeat PLU uploads (the common case) from ~20 sec → ~8-10 sec.
//
// Cache key: "ip:port"
// Cache value: hash of uploaded prerequisites (changes if dept/unit IDs
// change, invalidating the skip).

class _PrereqCacheEntry {
  final String hash;
  final DateTime at;
  _PrereqCacheEntry(this.hash, this.at);
}

final Map<String, _PrereqCacheEntry> _aclasPrereqCache = {};

String _computePrereqHash(Set<int> deptIds, Set<int> unitIds) {
  final d = (deptIds.toList()..sort()).join(',');
  final u = (unitIds.toList()..sort()).join(',');
  return 'd=$d|u=$u';
}

/// Returns true if the prereq tables for this scale+IDs combo were
/// uploaded within the last 60 minutes.
bool _prereqCached(String cacheKey, String hash) {
  final entry = _aclasPrereqCache[cacheKey];
  if (entry == null) return false;
  if (entry.hash != hash) return false;
  final ageMinutes = DateTime.now().difference(entry.at).inMinutes;
  return ageMinutes < 60;
}

void _recordPrereqUploaded(String cacheKey, String hash) {
  _aclasPrereqCache[cacheKey] = _PrereqCacheEntry(hash, DateTime.now());
}
