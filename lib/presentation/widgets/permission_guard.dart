import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/permissions/permission_codes.dart';
import '../../data/providers/providers.dart';
import '../../services/manager_approval_cache.dart';

/// النص اللي بيتعرض بدل المبلغ لما صلاحية العرض ناقصة.
const String kMaskedValuePlaceholder = '••••';

/// مبلغ محجوب بصلاحية عرض — بيوري القيمة لصاحب الصلاحية و[kMaskedValuePlaceholder]
/// لغيره، بنفس شكل النص عشان الجدول ما يترصّش.
///
/// ── ليه ودجت مستقلة مش `PermissionBuilder` ────────────────────────────────
/// `PermissionBuilder` بيعمل `contains(permission)` نضيف — **من غير تجاوز
/// مدير النظام**، عكس `PermissionGuard._checkPermission`. سجل سبب٠٨٦ بيوثّق
/// حالة إنتاج حقيقية اتفشل فيها منح كود لمدير النظام بصمت، فاستعمال
/// `PermissionBuilder` هنا كان معناه إخفاء مبالغ عن مدير النظام. الودجت دي
/// بتلفّ `PermissionGuard` عشان تاخد نفس منطق التجاوز بالظبط.
class PermissionMaskedText extends StatelessWidget {
  const PermissionMaskedText({
    super.key,
    required this.permission,
    required this.text,
    this.style,
  });

  final String permission;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return PermissionGuard(
      permission: permission,
      fallback: Text(
        kMaskedValuePlaceholder,
        style: (style ?? const TextStyle()).copyWith(
          color: AppColors.textMuted,
        ),
      ),
      child: Text(text, style: style),
    );
  }
}

/// A widget that conditionally shows/hides or enables/disables its child
/// based on user permissions.
///
/// When [allowManagerOverride] is true, the widget is always shown but
/// actions require manager password verification if the user lacks permission.
///
/// Usage:
/// ```dart
/// PermissionGuard(
///   permission: PermissionCodes.posExpense,
///   allowManagerOverride: true, // Show button, ask for manager password
///   actionName: 'إضافة مصروف',
///   child: ElevatedButton(
///     onPressed: () => _showExpenseDialog(),
///     child: Text('مصروف'),
///   ),
/// )
/// ```
class PermissionGuard extends ConsumerWidget {
  /// The permission code required to show this widget
  final String permission;

  /// The child widget to show if permission is granted
  final Widget child;

  /// Widget to show when permission is denied (defaults to empty).
  ///
  /// ── مع [allowManagerOverride] ─────────────────────────────────────────
  /// البديل هو اللي بيتعرض **قبل** موافقة المدير، والموافقة بتكشف [child].
  ///
  /// قبل الإصلاح ده كان `allowManagerOverride` بيتخطّى `fallback` تماماً
  /// ويعرض [child] الحقيقي تحت `AbsorbPointer` — يعني كارت بيقول
  /// `fallback: card(value: '---')` كان بيعرض **الرقم الحقيقي** لمين مالوش
  /// الصلاحية ويمنع الضغطة بس. الأربع مواقع اللي كانت بتبعت الاتنين كلها
  /// كروت لوحة التحكم في البراندين (`treasury_balance_view` و
  /// `dashboard_profit`) — يعني صلاحيتَي عرض ماليّتين مكانوش بيخبّوا حاجة
  /// أصلاً رغم إنهم متسجّلين «منفَّذين».
  final Widget? fallback;

  /// If true, shows the child but disabled instead of hiding it
  final bool showDisabled;

  /// Multiple permissions - user must have ALL of them
  final List<String>? allOf;

  /// Multiple permissions - user must have ANY of them
  final List<String>? anyOf;

  /// If true, allows manager override - shows the button but requires
  /// manager password when clicked if user doesn't have permission
  final bool allowManagerOverride;

  /// Human-readable name of the action (shown in override dialog)
  final String? actionName;

  /// What to run once a manager approves. **Prefer this** over letting the
  /// guard dig the callback out of [child].
  ///
  /// ── ليه موجود ────────────────────────────────────────────────────────────
  /// لما `allowManagerOverride` شغّال والمستخدم مالوش الصلاحية، الحارس بيلفّ
  /// الابن في `AbsorbPointer` ويمسك الضغطة بنفسه — فبعد موافقة المدير لازم
  /// يعرف يعمل إيه. الطريقة الوحيدة اللي كانت موجودة هي **تخمين** نوع الودجت
  /// (`_extractOnPressed`) وسحب `onPressed`/`onTap` منه، وهي بتفشل بصمت لأي
  /// نوع مش مكتوب في القائمة.
  ///
  /// تمريره هنا بيلغي التخمين تماماً: الفعل بيتقال صراحة، فما يقدرش يضيع.
  final VoidCallback? onGranted;

