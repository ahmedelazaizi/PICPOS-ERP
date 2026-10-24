// ذيلُ الإنهاء المشترك لمسارات المقرّ والفرع والمرآة: اعتمادُ النمط عبر المالك
// الوحيد لـ`network_mode`، ثم `setup_completed` **آخرَ** كتابة.
//
// ⚠️ ترتيبٌ مطابقٌ لذيل `SetupFinishRunner`: النمط ← `deployment_mode` ← خطّافٌ
// (فرعُ العميل) ← الإضافات ← `setup_completed` ← `setup_in_progress` ← تدقيق ←
// إعادةُ تحميل ذاكرة الإعدادات. فشلُ اعتماد النمط يوقف التشغيلَ بلا حالةٍ جزئية.
library;

import '../../../core/i18n/tr.dart';
import '../../../core/config/runtime_config_snapshot.dart'
    show DeploymentMode, DeploymentModeX;
import '../../../services/network_service.dart';
import '../setup_wizard/setup_finish_runner.dart';

Future<SetupRunResult> runFinishTail({
  required SetupPersistence p,
  required NetworkMode mode,
  required int serverPort,
  required Map<String, dynamic> auditPayload,
  required void Function(SetupRunStage s) enter,
  List<String> warnings = const [],
  Future<void> Function()? afterCommit,
  Future<void> Function()? extras,
}) async {
  enter(SetupRunStage.mode);
  final failure = await p.commitDeploymentMode(mode, serverPort);
  if (failure != null) {
    return SetupRunResult(
      ok: false,
      failedStage: SetupRunStage.mode,
      error: failure,
      warnings: warnings,
    );
  }
  await p.saveCachedSetting(
    'deployment_mode',
    switch (mode) {
      NetworkMode.standalone => DeploymentMode.standalone,
      NetworkMode.server => DeploymentMode.server,
      NetworkMode.client => DeploymentMode.client,
      NetworkMode.mirror => DeploymentMode.mirror,
    }.key,
  );
  if (afterCommit != null) await afterCommit();
  if (extras != null) {
    enter(SetupRunStage.extras);
    await extras();
  }
  enter(SetupRunStage.finalize);
  await p.saveSetting('setup_completed', 'true');
  await p.saveSetting('setup_in_progress', '');
  await p.recordAudit('setup_completed', auditPayload);
  final out = [...warnings];
  if (!await p.rehydrateRuntimeConfigCache()) {
    out.add(tr('تعذّر تحديث ذاكرة الإعدادات المؤقتة'));
  }
  return SetupRunResult(ok: true, warnings: out);
}
