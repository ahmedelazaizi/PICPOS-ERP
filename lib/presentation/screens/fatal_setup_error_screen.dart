import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/core/design_system/typography.dart';
// ═══════════════════════════════════════════════════════════════════════════
// FATAL SETUP ERROR SCREEN — Spec 125 Mirror Foundation (FR-013)
// ═══════════════════════════════════════════════════════════════════════════
//
// Full-screen blocker shown when `NetworkService.reconcileWithDb(...)` detects
// state inconsistency between `network_mode` (DB) and related state (pairing
// config, first-sync flags, etc.).
//
// Per Spec 125 contracts/reconciler.md + research.md R3.
//
// Design rules:
//   - Full-screen blocker (no AppBar, no escape).
//   - Two clear actions only: "ادخل خيارات المطور" + "إعادة اعداد البدء".
//   - Dynamic reason in Arabic (from `ReconcileInconsistent.reasonAr`).
//   - Footer shows build + device hint for support call-in.
//   - No DB writes — purely display + delegate to action handlers.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../services/deployment/reconcile_result.dart';
import '../../services/network_service.dart';
import '../../core/config/brand.dart';

/// Wrapper that boots a minimal MaterialApp with only the Fatal screen.
/// Used from main_desktop.dart / main_web.dart when reconcileWithDb returns
/// [ReconcileInconsistent] — no other providers / DB / sync get initialized.
class FatalSetupErrorApp extends StatelessWidget {
  const FatalSetupErrorApp({
    super.key,
    required this.result,
    this.onEnterDevTools,
    this.onResetWizard,
    this.onRetrySelfHeal,
    this.onMirrorRepair,
  });

  final ReconcileInconsistent result;
  final VoidCallback? onEnterDevTools;
  final VoidCallback? onResetWizard;

  /// Spec 130 — additional callback for the "إعادة محاولة الإصلاح الذاتى"
  /// button, shown only when [result.kind] is [ReconcileFatalKind.pgSchemaParity].
  /// Re-runs `_ensurePostgresSchemaParity` in-process without an app restart.
  final VoidCallback? onRetrySelfHeal;

  /// Spec 131 — primary callback for the "إعادة المزامنة مع السيرفر"
  /// button, shown only when [result.kind] is
  /// [ReconcileFatalKind.mirrorCacheDivergence]. Re-runs
  /// `ClientFirstSyncService.performFirstSync()` (wipe + pull) and
  /// invalidates POS cart state on return.
  final VoidCallback? onMirrorRepair;

  @override
  Widget build(BuildContext context) {
    // Spec 130 — orange accent for PG-parity issues. Spec 131 — red accent
    // for mirror-cache-divergence (matches the default red severity).
    final isPgParity = result.kind == ReconcileFatalKind.pgSchemaParity;
    final seedColor =
        isPgParity ? Colors.orange.shade700 : AppColors.error;
    return MaterialApp(
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Cairo',
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
      ),
      home: FatalSetupErrorScreen(
        result: result,
        onEnterDevTools: onEnterDevTools,
        onResetWizard: onResetWizard,
        onRetrySelfHeal: onRetrySelfHeal,
        onMirrorRepair: onMirrorRepair,
      ),
    );
  }
}

/// The Fatal screen widget itself. Can also be pushed onto an existing
/// navigation stack (e.g. from a test harness or recovery flow).
class FatalSetupErrorScreen extends StatelessWidget {
  const FatalSetupErrorScreen({
    super.key,
    required this.result,
    this.onEnterDevTools,
    this.onResetWizard,
    this.onRetrySelfHeal,
    this.onMirrorRepair,
  });

  final ReconcileInconsistent result;
  final VoidCallback? onEnterDevTools;
  final VoidCallback? onResetWizard;

  /// Spec 130 — shown only when [result.kind] is
  /// [ReconcileFatalKind.pgSchemaParity]. Triggers an in-process retry of
  /// `_ensurePostgresSchemaParity` without restarting the app.
  final VoidCallback? onRetrySelfHeal;