  // ── ⚠️ `allowManagerOverride` يبقى افتراضُه `false` — مقيسٌ لا مفترَض ─────
  //
  // قرارُ المالك (2026-08-12، اختيار «أ») **حوارُ كلمة مرور المسؤول على كلّ
  // رفض**، فبدا قلبُ هذا الافتراض إلى `true` علاجاً واحداً لـ٥٥ موضعاً ترفض
  // صامتةً (‏١٣٩ من ١٩٤ تفعّله صراحةً — أي أن الصوابَ يُكتب يدوياً كلَّ مرّة).
  //
  // **جُرّب فأسقط عشرةَ اختبارات، وأخطرُها تسريبُ بيانات:**
  //
  //     Expected: no matching candidates
  //     Actual:   Found 1 widget with text "12,345.00"
  //
  // والسبب أن الحارسَ يلفّ **نوعين** مختلفين: أفعالاً (زرٌّ يُضغط) وعرضاً
  // (مبلغٌ يُقرأ). و«حوارُ موافقةٍ» على فعلٍ صوابٌ، وعلى **قيمةٍ معروضة**
  // يعني إظهارَها لمن لا يملكها — والحوارُ لا يمنع القراءة، الشاشةُ تعرضه
  // فوق قيمةٍ صارت مرئيّة.
  //
  // وثمّة اختباراتٌ قائمةٌ تثبّت الإخفاءَ نصّاً («بدون الصلاحية: الزرار مختفي
  // تماماً» · «الحارس مربوط بالكود الصح، بلا allowManagerOverride») — قراراتٌ
  // صريحةٌ سابقة، لا نسيان.
  //
  // فاختيارُ «أ» يُنفَّذ **في مواضع الأفعال واحداً واحداً** كما في دفعات
  // صلاحيات PicPos، لا بقلب افتراضٍ يشمل العرضَ معها. ومن أراد قلبَه لاحقاً
  // فعليه أوّلاً أن يفصل حارسَ العرض عن حارس الفعل — وهو تغييرٌ في التصميم لا
  // في قيمةٍ افتراضية.

  const PermissionGuard({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
    this.showDisabled = false,
    this.allOf,
    this.anyOf,
    this.allowManagerOverride = false,
    this.actionName,
    this.onGranted,
  });

  /// Constructor for requiring ALL of multiple permissions
  const PermissionGuard.allOf({
    super.key,
    required this.allOf,
    required this.child,
    this.fallback,
    this.showDisabled = false,
    this.allowManagerOverride = false,
    this.actionName,
    this.onGranted,
  }) : permission = '',
       anyOf = null;

