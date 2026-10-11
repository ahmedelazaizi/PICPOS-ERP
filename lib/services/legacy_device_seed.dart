import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// البذرةُ القديمةُ المشتقّةُ من معرّف الجهاز — **ليست سرًّا**.
///
/// نُقل إليها منطقُ `SecurityService.getDatabaseEncryptionKey` (الفرع المشتقّ)
/// **حرفيًّا**: نفسُ `deviceId` ونفسُ الـpepper ونفسُ الـsha256، فالقيمةُ
/// الناتجةُ لا تتغيّر (قواعدُ العملاء الحاليّةُ مشفّرةٌ بها).
///
/// ⚠️ تُستعمل في مكانين فقط: (1) مرشّحَ فتحٍ قديمًا للقاعدة (المرحلة ب)،
/// (2) الـbearer القديم المشترك **داخل نافذة الانتقال** فقط. ولا تُستعمل
/// لاشتقاق أيّ سرٍّ جديدٍ للخادم — أسرارُ الخادم في `ServerSecrets`.
class LegacyDeviceSeed {
  LegacyDeviceSeed._();

  /// مزوّدُ معرّف الجهاز؛ يُستبدَل في الاختبارات. `null` = غير متاح.
  static Future<String?> Function() deviceIdProvider = _platformDeviceId;

  /// يعيد المشتقّ القديم، أو `null` إن لم يتوفّر معرّفُ جهاز (أو فشل
  /// `device_info_plus`). لا يولّد شيئًا ولا يلمس التخزينَ الآمن.
  static Future<String?> derive() async {
    try {
      final uniqueId = await deviceIdProvider();
      if (uniqueId == null || uniqueId.isEmpty) return null;
      return deriveFor(uniqueId);
    } catch (_) {
      return null;
    }
  }

  /// الاشتقاقُ الصرفُ من [uniqueId] (حرفيًّا كما كان في `SecurityService`).
  static String deriveFor(String uniqueId) {
    // Obfuscated pepper split into segments to hinder static analysis
    final p1 = String.fromCharCodes([85, 114, 97, 108, 67, 97, 115, 104]); // Ural
    final p2 = String.fromCharCodes(
        [95, 83, 101, 99, 117, 114, 105, 116, 121]); // Security
    final p3 = String.fromCharCodes(
        [95, 80, 101, 112, 112, 101, 114, 95, 118, 50]); // Pepper_v2
    final pepper = '$p1$p2$p3';

    final rawKey = '$uniqueId:$pepper';
    return sha256.convert(utf8.encode(rawKey)).toString();
  }

  static Future<String?> _platformDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isWindows) {
      return (await deviceInfo.windowsInfo).deviceId;
    } else if (Platform.isAndroid) {
      return (await deviceInfo.androidInfo).id;
    } else if (Platform.isIOS) {
      return (await deviceInfo.iosInfo).identifierForVendor;
    }
    return null;
  }
}
