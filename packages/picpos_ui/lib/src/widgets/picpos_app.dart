import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n.dart';
import '../theme.dart';

/// `MaterialApp` wired for PicPos: light/dark themes, AR (RTL) / EN (LTR)
/// from [settings], Material localizations, and a [PicPosSettingsScope].
class PicPosMaterialApp extends StatelessWidget {
  const PicPosMaterialApp({super.key, required this.settings, required this.title, required this.home});
  final PicPosAppSettings settings;

  /// `(locale) → window title` (the launcher label is set by Android).
  final String Function(Locale locale) title;
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return PicPosSettingsScope(
      settings: settings,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (ctx) => title(Localizations.localeOf(ctx)),
          theme: buildPicPosTheme(Brightness.light),
          darkTheme: buildPicPosTheme(Brightness.dark),
          themeMode: settings.themeMode,
          locale: settings.locale,
          supportedLocales: picposSupportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: home,
        ),
      ),
    );
  }
}
