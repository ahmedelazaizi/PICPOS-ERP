part of 'lan_pairing_service.dart';

/// Warehouse-device pairing (plan 2026-10-23): kind binding, branch from the
/// offer, device lookup for the route policy, permission-checked listing.
extension LanPairingWarehouse on LanPairingService {
  /// A code issued for warehouse pairs only a warehouse device, and a
  /// warehouse device can only use such a code.
  bool _kindAllowed(_PairingOffer offer, LanPairingRequest request) =>
      (offer.deviceKind == 'warehouse') == (request.deviceKind == 'warehouse');

  /// The branch comes from the issued offer, never from the device.
  Future<LanPairingResult> _pairWarehouseDevice(LanPairingRequest request) async {
    final branchId = _pendingOffer?.branchId;
    if (branchId == null) return const LanPairingResult.branchRequired();
    final branch = await _posBranch(branchId);
    if (branch.failure == LanPairingStatus.branchUnavailable) {
      return const LanPairingResult.branchUnavailable();
    }
    final deviceId = request.deviceId.trim();
    final pairedAt = DateTime.fromMillisecondsSinceEpoch(_now().millisecondsSinceEpoch);
    await _upsertDevice(_PairingDevice(
      deviceId: deviceId,
      name: request.deviceName.trim().isEmpty ? 'PicPos Warehouse' : request.deviceName.trim(),
      pairedAt: pairedAt,
      lastSeenAt: pairedAt,
      ip: request.ip,
      revoked: false,
      legacySeen: false,
      deviceKind: 'warehouse',
      branchId: branchId,
    ));
    return LanPairingResult.warehouseSuccess(token: tokenForDevice(deviceId), deviceId: deviceId, branchId: branchId);
  }

  /// [listDevices] for a UI actor: requires devices_pair_manage too.
  Future<List<LanPairingDevice>> listDevicesFor(int? actorUserId) async {
    await _authz.require(actorUserId, action: 'list');
    return listDevices();
  }

  /// True when [token] is the genuine token of a device that was revoked, so the
  /// middleware can answer 401 device_revoked (the phone then wipes itself)
  /// instead of an anonymous 403.
  Future<bool> isRevokedDeviceToken({required String token, required String deviceId}) async {
    if (!_initialized || deviceId.trim().isEmpty) return false;
    if (!LanPairingService._constantTimeEquals(tokenForDevice(deviceId.trim()), token)) return false;
    return (await _findDevice(deviceId.trim()))?.revoked == true;
  }

  /// The paired device row (kind + branch), for the route policy middleware.
  Future<LanPairingDevice?> deviceById(String deviceId) async =>
      (await _findDevice(deviceId.trim()))?.toPublic();
}
