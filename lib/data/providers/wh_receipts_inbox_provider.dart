// WH-002: gives the purchases screen the accountant's receipts inbox without
// the presentation layer importing `data/database` (presentation_db_import_guard).
//
// On a client (or mirror) desktop the phone documents are NOT in the local
// database - they live on the main - so the source is the main's desk routes;
// a local read would show «no receipts» while some wait.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api/m1_wh/wh_receipts_source.dart';
import '../database/sync_interceptor.dart';
import 'providers.dart';

final whReceiptsInboxProvider = Provider<WhReceiptsSource>((ref) =>
    SyncInterceptor.isClientMode || SyncInterceptor.isMirrorMode
        ? WhRemoteReceipts()
        : WhLocalReceipts(ref.watch(databaseProvider)));