  /// Constructor for requiring ANY of multiple permissions
  const PermissionGuard.anyOf({
    super.key,
    required this.anyOf,
    required this.child,
    this.fallback,
    this.showDisabled = false,
    this.allowManagerOverride = false,
    this.actionName,
    this.onGranted,
  }) : permission = '',
       allOf = null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);

    // Always prefer cached data to prevent child unmount/remount flicker.
    // This is critical for POS where PermissionGuard wraps ProductGrid —
    // returning SizedBox.shrink during loading destroys the entire grid tree.
    //
    // ── ⚠️ `.value` لا `asData?.value` — سلبٌ أمنيٌّ مقيس (2026-08-13) ───────
    // `asData` يرجع `null` في **كلّ** إعادة تحميلٍ لا في الأولى وحدَها: أثناء
    // التحديث تكون الحالةُ `AsyncLoading` وإن احتفظت بقيمتها السابقة، و
    // `asData` لا يطابق إلا `AsyncData`. و`.value` يُبقي القيمةَ السابقة عبر
    // `copyWithPrevious` — نفسُ الملاحظة المكتوبة في
    // `products/widgets/product_search_header.dart:113`.
    //
    // والفرقُ ليس تجميلاً: `_userHasPermissionFresh` ينادي
    // `ref.invalidate(currentUserPermissionsProvider)` مع **كلّ** حفظِ فاتورة
    // (F2/F4) وكلّ تعديلِ فاتورةٍ مرحّلة. فكان كلُّ `PermissionGuard` على
    // الشجرة يسقط في فرع «التحميل» ويعرض **الابنَ بلا حراسة** طوالَ دورة
    // القراءة من القاعدة — على شاشة البيع وعلى الإعدادات معاً.
    //
    // و`valueOrNull` يجعل ذلك مستحيلاً بعد أوّل قراءةٍ ناجحة، فيبقى الفرعُ
    // أدناه للإقلاع البارد وحدَه — وهناك **يُغلَق** لا يُفتَح.
    final userPermissions = permissionsAsync.value;
    if (userPermissions == null) {
      // إقلاعٌ باردٌ بلا قيمةٍ بعد: الحارسُ يفشل **مغلقاً**. عرضُ الابن
      // «تفاؤلاً» هنا كان يعني أن يومَض الزرُّ المحروسُ ظاهراً وقابلاً للضغط
      // قبل أن تُقرأ الصلاحيات.
      return fallback ?? const SizedBox.shrink();
    }

    final hasPermission = _checkPermission(userPermissions);

    // ⚠️ **المشروطُ يُظهر الودجتَ ويطلب الموافقةَ عند اللمس.**
    //    التصميمُ يصفه «يحتاج موافقةً أو حدّاً» — فالمشغّلُ **يرى** الإجراءَ
    //    (‏إخفاؤه كان سيجعله ممنوعاً لا مشروطاً) ولا يُنفَّذ إلّا بموافقة.
    //    وهذا عينُ ما يفعله `allowManagerOverride`، فيُعاد استعمالُ مساره
    //    بدل بناء ثانٍ.
    final conditional = _isConditional(userPermissions);

    if (hasPermission && !conditional) {
      return child;
    }

    // If manager override is allowed, show the widget with override wrapper.
    // `fallback` (لو موجود) هو اللي بيتعرض قبل الموافقة — شوف توثيق الحقل.
    if (allowManagerOverride || conditional) {
      return _ManagerOverrideWrapper(
        permission: permission.isNotEmpty
            ? permission
            : (allOf?.first ?? anyOf?.first ?? ''),
        actionName: actionName,
        onGranted: onGranted,
        lockedChild: fallback,
        child: child,
      );
    }

    if (showDisabled) {
      return _buildDisabledChild();
    }

    return fallback ?? const SizedBox.shrink();
  }

  /// هل أيٌّ من الأكواد التي يحرسها هذا الحارسُ ممنوحٌ **مشروطاً**؟
  ///
  /// وواحدٌ مشروطٌ يكفي: الحارسُ بابٌ واحدٌ، فلو مرّ لأنّ بقيّةَ الأكواد
  /// غيرُ مشروطةٍ لسقط الشرطُ عن الكود المشروط.
  bool _isConditional(List<String> userPermissions) {
    bool cond(String c) =>
        c.isNotEmpty && PermissionCodes.isConditionalIn(userPermissions, c);
    if (permission.isNotEmpty) return cond(permission);
    if (allOf != null && allOf!.isNotEmpty) return allOf!.any(cond);
    if (anyOf != null && anyOf!.isNotEmpty) return anyOf!.any(cond);
    return false;
  }

  bool _checkPermission(List<String> userPermissions) {
    // SYSTEM ADMIN BYPASS: مدير النظام لديه صلاحية كاملة
    // EXCEPT for critical financial operations — segregation of duties
    final isSystemAdmin = userPermissions.contains('system_admin') ||
        userPermissions.contains('*');
    if (isSystemAdmin && !_hasCriticalFinancialOp()) {
      return true;
    }

    // Check single permission
    if (permission.isNotEmpty) {
      return userPermissions.contains(permission);
    }

    // Check ALL of multiple permissions
    if (allOf != null && allOf!.isNotEmpty) {
      return allOf!.every((p) => userPermissions.contains(p));
    }

    // Check ANY of multiple permissions
    if (anyOf != null && anyOf!.isNotEmpty) {
      return anyOf!.any((p) => userPermissions.contains(p));
    }

    return false;
  }

  /// Returns true if any of the permissions being checked are critical financial ops.
  bool _hasCriticalFinancialOp() {
    if (permission.isNotEmpty &&
        PermissionCodes.criticalFinancialOps.contains(permission)) {
      return true;
    }
    if (allOf != null &&
        allOf!.any((p) => PermissionCodes.criticalFinancialOps.contains(p))) {
      return true;
    }
    if (anyOf != null &&
        anyOf!.any((p) => PermissionCodes.criticalFinancialOps.contains(p))) {
      return true;
    }
    return false;
  }

  Widget _buildDisabledChild() {
    // Try to disable the child if it's a button
    if (child is ElevatedButton) {
      final button = child as ElevatedButton;
      return ElevatedButton(
        onPressed: null,
        style: button.style,
        child: button.child,
      );
    }
    if (child is TextButton) {
      final button = child as TextButton;
      return TextButton(
        onPressed: null,
        style: button.style,
        child: button.child!,
      );
    }
    if (child is OutlinedButton) {
      final button = child as OutlinedButton;
      return OutlinedButton(
        onPressed: null,
        style: button.style,
        child: button.child!,
      );
    }
    if (child is IconButton) {
      final button = child as IconButton;
      return IconButton(
        onPressed: null,
        icon: button.icon,
        tooltip: button.tooltip,
      );
    }

    // For other widgets, wrap in IgnorePointer with reduced opacity
    return IgnorePointer(child: Opacity(opacity: 0.5, child: child));
  }
}

