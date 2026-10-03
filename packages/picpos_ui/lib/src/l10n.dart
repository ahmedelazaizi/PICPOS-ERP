import 'package:flutter/material.dart';

/// Arabic (default, RTL) and English (LTR).
const picposSupportedLocales = [Locale('ar'), Locale('en')];

/// A string table of `(ar, en)` pairs — the `S`-table pattern of
/// mobile/lib/l10n/strings.dart, shared so both apps and this package use
/// one mechanism. `{name}` placeholders are filled from `params`.
class L10nTable {
  const L10nTable(this.entries);
  final Map<String, (String, String)> entries;

  /// A new table with [other]'s entries added (other wins on clashes).
  L10nTable merge(L10nTable other) => L10nTable({...entries, ...other.entries});

  String lookup(String key, {required bool ar, Map<String, Object?> params = const {}}) {
    final pair = entries[key];
    if (pair == null) return key;
    var s = ar ? pair.$1 : pair.$2;
    params.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  /// Coverage helper for tests: keys whose Arabic or English text is empty,
  /// or whose two texts use different `{placeholders}`.
  List<String> coverageProblems() {
    final out = <String>[];
    final ph = RegExp(r'\{(\w+)\}');
    entries.forEach((k, v) {
      if (v.$1.trim().isEmpty) out.add('$k: missing ar');
      if (v.$2.trim().isEmpty) out.add('$k: missing en');
      final a = ph.allMatches(v.$1).map((m) => m[1]).toSet();
      final e = ph.allMatches(v.$2).map((m) => m[1]).toSet();
      if (a.length != e.length || !a.containsAll(e)) out.add('$k: placeholders differ');
    });
    return out;
  }
}

/// Strings used by the widgets of this package.
const picposUiStrings = L10nTable({
  'more': ('المزيد', 'More'),
  'asOf': ('حتى {time}', 'As of {time}'),
  'asOfStale': ('بيانات قديمة — {time}', 'Stale data — {time}'),
  'noData': ('لا توجد بيانات', 'No data'),
  'connLocal': ('محلي', 'Local'),
  'connCloud': ('سحابي', 'Cloud'),
  'connOffline': ('غير متصل', 'Offline'),
  'language': ('اللغة', 'Language'),
  'arabic': ('العربية', 'العربية'),
  'english': ('English', 'English'),
  'theme': ('المظهر', 'Theme'),
  'light': ('فاتح', 'Light'),
  'dark': ('داكن', 'Dark'),
});

/// Resolves a table for a locale: `final t = Tr(table, locale); t('key')`.
class Tr {
  Tr(this.table, this.locale);
  final L10nTable table;
  final Locale locale;
  bool get isAr => locale.languageCode != 'en';
  TextDirection get direction => isAr ? TextDirection.rtl : TextDirection.ltr;

  String call(String key, [Map<String, Object?> params = const {}]) => table.lookup(key, ar: isAr, params: params);

  static Tr of(BuildContext context, L10nTable table) => Tr(table, Localizations.localeOf(context));
}

/// Language and theme choice of an app (in memory; [onChanged] lets the app
/// persist it).
class PicPosAppSettings extends ChangeNotifier {
  PicPosAppSettings({Locale locale = const Locale('ar'), ThemeMode themeMode = ThemeMode.light, this.onChanged})
      : _locale = locale,
        _themeMode = themeMode;

  Locale _locale;
  ThemeMode _themeMode;
  final void Function(PicPosAppSettings settings)? onChanged;

  Locale get locale => _locale;
  ThemeMode get themeMode => _themeMode;
  bool get isArabic => _locale.languageCode != 'en';
  bool get isDark => _themeMode == ThemeMode.dark;

  set locale(Locale v) {
    if (v == _locale) return;
    _locale = v;
    _changed();
  }

  set themeMode(ThemeMode v) {
    if (v == _themeMode) return;
    _themeMode = v;
    _changed();
  }

  void toggleLocale() => locale = isArabic ? const Locale('en') : const Locale('ar');
  void toggleDark() => themeMode = isDark ? ThemeMode.light : ThemeMode.dark;

  void _changed() {
    notifyListeners();
    onChanged?.call(this);
  }
}

/// Makes [PicPosAppSettings] reachable from the widget tree.
class PicPosSettingsScope extends InheritedNotifier<PicPosAppSettings> {
  const PicPosSettingsScope({super.key, required PicPosAppSettings settings, required super.child})
      : super(notifier: settings);

  static PicPosAppSettings of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<PicPosSettingsScope>();
    assert(s != null, 'No PicPosSettingsScope above this context');
    return s!.notifier!;
  }
}