  /// Spec 131 — shown only when [result.kind] is
  /// [ReconcileFatalKind.mirrorCacheDivergence]. Triggers
  /// `performFirstSync()` to re-pull authoritative server master data.
  final VoidCallback? onMirrorRepair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPgParity = result.kind == ReconcileFatalKind.pgSchemaParity;
    final isMirrorDivergence =
        result.kind == ReconcileFatalKind.mirrorCacheDivergence;
    final accentStrong =
        isPgParity ? Colors.orange.shade700 : AppColors.errorDark;
    final accentSurface =
        isPgParity ? Colors.orange.shade50 : AppColors.error.withValues(alpha: 0.08);
    final accentBorder =
        isPgParity ? Colors.orange.shade200 : AppColors.error.withValues(alpha: 0.25);
    final accentText =
        isPgParity ? Colors.orange.shade900 : AppColors.errorDark;
    final titleAr = isPgParity
        ? tr('فشل التهيئة الذاتية لقاعدة البيانات')
        : isMirrorDivergence
            ? tr('تعارض فى بيانات المرآة')
            : tr('النظام يحتاج لإعادة الإعداد');
    final subtitleAr = isPgParity
        ? 'تم اكتشاف انحراف فى مخطط قاعدة بيانات PostgreSQL لم يستطع '
            'الإصلاح الذاتى معالجته. الكتابة والقراءة محظورتان حتى الإصلاح.'
        : isMirrorDivergence
            ? 'بعض البيانات الأساسية محلياً لا تطابق السيرفر — أعد '
                'المزامنة لاستعادة التوافق.'
            : 'تم اكتشاف عدم اتساق بين إعدادات النظام والبيانات '
                'المخزّنة محلياً.';
    return PopScope(
      // Block Android-back / Esc — this is a hard blocker by design.
      canPop: false,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 48,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      isPgParity
                          ? PhosphorIconsBold.database
                          : isMirrorDivergence
                              ? PhosphorIconsBold.arrowsCounterClockwise
                              : PhosphorIconsBold.warningCircle,
                      size: 96,
                      color: accentStrong,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      titleAr,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      subtitleAr,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: accentSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: accentBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('التفاصيل:'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: accentText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            result.reasonAr,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: accentText,
                            ),
                          ),
                          if (result.details.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: EdgeInsets.zero,
                              title: Text(
                                tr('تفاصيل تشخيصية ({p0})', {'p0': result.details.length}),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: accentText,
                                ),
                              ),
                              children: result.details
                                  .map((d) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        child: Text(
                                          '• $d',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: accentText,
                                            fontFamily: AppTypography.mono,
                                          ),
                                          textDirection: TextDirection.ltr,
                                          textAlign: TextAlign.left,
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Spec 130 — retry button shown FIRST when applicable,
                    // because it's the fastest path back to a working app
                    // when the operator just fixed PG permissions.
                    if (isPgParity && onRetrySelfHeal != null) ...[
                      FilledButton.icon(
                        onPressed: onRetrySelfHeal,
                        icon: const Icon(PhosphorIconsBold.arrowsClockwise),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'إعادة محاولة الإصلاح الذاتى\n'
                            '(بعد منح صلاحيات DB المطلوبة)',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Spec 131 — primary action on the mirror-cache-divergence
                    // variant. Re-runs performFirstSync (wipe + pull) and
                    // clears the POS cart state on return.
                    if (isMirrorDivergence && onMirrorRepair != null) ...[
                      FilledButton.icon(
                        onPressed: onMirrorRepair,
                        icon: const Icon(PhosphorIconsBold.arrowsCounterClockwise),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'إعادة المزامنة مع السيرفر\n'
                            '(يستبدل بيانات المرآة بأحدث ما على السيرفر)',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      onPressed: onEnterDevTools,
                      icon: const Icon(PhosphorIconsBold.wrench),
                      label:  Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          tr('ادخل خيارات المطور للإصلاح\n(يتطلب كلمة سر المطور)'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: onResetWizard,
                      icon: const Icon(PhosphorIconsBold.arrowCounterClockwise),
                      label:  Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          tr('إعادة اعداد البدء\n(يمسح البيانات المحلية ويبدأ من الصفر)'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Divider(color: theme.colorScheme.outlineVariant),
                    const SizedBox(height: 8),
                    DefaultTextStyle.merge(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                      child: Column(
                        children: [
                          Text(tr('رمز المشكلة: {p0}', {'p0': result.reasonCode})),
                          Text('وضع النظام فى قاعدة البيانات: '
                              '${_arabicMode(result.dbMode)}'),
                           Text(tr('يرجى تصوير هذه الشاشة عند طلب الدعم الفنى.')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _arabicMode(NetworkMode m) {
    switch (m) {
      case NetworkMode.standalone:
        return tr('مستقل');
      case NetworkMode.server:
        return tr('سيرفر');
      case NetworkMode.client:
        return tr('عميل');
      case NetworkMode.mirror:
        return tr('مرآة');
    }
  }
}