/// Digs the tap callback out of [child] so the manager-override wrapper knows
/// what to run after approval. Returns `null` when it cannot find one.
///
/// ── ليه ده موجود أصلاً، وليه هو الخيار الأضعف ────────────────────────────────
/// الحارس بيلفّ الابن في `AbsorbPointer` عشان يمسك الضغطة بنفسه، فبعد الموافقة
/// لازم يعرف يعمل إيه. تخمين نوع الودجت شغّال لكنه هشّ بطبيعته: أي نوع مش مكتوب
/// في القايمة دي بيرجع `null`. **`PermissionGuard.onGranted` هو الطريق الصح**؛
/// ده احتياطي لمواقع الاستدعاء القديمة.
///
/// ── الباج اللي عاش هنا ────────────────────────────────────────────────────
/// `ListTile` ما كانش موجود في القائمة، وكل مداخل «الأدوار والصلاحيات»
/// و«إدارة المستخدمين» في شاشتَي الإعدادات (١١ موضع) عبارة عن `ListTile`.
/// وكمان الفشل كان بيرجّع دالة فاضية بدل `null`، فالحارس كان «ينجح» ويشغّل
/// اللاشيء: الكاشير يضغط، يكتب كلمة مرور المدير، الديالوج يقفل، وما يحصلش حاجة
/// — بيتقرا كأن النظام رفضه.
///
/// مكشوف للاختبار عشان إضافة نوع ودجت جديد تبقى مغطّاة بدل ما تتكتشف ميدانياً.
@visibleForTesting
VoidCallback? extractChildAction(Widget child) {
  if (child is ElevatedButton) return child.onPressed;
  if (child is OutlinedButton) return child.onPressed;
  if (child is TextButton) return child.onPressed;
  if (child is IconButton) return child.onPressed;
  if (child is ListTile) return child.onTap;
  if (child is InkWell) return child.onTap;
  if (child is InkResponse) return child.onTap;
  if (child is GestureDetector) return child.onTap;

  // For wrapper widgets, recursively search.
  if (child is Expanded) return extractChildAction(child.child);
  if (child is Flexible) return extractChildAction(child.child);
  if (child is Center && child.child != null) {
    return extractChildAction(child.child!);
  }
  if (child is Align && child.child != null) {
    return extractChildAction(child.child!);
  }
  if (child is SizedBox && child.child != null) {
    return extractChildAction(child.child!);
  }
  if (child is Padding && child.child != null) {
    return extractChildAction(child.child!);
  }
  if (child is Container && child.child != null) {
    return extractChildAction(child.child!);
  }
  if (child is Material && child.child != null) {
    return extractChildAction(child.child!);
  }
  if (child is AnimatedOpacity && child.child != null) {
    return extractChildAction(child.child!);
  }
  if (child is Opacity && child.child != null) {
    return extractChildAction(child.child!);
  }
  if (child is DecoratedBox && child.child != null) {
    return extractChildAction(child.child!);
  }
  if (child is ColoredBox && child.child != null) {
    return extractChildAction(child.child!);
  }
  if (child is ConstrainedBox && child.child != null) {
    return extractChildAction(child.child!);
  }
  if (child is UnconstrainedBox && child.child != null) {
    return extractChildAction(child.child!);
  }
  if (child is Tooltip && child.child != null) {
    return extractChildAction(child.child!);
  }
  if (child is MouseRegion && child.child != null) {
    return extractChildAction(child.child!);
  }
  if (child is Semantics && child.child != null) {
    return extractChildAction(child.child!);
  }

  return null;
}

