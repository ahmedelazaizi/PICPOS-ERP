// ═══════════════════════════════════════════════════════════════════════════
// MIRROR DIVERGENCE HANDLER — Spec 131 (FR-006 raise sites)
// ═══════════════════════════════════════════════════════════════════════════
//
// Global routing point between the divergence detection sites
// (sales_transaction_orchestrator pre-flight + server-500 catch) and the
// Fatal screen. The orchestrator MUST NOT depend on `lib/presentation/...`
// (Constitution VII — layered architecture). This handler is the seam.
//
// Wire:
//   main.dart on boot:    MirrorDivergenceHandler.installRunner(fn);
//   orchestrator on miss: await MirrorDivergenceHandler.surface(...);
//
// The runner function is whatever main.dart wants — typically it calls
// `runApp(FatalSetupErrorApp(result, onMirrorRepair: _retry…))`. Tests
// stub the runner with a Completer to assert "Fatal would surface".
//
// See contracts/fatal-screen-extension.md.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

import '../deployment/reconcile_result.dart';
import '../network_service.dart' show NetworkMode;
import 'mirror_cache_divergence_exception.dart';

typedef MirrorDivergenceRunner = Future<void> Function(
    ReconcileInconsistent inconsistent);

class MirrorDivergenceHandler {
  MirrorDivergenceHandler._();

  static MirrorDivergenceRunner? _runner;

  /// Called once from `main.dart` after boot completes to register the
  /// callback that runs when a divergence event surfaces. Idempotent —
  /// repeat calls overwrite the previous runner (useful for tests).
  static void installRunner(MirrorDivergenceRunner runner) {
    _runner = runner;
  }

  /// Reset state. Tests only.
  @visibleForTesting
  static void resetForTests() {
    _runner = null;
  }

  /// Surface a Fatal screen with the new `mirrorCacheDivergence` kind.
  /// Builds the [ReconcileInconsistent] payload from the exception and
  /// dispatches it to the registered runner.
  ///
  /// If no runner is installed (e.g., during tests or on a pre-Spec-131
  /// build), the call is a no-op + debugPrint warning.
  ///
  /// [origin] is `'pre-flight'` or `'server-500'` per
  /// contracts/diagnostic-breadcrumbs.md.
  static Future<void> surface({
    required MirrorCacheDivergenceException exception,
    required String origin,
  }) async {
    final runner = _runner;
    if (runner == null) {
      debugPrint('[MIRROR-DIVERGENCE-HANDLER] No runner installed — '
          'Fatal screen suppressed (kind=${exception.kind.breadcrumbName} '
          'requested=${exception.requestedId} origin=$origin). '
          'Install via MirrorDivergenceHandler.installRunner() in main.dart.');
      return;
    }

    final inconsistent = ReconcileInconsistent(
      reasonAr: 'تعارض فى بيانات المرآة: لم يتم العثور على '
          '${exception.kind.arabicName} برقم ${exception.requestedId}. '
          'اضغط "إعادة المزامنة مع السيرفر" لاستعادة التوافق.',
      reasonCode: ReconcileReasonCode.mirrorCacheDivergence,
      dbMode: NetworkMode.mirror,
      kind: ReconcileFatalKind.mirrorCacheDivergence,
      details: [
        'kind=${exception.kind.breadcrumbName}',
        'requested_id=${exception.requestedId}',
        'cached_ids=${exception.cachedIds.join(",")}',
        if (exception.serverResponse != null)
          'server_response=${exception.serverResponse}',
        if (exception.localFkError != null)
          'local_fk_error=${exception.localFkError}',
        'origin=$origin',
      ],
    );

    await runner(inconsistent);
  }
}
