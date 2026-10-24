part of 'lan_pairing_service.dart';

// Pairing data models, moved out of lan_pairing_service.dart (file-size ceiling).

class _PairingWork {
  const _PairingWork({
    required this.request,
    required this.deviceId,
    required this.pairedAt,
    required this.token,
  });

  final LanPairingRequest request;
  final String deviceId;
  final int pairedAt;
  final String token;

  String get deviceName => request.deviceName.trim().isEmpty
      ? 'جهاز LAN'
      : request.deviceName.trim();
}

class PairingOffer {
  const PairingOffer({
    required this.code,
    required this.expiresAt,
    required this.qrPayload,
  });
  final String code;
  final DateTime expiresAt;
  final String qrPayload;
}

class LanPairingRequest {
  const LanPairingRequest({
    required this.code,
    required this.deviceId,
    required this.deviceName,
    required this.ip,
    this.deviceKind,
    this.branchId,
  });

  final String code;
  final String deviceId;
  final String deviceName;
  final String ip;
  final String? deviceKind;
  final int? branchId;
}

class _TerminalAllocation {
  const _TerminalAllocation({
    required this.branchId,
    required this.deviceId,
    required this.assignedAt,
    required this.terminalCode,
  });

  final int branchId;
  final String deviceId;
  final int assignedAt;
  final String terminalCode;
}

class _PosDeviceRecord {
  const _PosDeviceRecord({
    required this.deviceId,
    required this.deviceName,
    required this.ip,
    required this.branchId,
    required this.pairedAt,
    required this.terminalCode,
  });

  final String deviceId;
  final String deviceName;
  final String ip;
  final int branchId;
  final int pairedAt;
  final String terminalCode;
}

class LanPairingResult {
  const LanPairingResult._({
    required this.status,
    this.token,
    this.deviceId,
    this.branchId,
    this.branchCode,
    this.terminalCode,
    this.deviceKind,
  });

  const LanPairingResult.success({
    required String token,
    required String deviceId,
  }) : this._(
         status: LanPairingStatus.success,
         token: token,
         deviceId: deviceId,
       );
  const LanPairingResult.posSuccess({
    required String token,
    required String deviceId,
    required int branchId,
    required String branchCode,
    required String terminalCode,
  }) : this._(
         status: LanPairingStatus.success,
         token: token,
         deviceId: deviceId,
         branchId: branchId,
         branchCode: branchCode,
         terminalCode: terminalCode,
       );
  const LanPairingResult.warehouseSuccess({
    required String token,
    required String deviceId,
    required int branchId,
  }) : this._(
         status: LanPairingStatus.success,
         token: token,
         deviceId: deviceId,
         branchId: branchId,
       );
  const LanPairingResult.boundSuccess({
    required String token,
    required String deviceId,
    required int branchId,
    String? branchCode,
  }) : this._(
         status: LanPairingStatus.success,
         token: token,
         deviceId: deviceId,
         branchId: branchId,
         branchCode: branchCode,
       );
  const LanPairingResult.kindMismatch()
    : this._(status: LanPairingStatus.kindMismatch);
  const LanPairingResult.invalidCode()
    : this._(status: LanPairingStatus.invalidCode);
  const LanPairingResult.rateLimited()
    : this._(status: LanPairingStatus.rateLimited);
  const LanPairingResult.invalidDevice()
    : this._(status: LanPairingStatus.invalidDevice);
  const LanPairingResult.branchRequired()
    : this._(status: LanPairingStatus.branchRequired);
  const LanPairingResult.branchUnavailable()
    : this._(status: LanPairingStatus.branchUnavailable);
  const LanPairingResult.branchCodeUnavailable()
    : this._(status: LanPairingStatus.branchCodeUnavailable);

  final LanPairingStatus status;
  final String? token;
  final String? deviceId;
  final int? branchId;
  final String? branchCode;
  final String? terminalCode;

  /// The kind the device was paired as (from the code, or the request).
  final String? deviceKind;

  /// Success carrying the effective kind; failures pass through unchanged.
  LanPairingResult withKind(String? kind) => status != LanPairingStatus.success
      ? this
      : LanPairingResult._(
          status: status,
          token: token,
          deviceId: deviceId,
          branchId: branchId,
          branchCode: branchCode,
          terminalCode: terminalCode,
          deviceKind: kind,
        );
}

enum LanPairingStatus {
  success,
  invalidCode,
  rateLimited,
  invalidDevice,
  branchRequired,
  branchUnavailable,
  branchCodeUnavailable,
  kindMismatch,
}

class LanPairingDevice {
  const LanPairingDevice({
    required this.deviceId,
    required this.name,
    required this.pairedAt,
    required this.lastSeenAt,
    required this.ip,
    required this.revoked,
    required this.legacySeen,
    this.deviceKind,
    this.branchId,
    this.terminalCode,
  });

  final String deviceId;
  final String name;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;
  final String? ip;
  final bool revoked;
  final bool legacySeen;
  final String? deviceKind;
  final int? branchId;
  final String? terminalCode;

  bool get isPaired => pairedAt != null;
}

class _PairingOffer {
  const _PairingOffer({
    required this.code,
    required this.expiresAt,
    required this.payload,
    this.deviceKind,
    this.branchId,
  });
  final String? deviceKind;
  final int? branchId;
  final String code;
  final DateTime expiresAt;
  final String payload;
}

class _PairingDevice {
  _PairingDevice({
    required this.deviceId,
    required this.name,
    required this.pairedAt,
    required this.lastSeenAt,
    required this.ip,
    required this.revoked,
    required this.legacySeen,
    this.deviceKind,
    this.branchId,
    this.terminalCode,
  });

  final String deviceId;
  final String name;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;
  final String? ip;
  bool revoked;
  final bool legacySeen;
  final String? deviceKind;
  final int? branchId;
  final String? terminalCode;

  LanPairingDevice toPublic() => LanPairingDevice(
    deviceId: deviceId,
    name: name,
    pairedAt: pairedAt,
    lastSeenAt: lastSeenAt,
    ip: ip,
    revoked: revoked,
    legacySeen: legacySeen,
    deviceKind: deviceKind,
    branchId: branchId,
    terminalCode: terminalCode,
  );
}