/// Wrapper that intercepts button presses and asks for manager override
class _ManagerOverrideWrapper extends ConsumerStatefulWidget {
  final String permission;
  final String? actionName;
  final VoidCallback? onGranted;

  /// اللي بيتعرض **قبل** موافقة المدير لما الحارس يكون معاه `fallback`
  /// (كارت قيمته `---` مثلاً). `null` = اعرض [child] زي ما كان — ده حال كل
  /// مواقع الأزرار: الزرار لازم يفضل باين عشان يتضغط ويُطلب عليه الموافقة.
  final Widget? lockedChild;

  final Widget child;

  const _ManagerOverrideWrapper({
    required this.permission,
    this.actionName,
    this.onGranted,
    this.lockedChild,
    required this.child,
  });

  @override
  ConsumerState<_ManagerOverrideWrapper> createState() =>
      _ManagerOverrideWrapperState();
}

class _ManagerOverrideWrapperState
    extends ConsumerState<_ManagerOverrideWrapper> {
  VoidCallback? _originalOnPressed;

  /// Set once a manager approved a child that has no single action to run
  /// (a whole settings section, a toggle). See [_requestOverride].
  bool _unlocked = false;

  @override
  Widget build(BuildContext context) {
    // Approval already granted for a section-shaped child: hand the child back
    // untouched so it behaves exactly as it does for a permitted user.
    if (_unlocked) return widget.child;

    // البديل (لو موجود) هو المعروض قبل الموافقة — وده الفرق اللي بيخلّي
    // صلاحيات العرض تخبّي فعلاً بدل ما تمتص الضغطة وبس.
    final visible = widget.lockedChild ?? widget.child;

    // An explicit callback always wins — no guessing needed.
    _originalOnPressed = widget.onGranted ?? extractChildAction(visible);

    // The tap is intercepted unconditionally. It used to be wired only when a
    // callback had been resolved, but the extractor always resolved SOMETHING
    // (a no-op on failure), so that condition never actually guarded anything
    // — and a guard that silently swallows the tap is worse than one that
    // does something meaningful with the approval.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _requestOverride(context),
      child: AbsorbPointer(child: visible),
    );
  }

  Future<void> _requestOverride(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ManagerOverrideDialog(
        permission: widget.permission,
        actionName: widget.actionName,
      ),
    );

    if (result != true) return;

    final action = widget.onGranted ?? _originalOnPressed;
    if (action != null) {
      // ابن له فعل واحد واضح (زرار، أو `ListTile` بـ `onTap`) — نشغّله فوراً،
      // فالموافقة بتوصّل للنتيجة في خطوة واحدة زي ما الكاشير متوقّع.
      action();
      // لو كان فيه بديل معروض (صلاحية عرض)، الموافقة كمان **بتكشف** الأصل —
      // تشغيل الفعل لوحده كان هيسيب الكارت مكتوب فيه `---` بعد الموافقة.
      if (widget.lockedChild != null && mounted) {
        setState(() => _unlocked = true);
      }
      return;
    }

    // ── ابن مالوش فعل واحد: نفتح القفل بدل ما نخمّن ──────────────────────────
    // فيه مواقع استدعاء بتلفّ **قسم كامل** (`_buildSettingsCard` بداخله عدة
    // مداخل) أو مفتاح تبديل (`_ServerPermsToggleTile`) — دول مالهمش «الفعل»
    // الواحد اللي يتشغّل بعد الموافقة، وأي تخمين هيبقى غلط.
    //
    // الصح دلالياً إن الموافقة **تفكّ القفل**: الابن يرجع يشتغل عادي، والمدير
    // يضغط اللي هو عايزه بنفسه. وده كمان بيخلّي المفتاح قابل للتبديل، وهو حاجة
    // ما كانتش ممكنة أصلاً بمنطق «استخرج الدالة وشغّلها».
    //
    // قبل كده كان بيتحط `() {}` هنا وتُنادى — فالموافقة «تنجح» وما يحصلش حاجة.
    if (!mounted) return;
    debugPrint(
      '[PermissionGuard] تمت الموافقة على قسم بلا فعل واحد — '
      'permission=${widget.permission} childType=${widget.child.runtimeType} '
      '→ فُك القفل.',
    );
    setState(() => _unlocked = true);
  }
}

