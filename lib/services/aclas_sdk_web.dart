// نسخة الويب من aclas_sdk_ffi.dart: AclasSDK.dll عبر dart:ffi لا تُترجم للويب
// (موازين الملصقات خارج نطاق الويب). نفس التوقيعات العامة؛ الكشف يعيد null/false
// والرفع يعيد فشلًا صريحًا.
import 'aclas_models.dart';

export 'aclas_models.dart';

class AclasSDK {
  static const String _msg = 'AclasSDK غير متاح على الويب';

  static bool load() => false;
  static bool initialize() => false;
  static void finalizeSdk() {}

  static int ipToUint32(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return 0;
    var v = 0;
    for (final p in parts) {
      v = (v << 8) | ((int.tryParse(p) ?? 0) & 0xFF);
    }
    return v;
  }

  static const List<int> fallbackUdpPorts = [9001, 5001, 9002, 10000, 3000, 8008];

  static AclasDeviceInfo? getDeviceInfo(String ip,
          {int port = 0, int protocolType = 0}) =>
      null;

  static bool isAsciiPath(String path) => path.codeUnits.every((c) => c < 128);

  static Future<AclasUploadResult> uploadPLU(
    String ip,
    String pluFilePath, {
    AclasDeviceInfo? deviceInfo,
  }) async =>
      AclasUploadResult(success: false, message: _msg);

  static Future<AclasUploadResult> uploadDataFile(
    String ip,
    String filePath,
    int dataType,
    String dataTypeName, {
    AclasDeviceInfo? deviceInfo,
  }) async =>
      AclasUploadResult(success: false, message: _msg);

  static Future<int> verifyPLUCount(
    String ip, {
    AclasDeviceInfo? deviceInfo,
  }) async =>
      -1;

  static Future<AclasUploadResult> uploadHotKeys(
    String ip,
    String hotKeyFilePath, {
    AclasDeviceInfo? deviceInfo,
  }) async =>
      AclasUploadResult(success: false, message: _msg);

  static Future<String> generateHotKeyFile(
          List<AclasHotKeyMapping> mappings, String outputPath) async =>
      throw UnsupportedError(_msg);

  static Future<String> generateDepartmentFile(
          List<AclasDepartment> departments, String outputPath) async =>
      throw UnsupportedError(_msg);

  static Future<String> generateUnitFile(
          List<AclasUnit> units, String outputPath) async =>
      throw UnsupportedError(_msg);

  static Future<String> generateGroupFile(
          List<AclasGroup> groups, String outputPath) async =>
      throw UnsupportedError(_msg);

  static Future<String> generatePLUFile(
          List<AclasPLUItem> items, String outputPath) async =>
      throw UnsupportedError(_msg);
}