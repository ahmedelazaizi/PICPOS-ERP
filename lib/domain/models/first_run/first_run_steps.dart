// خطواتُ الإعداد الأول لكلّ مسار — ستٌّ بالضبط (قرارُ المالك 2026-10-23).
//
// ⚠️ لا خطوةَ تفعيلٍ ولا ترخيص: التفعيلُ في الإعدادات › حول، ولا يُكرَّر هنا.
// وفي الفرع تأتي «المزامنةُ الأولى» قبل «حساب الفرع» (‏C.2: التحقّقُ الحقيقيّ
// من الحساب يحتاج البياناتِ المزامَنة).
library;

import 'first_run_path.dart';

enum FirstRunStep {
  mode,
  company,
  link,
  storage,
  users,
  firstSync,
  prep,
  account,
  review,

  /// صفحةُ النجاح — ليست من المسار (‏لا تُعدّ في «من ٦»).
  success,
}

/// خطواتُ [path] بترتيبها، بلا صفحة النجاح.
List<FirstRunStep> stepsFor(FirstRunPath path) => switch (path) {
      FirstRunPath.standalone || FirstRunPath.hq => const [
          FirstRunStep.mode,
          FirstRunStep.company,
          FirstRunStep.storage,
          FirstRunStep.users,
          FirstRunStep.prep,
          FirstRunStep.review,
        ],
      FirstRunPath.mirror => const [
          FirstRunStep.mode,
          FirstRunStep.link,
          FirstRunStep.review,
        ],
      FirstRunPath.branch => const [
          FirstRunStep.mode,
          FirstRunStep.link,
          FirstRunStep.storage,
          FirstRunStep.firstSync,
          FirstRunStep.account,
          FirstRunStep.review,
        ],
    };
