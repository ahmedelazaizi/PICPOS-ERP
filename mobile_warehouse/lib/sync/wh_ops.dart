import 'package:flutter/widgets.dart';
import 'package:picpos_api_client/picpos_api_client.dart';

import '../printing/label_printer.dart';
import '../scan/camera_scan_view.dart';
import '../session/wh_session.dart';
import '../store/wh_local_store.dart';
import 'wh_outbox.dart';

typedef Scanner = Future<String?> Function(BuildContext context, {bool qr});

/// Everything the document screens share: the session (and its client), the
/// outbox, the reachability state, the printer and the camera scanner.
class WhOps {
  WhOps({
    required this.session,
    required this.store,
    required this.printer,
    this.scanner = scanWithCamera,
    WhSyncState? sync,
  }) : sync = sync ?? WhSyncState();

  final WhSession session;
  final WhLocalStore store;
  final LabelPrinter printer;
  final Scanner scanner;
  final WhSyncState sync;
  late final WhOutbox outbox = WhOutbox(store, session, sync);

  WhSessionInfo? get info => session.info;
  bool can(String code) => info?.can(code) ?? false;

  /// Runs an online call. Marks the desktop reachable / unreachable so the
  /// banner is honest; the error is re-thrown for the caller to display.
  Future<T> online<T>(Future<T> Function(WarehouseLanClient client) call) async {
    final client = session.client;
    if (client == null) throw const ApiError(kind: ApiErrorKind.network, code: 'network');
    try {
      final r = await call(client);
      sync.reachable();
      return r;
    } on ApiError catch (e) {
      if (e.kind == ApiErrorKind.network || e.kind == ApiErrorKind.unavailable) sync.unreachable();
      if (e.kind == ApiErrorKind.unauthorized) sync.unreachable(login: true);
      rethrow;
    }
  }
}
