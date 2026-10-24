// آلةُ حالات الإعداد الأول (C.3) — انتقالاتٌ خالصة على [FirstRunDraft].
//
//   editing(step i) ──advance/valid──▶ editing(i+1) … ──▶ review
//   review ──finish──▶ committing ──ok──▶ committed ──▶ success
//   committing ──fail(stage, reason)──▶ review (failedStage، إعادةُ محاولة)
//   تغيير المسار ──▶ editing(0) مع تصفير التحقّقات (‏`selectPath`)
//
// لا قفزَ أماميّ فوق `maxStep`، و«التالي» محروسٌ بتحقّق الخطوة الحاليّة،
// و«إنهاء» في المراجعة يعيد التحقّقَ الشاملَ ويقفز إلى أوّل خطوةٍ فاشلة.
library;

import 'first_run_draft.dart';
import 'first_run_steps.dart';
import 'first_run_validation.dart';

enum FirstRunPhase { editing, committing, committed }

/// نتيجةُ محاولة انتقال: [draft] الجديدةُ، و[blocked] إن مُنع الانتقال.
class FirstRunMove {
  const FirstRunMove(this.draft, {this.blocked});

  final FirstRunDraft draft;
  final FirstRunStepIssue? blocked;

  bool get ok => blocked == null;
}

/// يتقدّم خطوةً بعد التحقّق من الحاليّة.
FirstRunMove advance(FirstRunDraft d, FirstRunSecrets s) {
  final steps = stepsFor(d.path);
  final current = steps[d.step.clamp(0, steps.length - 1)];
  final issue = validateStep(current, d, s);
  if (issue != null) return FirstRunMove(d, blocked: FirstRunStepIssue(current, issue));
  if (d.step >= steps.length - 1) return FirstRunMove(d);
  final next = d.step + 1;
  return FirstRunMove(
    d.copyWith(step: next, maxStep: next > d.maxStep ? next : d.maxStep),
  );
}

/// خطوةٌ للخلف (‏لا تحتاج تحقّقاً).
FirstRunDraft back(FirstRunDraft d) =>
    d.step > 0 ? d.copyWith(step: d.step - 1) : d;

/// قفزٌ إلى [index] — مرفوضٌ فوق `maxStep` (‏الخطواتُ غير المنجزة معطّلة).
FirstRunDraft jumpTo(FirstRunDraft d, int index) {
  final last = stepsFor(d.path).length - 1;
  if (index < 0 || index > last || index > d.maxStep) return d;
  return d.copyWith(step: index);
}

/// «إنهاء» من المراجعة: يعيد التحقّقَ من كلّ الخطوات. الفشلُ ⇒ يقفز إلى أوّل
/// خطوةٍ فاشلةٍ ويُرجع سببها؛ النجاحُ ⇒ المسودّةُ كما هي وجاهزةٌ للتشغيل.
FirstRunMove beginFinish(FirstRunDraft d, FirstRunSecrets s) {
  final failure = validateAll(d, s);
  if (failure == null) return FirstRunMove(d);
  final index = stepsFor(d.path).indexOf(failure.step);
  return FirstRunMove(d.copyWith(step: index), blocked: failure);
}
