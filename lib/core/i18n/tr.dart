import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint, kDebugMode;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Runtime Arabic-as-key catalog used by the automated UI codemod.
class I18nCatalog {
  I18nCatalog._();

  static final ValueNotifier<Locale> localeNotifier =
      ValueNotifier<Locale>(const Locale('ar', 'EG'));
  static final Set<String> _missingKeys = <String>{};
  static Map<String, String> _english = <String, String>{};

  static Locale get activeLocale => localeNotifier.value;

  static Future<void> load({AssetBundle? bundle}) async {
    final raw = await (bundle ?? rootBundle).loadString('assets/i18n/en.json');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('assets/i18n/en.json must contain an object');
    }
    _english = <String, String>{
      for (final entry in decoded.entries)
        if (entry.value is String) entry.key: entry.value as String,
    };
  }

  static void setCatalog(Map<String, String> catalog) {
    _english = Map<String, String>.from(catalog);
  }

  static void setLocale(Locale locale) {
    if (localeNotifier.value == locale) return;
    localeNotifier.value = locale;
  }

  static Set<String> get missingKeys => Set<String>.unmodifiable(_missingKeys);

  static String translate(String arabic, [Map<String, Object?>? args]) {
    final isEnglish = activeLocale.languageCode == 'en';
    var template = arabic;
    if (isEnglish) {
      final translated = _english[arabic];
      if (translated != null && translated.isNotEmpty) {
        template = translated;
      } else if (kDebugMode && _missingKeys.add(arabic)) {
        debugPrint('[i18n] Missing English catalog entry: $arabic');
      }
    }
    return _replacePlaceholders(template, args);
  }

  static String _replacePlaceholders(
    String template,
    Map<String, Object?>? args,
  ) {
    if (args == null || args.isEmpty) return template;
    return template.replaceAllMapped(RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}'),
        (match) {
      final name = match.group(1)!;
      return args.containsKey(name) ? '${args[name]}' : match.group(0)!;
    });
  }
}

/// Translate an Arabic source template using the active UI locale.
String tr(String arabic, [Map<String, Object?>? args]) =>
    I18nCatalog.translate(arabic, args);
