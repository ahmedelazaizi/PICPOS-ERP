// حقائقُ النظام التي تُشتقّ منها أعلامُ التحقّق عند الاستئناف (C.3).
//
// المسودّةُ لا تحمل أعلامَ تحقّق (‏لا تُسلسَل)، فمسودّةٌ معدَّلةٌ يدوياً لا تستطيع
// أن تُوهم المعالجَ بأنّ الربط أو المزامنة تمّا. الأعلامُ هنا تُقرأ من الواقع:
// قابليةُ الكتابة في مجلد البيانات، و`client_first_sync_completed`، ووجودُ
// عنوان الخادم. وتحقّقُ الحساب (`accountVerified`) لا يُشتقّ أبداً: يحتاج جلسةً.
library;

import '../../../domain/models/first_run/first_run_draft.dart';
import '../../../services/setup/first_run_storage_probe.dart';
import 'first_run_draft_store.dart';

class FirstRunFacts {
  const FirstRunFacts({
    required this.storage,
    this.setupInProgress = false,
    this.wasCommitting = false,
    this.clientFirstSyncCompleted = false,
    this.hasServerAddress = false,
  });

  final StorageProbeResult storage;

  /// `setup_in_progress=='true'` — بدأ التشغيلُ ولم يكتمل.
  final bool setupInProgress;

  /// `setup_progress_v2` يحوي `committing` — أُغلق التطبيقُ أثناء التشغيل.
  final bool wasCommitting;

  final bool clientFirstSyncCompleted;
  final bool hasServerAddress;

  /// بانر «إعداد غير مكتمل — أكمل».
  bool get incomplete => setupInProgress || wasCommitting;
}

Future<FirstRunFacts> loadFacts({
  required SettingReader read,
  required FirstRunStorageProbe probe,
  required bool wasCommitting,
}) async {
  Future<String> value(String key) async {
    try {
      return (await read(key)) ?? '';
    } catch (_) {
      return '';
    }
  }

  return FirstRunFacts(
    storage: await probe.probe(),
    setupInProgress: await value('setup_in_progress') == 'true',
    wasCommitting: wasCommitting,
    clientFirstSyncCompleted:
        await value('client_first_sync_completed') == 'true',
    hasServerAddress: (await value('network_server_address')).isNotEmpty,
  );
}

/// يضبط أعلامَ [d] من الحقائق (‏لا من المسودّة).
FirstRunDraft applyFacts(FirstRunDraft d, FirstRunFacts f) => d.copyWith(
      checks: FirstRunChecks(
        storageChecked: f.storage.writable,
        linked: f.hasServerAddress,
        firstSyncDone: f.clientFirstSyncCompleted,
      ),
    );
