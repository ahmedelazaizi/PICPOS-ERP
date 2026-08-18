// ═══════════════════════════════════════════════════════════════════════════
// «لا ورديّةَ مفتوحة» ⇒ اعرض فتحَها ثمّ أعد المحاولةَ مرّةً — لا رفضٌ جافّ
// ═══════════════════════════════════════════════════════════════════════════
//
// المواصفة: docs/superpowers/specs/2026-08-18-sales-return-cash-shift-rule-design.md (ح‑١)
//
// المستودعُ يرفض المرتجعَ النقديَّ بلا ورديّةٍ مفتوحة برميِ
// [ShiftRequiredException]. والرفضُ وحدَه قاسٍ على الكاشير: ما يريده أن يفتح
// ورديّةً، لا أن يُخبَر أنّه لا يستطيع.
//
// فهذا المساعدُ يترجم الرفضَ إلى إجراء — بنفسِ ديالوجِ الرصيد الافتتاحيّ الذي
// تعرضه شاشةُ نقطة البيع في `_ensureShiftOpen`، فيرى الكاشيرُ ما اعتاده.
//
// ولماذا هنا لا في كلّ شاشة: شاشتا المرتجع توأمان (‏`screens/sales_returns`
// و`sales_returns_picpos`)، ونسخُ المنطقِ بينهما هو «مصيدةُ النسخ §٥.٥» التي
// أوقعت الفورك مراراً — آخرُها أنّ PicPos POS فقدَ `_ensureShiftOpen` كلَّها.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exceptions.dart';
import '../../data/providers/repository_providers.dart';
import '../../services/client_write_interceptor.dart';
import '../../data/providers/auth_providers.dart';
import '../../data/providers/branch_scope_provider.dart';
import '../pos/widgets/pos_opening_balance_dialog.dart';

/// نتيجةُ محاولةِ المرتجع بعد معالجةِ «لا ورديّة».
enum ShiftPromptOutcome {
  /// مضى المرتجعُ (إمّا من أوّل محاولةٍ أو بعد فتحِ ورديّة).
  completed,

  /// رفض الكاشيرُ فتحَ ورديّة — لم يقع شيءٌ إطلاقاً.
  cancelledByUser,

  /// تعذّر فتحُ الورديّة (حساباتٌ غيرُ مربوطة، فرعٌ ناقص…).
  shiftOpenFailed,
}

/// ينفّذ [attempt]، فإن رُفض لغياب ورديّةٍ عرض فتحَها وأعاد المحاولةَ **مرّةً**.
///
/// المحاولةُ الثانيةُ واحدةٌ لا حلقة: لو رُفضت ثانيةً فالسببُ ليس الورديّةَ
/// (سباقٌ أو إخفاقُ فتحٍ صامت)، وإعادةُ العرضِ حينها تُدوِّر الكاشيرَ في ديالوجٍ
/// لا ينتهي — وهي العلّةُ التي عالجها حارسُ `shiftDialogPromptedUserIds` في
/// نقطة البيع (Feature 012 / Issue C-SHIFT-LOOP).
///
/// [attempt] يجب أن يكون **ذرّيّاً**: الحارسُ في المستودع يرمي قبل فتحِ
/// المعاملة، فلا أثرَ جزئيّاً يبقى قبل إعادة المحاولة.
Future<ShiftPromptOutcome> runWithOpenShiftPrompt({
  required BuildContext context,
  required WidgetRef ref,
  required Future<void> Function() attempt,
  /// نصٌّ يشرح للكاشير لماذا يُسأل الآن — يختلف بين بيعةٍ ومرتجع.
  String Function(double cashAmount)? subtitleBuilder,
}) async {
  try {
    await attempt();
    return ShiftPromptOutcome.completed;
  } on ShiftRequiredException catch (e) {
    if (!context.mounted) return ShiftPromptOutcome.cancelledByUser;

    final authState = ref.read(authProvider);
    final userId = authState.user?.id;
    if (userId == null) return ShiftPromptOutcome.shiftOpenFailed;

    final opening = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PosOpeningBalanceDialog(
        userName: authState.user?.displayName ?? 'كاشير',
        // المبلغُ يُعرَض ليعرف الكاشيرُ لماذا يُسأل الآن تحديداً.
        subtitle: subtitleBuilder?.call(e.cashAmount) ??
            'العملية تحرّك ${e.cashAmount.toStringAsFixed(2)} نقداً في الدرج.',
      ),
    );

    // الإلغاء = لا مرتجع. ولا شيءَ يحتاج تراجعاً: الحارسُ رمى قبل أن يُكتَب حرف.
    if (opening == null) return ShiftPromptOutcome.cancelledByUser;

    try {
      final treasuryRepo = ref.read(treasuryRepositoryProvider);
      int? branchId;
      try {
        final scope = await ref.read(branchScopeProvider.future);
        branchId = scope.primaryBranchId;
      } catch (_) {
        // غيرُ قاتل: ورديّةٌ بلا فرعٍ تنزل لفرعِ المخزن في مُحلِّل الخزنة.
      }

      await treasuryRepo.openShift(userId, opening, branchId: branchId);

      // مرآةُ الخادم — غيرُ قاتلة: تُصَفّ في الـoutbox عند الإخفاق، تماماً
      // كما يفعل `_ensureShiftOpen`.
      try {
        final shift = await treasuryRepo.getCurrentOpenShift(userId);
        await ClientWriteInterceptor.openShift(
          userId,
          opening,
          localShiftId: shift?.id,
          branchId: branchId,
          globalId: shift?.globalId,
        );
      } catch (_) {}
    } catch (_) {
      return ShiftPromptOutcome.shiftOpenFailed;
    }

    // المحاولةُ الثانيةُ والأخيرة. ورفضٌ ثانٍ لا يُرمى للشاشة: الشاشتان
    // تلفّان النداءَ بـ`finally` بلا `catch`، فاستثناءٌ منتشرٌ هنا يصير خطأً
    // طليقاً في الواجهة بدل رسالةٍ مفهومة. السببُ حينها ليس الورديّةَ أصلاً
    // (سباقٌ، أو فتحٌ أخفق صامتاً) فيُعامَل معاملةَ «تعذّر الفتح».
    try {
      await attempt();
      return ShiftPromptOutcome.completed;
    } on ShiftRequiredException {
      return ShiftPromptOutcome.shiftOpenFailed;
    }
  }
}
