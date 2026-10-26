// WH-002: where the accountant's receipts inbox reads from.
//
// * server / standalone: the LOCAL database ([WhLocalReceipts]) - the phones
//   post their documents to this very machine.
// * client: the phone documents live only on the MAIN, so the dialog asks the
//   main through the desk routes ([WhRemoteReceipts]); a local read would show
//   an empty list while receipts wait. The main enforces the permission, the
//   warehouse scope and the device policy (a mirror console is refused).
import '../../../data/database/database.dart';
import '../../server_proxy.dart';
import 'wh_error_classifier.dart';
import 'wh_http.dart';
import 'wh_receipts_inbox.dart';

abstract class WhReceiptsSource {
  Future<List<Map<String, Object?>>> list(int userId);
  Future<Map<String, Object?>> convert(String gid, int userId);
}

class WhLocalReceipts implements WhReceiptsSource {
  WhLocalReceipts(AppDatabase db) : _inbox = WhReceiptsInbox(db);
  final WhReceiptsInbox _inbox;

  @override
  Future<List<Map<String, Object?>>> list(int userId) => _guard(() => _inbox.list(userId));

  @override
  Future<Map<String, Object?>> convert(String gid, int userId) => _guard(() => _inbox.convert(gid, userId));

  // period_closed / accounts_not_mapped surface with their stable code.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw classifyWhFailure(e);
    }
  }
}

class WhRemoteReceipts implements WhReceiptsSource {
  WhRemoteReceipts([ServerProxy? proxy]) : _proxy = proxy ?? ServerProxy.instance;
  final ServerProxy _proxy;

  Never _refuse(int status, Map<String, dynamic> body) {
    if (status == 403 && body['error'] is String && (body['error'] as String).contains('permission')) {
      throw WhError('permission_denied', 403);
    }
    throw WhError('${body['error'] ?? 'internal'}', status);
  }

  @override
  Future<List<Map<String, Object?>>> list(int userId) async {
    final (status, body) = await _proxy.whDeskCall('GET', '/api/m1/wh/desk/receipts');
    if (status != 200) _refuse(status, body);
    return [for (final r in (body['receipts'] as List? ?? const [])) Map<String, Object?>.from(r as Map)];
  }

  @override
  Future<Map<String, Object?>> convert(String gid, int userId) async {
    // One key per receipt: a retry after a lost answer is a replay, not a
    // second invoice (the main also refuses a second convert of the document).
    final (status, body) = await _proxy.whDeskCall('POST', '/api/m1/wh/desk/receipts/$gid/convert',
        idempotencyKey: 'desk-convert-$gid');
    if (status != 200) _refuse(status, body);
    return Map<String, Object?>.from(body);
  }
}