/// Dialog for manager password entry
class _ManagerOverrideDialog extends ConsumerStatefulWidget {
  final String permission;
  final String? actionName;

  /// بابُ الطلب — يمنع صرفَ الإذن في بابٍ آخرَ يتقاسم نفسَ الكود.
  final String? scope;

  const _ManagerOverrideDialog({
    required this.permission,
    this.actionName,
    this.scope,
  });

  @override
  ConsumerState<_ManagerOverrideDialog> createState() =>
      _ManagerOverrideDialogState();
}

class _ManagerOverrideDialogState
    extends ConsumerState<_ManagerOverrideDialog> {
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _verifyPassword() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => _errorMessage = 'الرجاء إدخال كلمة المرور');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);

      // Authenticate by password or MSR card code
      final userWithRole = await authRepo.authenticateByPasswordOrCard(password);

      if (userWithRole == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'كلمة المرور غير صحيحة';
        });
        return;
      }

      // Check if authenticated user has the required permission or is system admin
      final userPermissions = await authRepo.getUserPermissionCodes(
        userWithRole.user.id,
      );

      // SYSTEM ADMIN BYPASS: مدير النظام لديه صلاحية كاملة
      // EXCEPT for critical financial operations — segregation of duties
      final isSystemAdmin =
          userPermissions.contains('system_admin') ||
          userPermissions.contains('*');
      final isCriticalOp =
          PermissionCodes.criticalFinancialOps.contains(widget.permission);

      if ((isSystemAdmin && !isCriticalOp) || userPermissions.contains(widget.permission)) {
        // Success! An admin has authorized this SINGLE action.
        //
        // Do NOT call `authProvider.notifier.elevate(...)` here — that used
        // to leak the authorization into session-wide state, so every
        // subsequent `PermissionGuard` in the tree started passing silently
        // until the user logged out. The contract of this dialog is pure:
        // validate the password, return `true`, and let the caller run
        // exactly one action. Next gated tap triggers a fresh prompt.
        //
        // ManagerApprovalCache: stamp this permission with a 60-second,
        // single-use approval token. The downstream defence-in-depth
        // checks (e.g. `_userHasPermissionFresh` inside
        // `_processPaymentAndSave`) consume the token so the cashier
        // doesn't get prompted a SECOND time for the same logical action
        // (button → payment → save). The token is consumed on first
        // read, so it can't authorise any later, distinct action.
        ManagerApprovalCache.instance
            .grant(widget.permission, scope: widget.scope);
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'المستخدم "${userWithRole.user.displayName}" ليس لديه صلاحية لهذا الإجراء';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'حدث خطأ: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                PhosphorIconsBold.shieldWarning,
                color: AppColors.warning,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'تصريح المسؤول مطلوب',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.actionName != null) ...[
                Text(
                  'الإجراء: ${widget.actionName}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'هذا الإجراء يتطلب صلاحية خاصة.\nالرجاء إدخال كلمة مرور المسؤول للمتابعة.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'كلمة مرور المسؤول',
                  prefixIcon: const Icon(PhosphorIconsBold.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? PhosphorIconsBold.eye
                          : PhosphorIconsBold.eyeSlash,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  errorText: _errorMessage,
                ),
                onSubmitted: (_) => _verifyPassword(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _verifyPassword,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(PhosphorIconsBold.checkCircle, size: 18),
            label: const Text('تأكيد'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// A helper widget that checks permission and provides a boolean to builder
class PermissionBuilder extends ConsumerWidget {
  final String permission;
  final Widget Function(BuildContext context, bool hasPermission) builder;

  const PermissionBuilder({
    super.key,
    required this.permission,
    required this.builder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);

    return permissionsAsync.when(
      data: (userPermissions) {
        final hasPermission = userPermissions.contains(permission);
        return builder(context, hasPermission);
      },
      loading: () => builder(context, false),
      error: (_, _) => builder(context, false),
    );
  }
}

/// B5: Public function to request manager approval for high-value operations
/// Returns true if approved, false if cancelled or denied.
Future<bool> requestManagerApproval(
  BuildContext context, {
  required String actionName,
  String permission = 'approve_high_value_return',

  /// بابُ الطلب. حين يُمرَّر، لا يُصرَف الإذنُ إلّا في نفس الباب —
  /// انظر `ManagerApprovalCache._key`. و`null` تُبقي السلوكَ القائم.
  String? scope,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ManagerOverrideDialog(
      permission: permission,
      actionName: actionName,
      scope: scope,
    ),
  );
  return result == true;
}

/// هل تحوي [permissions] الكودَ [permission]، مع تجاوز مدير النظام؟
///
/// نفسُ منطق `PermissionGuard._checkPermission` بالحرف — بما فيه أن التجاوزَ
/// **لا** يشمل [PermissionCodes.criticalFinancialOps]. وفصلُه دالّةً خالصةً
/// يجعله قابلاً للاختبار بلا شجرة ودجت.
bool hasPermissionWithAdminBypass(
  List<String> permissions,
  String permission,
) {
  final isSystemAdmin =
      permissions.contains('system_admin') || permissions.contains('*');
  if (isSystemAdmin && !PermissionCodes.criticalFinancialOps.contains(permission)) {
    return true;
  }
  return permissions.contains(permission);
}

/// بوّابةٌ إجرائيةٌ عامّة: يسمح، أو يطلب موافقةَ مسؤولٍ يملك الكود.
///
/// ── لماذا توجد بجانب [PermissionGuard] ──────────────────────────────────
/// [PermissionGuard] يلفّ **ودجت**، فيحمي الضغطةَ على زرٍّ بعينه. ولا يحمي
/// الدالّةَ التي يستدعيها الزرّ — فأيُّ مدخلٍ آخرَ لها (اختصارُ لوحة مفاتيح،
/// قائمةُ سياق، استدعاءٌ برمجيّ) يتخطّاه كلياً.
///
/// وهذا عطبٌ **مقيسٌ** لا نظريّ: `AppShortcuts(onNew: _addProduct)` كان
/// يستدعي نفسَ الدالّة التي يلفّ زرَّها `PermissionGuard(productsAdd)` — فـ
/// **F5** يضيف صنفاً بلا فحص. ونفسُ النمط في المشتريات وفواتير البيع.
///
/// فالقاعدة: يُحرَس **القِمع** لا المداخل. و[PermissionGuard] يبقى للإخفاء
/// البصريّ، وهذه للمنع الفعليّ.
///
/// ⚠️ وتستهلك موافقةَ المسؤول من [ManagerApprovalCache] أوّلاً — وإلا سُئل
/// المسؤولُ مرّتين حين يكون الزرُّ ملفوفاً بالحارس **و** الدالّةُ محروسة.
Future<bool> ensurePermission(
  WidgetRef ref,
  BuildContext context,
  String permission, {
  required String actionName,
}) async {
  if (ManagerApprovalCache.instance.consume(permission)) return true;
  // ⚠️ **المشروطُ يُفحَص قبل المِلك، والترتيبُ هو الميزةُ كلُّها.**
  //    الصلاحيةُ المشروطةُ **ممنوحةٌ** فعلاً — صفُّها موجودٌ في
  //    `role_permissions` — فلو فُحص المِلكُ أوّلاً لعاد `true` ولما سُئل
  //    مسؤولٌ أبداً، وصار «مشروط» مفتاحاً لا يفعل شيئاً. راجع
  //    `test/unit/conditional_permission_test.dart`: طفرةٌ تعكس السطرَين
  //    تُسقط فحصاً صريحاً.
  // `.value` لا `asData?.value`: الثاني يرجع `null` في كلّ إعادة تحميل، وهنا
  // ذلك يعني سؤالَ المسؤول بلا داعٍ لا فتحَ الباب — لكنّ الاتّساق مقصود.
  final perms =
      ref.read(currentUserPermissionsProvider).value ?? const <String>[];
  if (!PermissionCodes.isConditionalIn(perms, permission) &&
      hasPermissionWithAdminBypass(perms, permission)) {
    return true;
  }
  if (!context.mounted) return false;
  return requestManagerApproval(
    context,
    actionName: actionName,
    permission: permission,
  );
}

/// Extension to check permission synchronously when you already have permissions
extension PermissionListExtension on List<String> {
  bool hasPermission(String code) => contains(code);
  bool hasAnyPermission(List<String> codes) => codes.any((c) => contains(c));
  bool hasAllPermissions(List<String> codes) => codes.every((c) => contains(c));
}
