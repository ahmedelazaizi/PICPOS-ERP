import 'dart:async';

import '../../core/logging/diagnostic_logger.dart';
import 'provisioning_applier.dart' show describeFailureForLog;

/// تشخيصُ فشلِ قراءة `network_mode` من قاعدة البيانات داخل المصالحة.
/// تشخيصٌ فقط: لا يغيّر النتيجةَ التي تُرجعها `reconcileWithDb`.
void logReconcileDbReadFailure(Object e, StackTrace st) {
  unawaited(DiagnosticLogger.log(
    'RECONCILE-FAIL',
    'DB_READ_ERROR: key=network_mode; ${describeFailureForLog(e, st)}',
  ));
}
