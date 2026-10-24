part of 'lan_pairing_service.dart';

/// Kind / branch binding of pairing codes (plan 2026-10-24, P1 + M1).
///
/// A code is issued for ONE device kind (and, for branch devices, ONE branch).
/// The device does not choose either: at claim the kind and the branch come
/// from the code, and a request that names a different kind is refused.
///
/// | kind        | branch in the code | notes                                   |
/// |-------------|--------------------|-----------------------------------------|
/// | `client`    | required           | branch device (accountant, store, ...)  |
/// | `pos`       | optional           | no branch in the code = legacy (the     |
/// |             |                    | device names it); with one it is bound  |
/// | `mirror`    | forbidden          | branch-manager console; not branch-bound|
/// | `warehouse` | required (+ TLS)   | PicPos Warehouse phone                  |
/// | `admin`     | optional           |                                         |
/// | (none)      | optional           | legacy generic code: `admin` / `pos`    |
extension LanPairingKinds on LanPairingService {
  /// Rejects a code whose kind / branch / transport combination is invalid.
  void _validateOfferShape(String? kind, int? branchId, String? fingerprint) {
    if (kind != null && !kPairableDeviceKinds.contains(kind)) {
      throw ArgumentError.value(kind, 'deviceKind', 'unsupported');
    }
    final needsBranch = kind == 'warehouse' || kind == 'client';
    if ((needsBranch && branchId == null) || (branchId != null && branchId <= 0)) {
      throw ArgumentError.value(branchId, 'branchId', 'required for $kind');
    }
    if (kind == 'mirror' && branchId != null) {
      throw ArgumentError.value(branchId, 'branchId', 'a mirror is not branch-bound');
    }
    if (kind == 'warehouse' && (fingerprint ?? '').isEmpty) {
      throw StateError('tls_required_for_warehouse');
    }
  }

  /// Whether a request may claim [offer]. A code with a kind admits only that
  /// kind (`warehouse` also demands the device to say so); a code without a
  /// kind keeps the legacy behaviour (`admin` / `pos` / unspecified only).
  bool _kindAllowed(_PairingOffer offer, LanPairingRequest request) {
    final bound = offer.deviceKind;
    final asked = request.deviceKind;
    if (bound == null) return asked == null || asked == 'admin' || asked == 'pos';
    if (bound == 'warehouse') return asked == 'warehouse';
    return asked == null || asked == bound;
  }

  /// The request as it is acted on: kind and branch come from the code.
  LanPairingRequest _bindRequest(_PairingOffer offer, LanPairingRequest request) {
    final kind = offer.deviceKind ?? request.deviceKind;
    return LanPairingRequest(
      code: request.code,
      deviceId: request.deviceId,
      deviceName: request.deviceName,
      ip: request.ip,
      deviceKind: kind,
      branchId: kind == 'mirror' ? null : offer.branchId ?? request.branchId,
    );
  }

  Future<LanPairingResult> _pairClientDevice(_PairingWork work) async {
    final branchId = work.request.branchId;
    if (branchId == null || branchId <= 0) {
      return const LanPairingResult.branchRequired();
    }
    final branch = await _posBranch(branchId);
    if (branch.failure == LanPairingStatus.branchUnavailable) {
      return const LanPairingResult.branchUnavailable();
    }
    await _upsertDevice(_boundDevice(work, 'client', branchId));
    return LanPairingResult.boundSuccess(
      token: work.token,
      deviceId: work.deviceId,
      branchId: branchId,
      branchCode: branch.code,
    );
  }

  Future<LanPairingResult> _pairMirrorDevice(_PairingWork work) async {
    await _upsertDevice(_boundDevice(work, 'mirror', null));
    return LanPairingResult.success(token: work.token, deviceId: work.deviceId);
  }

  _PairingDevice _boundDevice(_PairingWork work, String kind, int? branchId) {
    final at = DateTime.fromMillisecondsSinceEpoch(work.pairedAt);
    return _PairingDevice(
      deviceId: work.deviceId,
      name: work.deviceName,
      pairedAt: at,
      lastSeenAt: at,
      ip: work.request.ip,
      revoked: false,
      legacySeen: false,
      deviceKind: kind,
      branchId: branchId,
    );
  }
}
