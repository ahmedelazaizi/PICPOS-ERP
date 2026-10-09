// نماذج وثوابت AclasSDK الخالية من dart:ffi (مشتركة بين النسخة الأصلية ونسخة الويب).

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

/// Error / progress codes returned by the SDK callback.
class AclasErr {
  static const int success = 0x0000;
  static const int progress = 0x0001;
  static const int terminate = 0x0002;
}

/// Protocol type (auto-detect = 0).
class AclasProtocol {
  static const int none = 0; // auto-detect
  static const int pecr = 1;
  static const int hecr = 2;
  static const int tsecr = 3;
}

/// Procedure type.
class AclasProcType {
  static const int down = 0;   // download TO scale
  static const int up = 1;     // upload FROM scale
  static const int edit = 2;
  static const int del = 3;
  static const int list = 4;
  static const int empty = 5;
}

/// Data type.
class AclasDataType {
  static const int plu = 0x0000;
  static const int unit = 0x0001;
  static const int department = 0x0002;
  static const int hotKey = 0x0003;
  static const int group = 0x0004;
  static const int discount = 0x0005;
  static const int tare = 0x000A;
  static const int nutrition = 0x000B;
  static const int note1 = 0x000C;
  static const int note2 = 0x000D;
  static const int note3 = 0x000E;
  static const int options = 0x0010;
  static const int customBarcode = 0x0011;
}

// ─────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────

class AclasDeviceInfo {
  final int protocolType;
  final int addr;
  final int port;
  final int pluStorage;
  final int version;
  final int defaultProtocol;
  /// Total number of physical hotkey buttons on the scale's keyboard.
  /// Common layouts: 24 (4×6), 56 (7×8), 112 (14×8). 0 = unknown.
  final int hotKeyCount;

  AclasDeviceInfo({
    required this.protocolType,
    required this.addr,
    required this.port,
    required this.pluStorage,
    required this.version,
    required this.defaultProtocol,
    this.hotKeyCount = 0,
  });
}

class AclasUploadResult {
  final bool success;
  final String message;
  final int? detectedProtocol;
  final int? detectedPort;
  final int? maxPlu;

  AclasUploadResult({
    required this.success,
    required this.message,
    this.detectedProtocol,
    this.detectedPort,
    this.maxPlu,
  });
}

class AclasPLUItem {
  final int id;
  final String itemCode;
  final int departmentId;
  final String name;
  final double price;
  final int unitId;       // 4=weight(kg), 10=count(pcs)
  final int barcodeType1;
  final int barcodeType2;
  final double tareWeight;

  AclasPLUItem({
    required this.id,
    required this.itemCode,
    required this.departmentId,
    required this.name,
    required this.price,
    this.unitId = 4,
    this.barcodeType1 = 7,
    this.barcodeType2 = 7,
    this.tareWeight = 0,
  });
}

/// Maps a physical button position on the scale keyboard to a PLU ID.
class AclasHotKeyMapping {
  /// Physical button position on the scale keyboard (1-based, 1, 2, 3, ...).
  /// This is NOT the PLU number — it's the button index on the scale's keyboard.
  /// Most Aclas scales have 24-56 physical hotkey buttons.
  final int keyNo;
  /// PLU ID to invoke when this key is pressed.
  final int pluId;
  /// Page/Mode (0 = default page, 1 = shift/second page).
  /// Most scales have a Shift or Page key to access additional hotkey layers.
  final int mode;

  AclasHotKeyMapping({
    required this.keyNo,
    required this.pluId,
    this.mode = 0,
  });

  /// Build hotkey mappings for a list of PLU IDs, auto-wrapping to additional
  /// pages (Mode) when the count exceeds the scale's physical button count.
  ///
  /// [pluIds] — PLU IDs in the order they should appear on the keyboard
  /// [buttonsPerPage] — Number of physical hotkey buttons on the scale
  ///   (from `AclasDeviceInfo.hotKeyCount`, or common defaults:
  ///    24 for small scales, 56 for mid-size, 112 for 14×8 layouts).
  ///   If 0 or null, defaults to 112 (largest common layout).
  ///
  /// Example: 150 PLUs on a 56-button scale produces:
  ///   Keys 1-56  on Mode 0 (default page) → PLUs 1-56
  ///   Keys 1-56  on Mode 1 (shift page 1) → PLUs 57-112
  ///   Keys 1-38  on Mode 2 (shift page 2) → PLUs 113-150
  static List<AclasHotKeyMapping> buildSequentialMappings(
    List<int> pluIds, {
    int? buttonsPerPage,
  }) {
    final buttons = (buttonsPerPage != null && buttonsPerPage > 0)
        ? buttonsPerPage
        : 112; // 14×8 layout is the largest common
    final result = <AclasHotKeyMapping>[];
    for (int i = 0; i < pluIds.length; i++) {
      result.add(AclasHotKeyMapping(
        keyNo: (i % buttons) + 1,  // 1-based button position within a page
        pluId: pluIds[i],
        mode: i ~/ buttons,         // Page number (0 = default, 1 = shift, ...)
      ));
    }
    return result;
  }
}

/// Department entry for the scale's department table.
/// PLU records reference DepartmentID — must be uploaded before PLU data.
class AclasDepartment {
  final int id;
  final String name;

  AclasDepartment({required this.id, required this.name});
}

/// Unit entry for the scale's unit table.
/// PLU records reference UnitID (4=kg, 10=pcs) — must be uploaded before PLU data.
class AclasUnit {
  final int id;
  final String name;

  AclasUnit({required this.id, required this.name});
}

/// Group entry for the scale's group table.
/// PLU records reference GroupID — should be uploaded before PLU data.
class AclasGroup {
  final int id;
  final String name;

  AclasGroup({required this.id, required this.name});
}
