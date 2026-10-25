// WH-002: gives the purchases screen the accountant's receipts inbox without
// the presentation layer importing `data/database` (presentation_db_import_guard).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api/m1_wh/wh_receipts_inbox.dart';
import 'providers.dart';

final whReceiptsInboxProvider = Provider<WhReceiptsInbox>((ref) => WhReceiptsInbox(ref.watch(databaseProvider)));
