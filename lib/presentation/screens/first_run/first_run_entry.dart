// نقطةُ دخول الإعداد الأول لبوّابة الإقلاع (`_SetupGate` في main.dart).
//
// • `setup_completed == 'true'` ⇒ الشاشةُ الرئيسيّة كما كانت — التثبيتاتُ
//   المكتملةُ لا ترى المعالجَ الجديدَ إطلاقاً.
// • غير ذلك (‏فارغ/غائب/نصٌّ آخر) ⇒ المعالجُ الجديد.
//
// القرارُ في دالّةٍ عامّةٍ ليُقاس بلا تركيب `main.dart`.
import 'package:flutter/widgets.dart';

import 'first_run_setup_screen.dart';

/// المعالجُ الجديد — مفتاحٌ انتقاليٌّ يُحذف مع القديم في P8.
Widget buildFirstRunEntry() => const FirstRunSetupScreen();

/// ما تعرضه البوّابةُ بعد قراءة `setup_completed`.
Widget resolveSetupGateChild({
  required String? setupCompleted,
  required Widget Function() completed,
}) =>
    setupCompleted == 'true' ? completed() : buildFirstRunEntry();
