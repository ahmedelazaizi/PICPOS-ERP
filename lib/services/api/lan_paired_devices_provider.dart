import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/providers.dart';
import '../network_service.dart';
import 'lan_pairing_service.dart';

/// Settings › Linked devices — the LAN pairing registry (`lan_paired_devices`)
/// for listing and revoking paired cashier/branch devices.
///
/// Uses the running server's service when there is one; otherwise a
/// DB-backed instance — `listDevices`/`revoke` only touch the table (bound
/// parameters) and never the install secret, so the registry stays readable
/// and revocable while the LAN server is stopped.
final lanPairedDevicesServiceProvider = Provider<LanPairingService>((ref) =>
    NetworkService.instance.lanPairingService ??
    LanPairingService(ref.read(databaseProvider)));
