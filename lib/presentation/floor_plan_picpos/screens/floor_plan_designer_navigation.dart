// الرجوعُ من «مصمم القاعة» وحارسُ التغييرات غير المحفوظة (خطة A.5).
//
// ═══ لماذا ملفٌّ مستقلّ ═══
//
// `floor_plan_designer_picpos_screen.dart` على سقف `file_size_ratchet` — لا
// يجوز أن يكبر. فكلُّ ما يخصّ المغادرة هنا، وتبقى الشاشةُ تستدعيه بسطرَين.
//
// ═══ لماذا لا `Navigator.pop` وحدَه ═══
//
// المصمّمُ تابٌ في شِلّ التطبيق (`IndexedStack`) لا راوتٌ مدفوع، فـ
// `Navigator.canPop` خاطئةٌ فيه وترويسةُ `PicPosPageHeader` لا ترسم سهمَ
// الرجوع من تلقاء نفسها. فنمرّر `onBack` صريحاً: إن كان ثمّة راوتٌ نرجع به،
// وإلّا نطلب فتحَ شاشة «الطاولات» عبر قناة التنقّل.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/navigation/screen_id.dart';
import '../../../data/providers/screen_navigation_provider.dart';

/// حوارُ «تغييراتٌ لم تُحفَظ». يرجع `true` إن اختار المستخدمُ المغادرةَ.
///
/// [leavingDesigner] يبدّل نصَّ الشرح: مغادرةُ **المصمّم** كلِّه لا مغادرةُ
/// القسم الحاليّ.
Future<bool> showFloorPlanDiscardDialog(
  BuildContext context, {
  bool leavingDesigner = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(tr('تغييراتٌ لم تُحفَظ')),
        content: Text(
          leavingDesigner
              ? tr('مغادرةُ المصمّم الآن تُسقط ما رسمتَه ولم تحفظه. أتريد المتابعة؟')
              : tr('مغادرةُ هذا القسم الآن تُسقط ما رسمتَه فيه. أتريد المتابعة؟'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('ابقَ')),
          ),
          TextButton(
            key: const Key('floor_plan_discard_ok'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('غادِر واترك التغييرات')),
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}

/// زرُّ الرجوع في ترويسة المصمّم: يسأل إن كان المخطَّطُ متّسخاً، ثم يرجع إلى
/// شاشة «الطاولات».
///
/// [discardDraft] يُسقط المسوّدةَ ويعيد تحميلَ المحفوظ — التابُ يبقى حيّاً بعد
/// المغادرة، فبلا هذا يعود المستخدمُ فيجد المسوّدةَ «متّسخةً» ولا يدري.
Future<void> leaveFloorPlanDesigner(
  BuildContext context,
  WidgetRef ref, {
  required bool dirty,
  required Future<void> Function() discardDraft,
}) async {
  if (dirty) {
    final leave = await showFloorPlanDiscardDialog(
      context,
      leavingDesigner: true,
    );
    if (!leave) return;
    await discardDraft();
  }
  if (!context.mounted) return;
  if (Navigator.canPop(context)) {
    Navigator.pop(context);
    return;
  }
  ref
      .read(screenNavigationProvider.notifier)
      .open(ScreenId.tables.navigationIndex);
}

/// يحرس مغادرةَ المصمّم بالرجوع (زرُّ النظام/Esc/`maybePop`) حين يكون متّسخاً.
class FloorPlanLeaveGuard extends ConsumerWidget {
  const FloorPlanLeaveGuard({
    super.key,
    required this.dirty,
    required this.discardDraft,
    required this.child,
  });

  final bool dirty;
  final Future<void> Function() discardDraft;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // نفسُ مسار زرّ الرجوع: يسأل ثم يرجع بـ`pop` إن وُجد راوتٌ يُدفَع، وإلّا
        // يفتح «الطاولات» — `Navigator.pop` المجرّدةُ كانت تُسقط راوتَ الشِّلّ
        // نفسَه فتترك شاشةً سوداء (E-2).
        await leaveFloorPlanDesigner(
          context,
          ref,
          dirty: dirty,
          discardDraft: discardDraft,
        );
      },
      child: child,
    );
  }
}
