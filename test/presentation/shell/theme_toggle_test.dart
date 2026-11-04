import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/theme_mode_provider.dart';
import 'package:picpos_erp/presentation/shell/theme_toggle_tile.dart';
import 'package:picpos_erp/services/theme_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ThrowingThemeService extends ThemeService {
  @override
  Future<void> saveThemeMode(ThemeMode mode) async =>
      throw Exception('prefs down');
}

ProviderContainer _container({ThemeService? service, ThemeMode? initial}) {
  final c = ProviderContainer(overrides: [
    if (service != null) themeServiceProvider.overrideWithValue(service),
    if (initial != null) initialThemeModeProvider.overrideWithValue(initial),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('isEffectivelyDark', () {
    test('resolves all mode/brightness combinations', () {
      expect(isEffectivelyDark(ThemeMode.dark, Brightness.light), isTrue);
      expect(isEffectivelyDark(ThemeMode.light, Brightness.dark), isFalse);
      expect(isEffectivelyDark(ThemeMode.system, Brightness.dark), isTrue);
      expect(isEffectivelyDark(ThemeMode.system, Brightness.light), isFalse);
    });
  });

  group('ThemeModeNotifier', () {
    test('toggle flips the effective mode', () async {
      final cases = <(ThemeMode, Brightness, ThemeMode)>[
        (ThemeMode.light, Brightness.light, ThemeMode.dark),
        (ThemeMode.dark, Brightness.light, ThemeMode.light),
        (ThemeMode.system, Brightness.dark, ThemeMode.light),
        (ThemeMode.system, Brightness.light, ThemeMode.dark),
      ];
      for (final (start, bright, expected) in cases) {
        final c = _container(initial: start);
        await c.read(themeModeProvider.notifier).toggle(bright);
        expect(c.read(themeModeProvider), expected, reason: '$start/$bright');
      }
    });

    test('saved mode is restored in a new container', () async {
      final a = _container();
      await a.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
      final b = _container();
      expect(b.read(themeModeProvider), ThemeMode.system);
      await b.read(themeModeProvider.notifier).init();
      expect(b.read(themeModeProvider), ThemeMode.dark);
    });

    test('initialThemeModeProvider seeds the first state (no light flash)', () {
      expect(
        _container(initial: ThemeMode.dark).read(themeModeProvider),
        ThemeMode.dark,
      );
    });

    test('save failure does not throw and keeps the new mode', () async {
      final c = _container(service: _ThrowingThemeService());
      await c.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
      expect(c.read(themeModeProvider), ThemeMode.dark);
    });
  });

  group('ThemeToggleTile', () {
    Future<ProviderContainer> pump(
      WidgetTester t, {
      required ThemeMode mode,
      required Brightness platform,
      bool expanded = true,
    }) async {
      t.platformDispatcher.platformBrightnessTestValue = platform;
      addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
      final c = _container(initial: mode);
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(body: ThemeToggleTile(expanded: expanded)),
        ),
      ));
      return c;
    }

    for (final (mode, bright, expected) in [
      (ThemeMode.light, Brightness.light, ThemeMode.dark),
      (ThemeMode.dark, Brightness.light, ThemeMode.light),
      (ThemeMode.system, Brightness.dark, ThemeMode.light),
      (ThemeMode.system, Brightness.light, ThemeMode.dark),
    ]) {
      testWidgets('tap from $mode on $bright platform -> $expected',
          (t) async {
        final c = await pump(t, mode: mode, platform: bright);
        await t.tap(find.byKey(const ValueKey('themeToggleTile')));
        await t.pump();
        expect(c.read(themeModeProvider), expected);
      });
    }

    testWidgets('collapsed shows icon only and still toggles', (t) async {
      final c = await pump(t,
          mode: ThemeMode.light, platform: Brightness.light, expanded: false);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Text), findsNothing);
      await t.tap(find.byKey(const ValueKey('themeToggleTile')));
      await t.pump();
      expect(c.read(themeModeProvider), ThemeMode.dark);
    });
  });
}
