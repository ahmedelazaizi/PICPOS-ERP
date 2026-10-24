import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/config/brand.dart';
import '../../core/i18n/tr.dart';

/// A0 (ADP-009): runs [reset] (forget mode + pairing, see
/// `resetProvisioning`) from the Fatal-setup screen, then replaces the UI with
/// a "restart the app" screen whose only button closes the program. The next
/// launch starts the first-run setup — no developer options involved.
Future<void> runProvisioningResetFlow(
  Future<void> Function() reset, {
  void Function(Widget app)? launch,
}) async {
  String? error;
  try {
    await reset();
  } catch (e) {
    error = e.toString();
  }
  (launch ?? (w) => runApp(w))(ProvisioningResetDoneApp(error: error));
}

class ProvisioningResetDoneApp extends StatelessWidget {
  const ProvisioningResetDoneApp({super.key, this.error, this.onClose});

  /// Non-null when the reset failed; the screen then reports it.
  final String? error;

  /// Test hook; defaults to closing the process.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
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
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      theme: ThemeData(useMaterial3: true, fontFamily: 'Cairo'),
      home: Builder(builder: (context) {
        final theme = Theme.of(context);
        final failed = error != null;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        failed
                            ? PhosphorIconsBold.warningCircle
                            : PhosphorIconsBold.checkCircle,
                        size: 80,
                        color: failed
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        failed
                            ? tr('تعذّرت إعادة توفير الجهاز')
                            : tr('تمت إعادة توفير الجهاز'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        failed
                            ? tr('تعذّرت إعادة الضبط: {p0}', {'p0': error})
                            : tr('أغلق البرنامج ثم افتحه من جديد لبدء الإعداد الأول.'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        onPressed: onClose ?? () => exit(0),
                        icon: const Icon(PhosphorIconsBold.power),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(tr('إغلاق البرنامج')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
