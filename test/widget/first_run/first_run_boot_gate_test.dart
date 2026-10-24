// بوّابة الإقلاع: تثبيتٌ جديد ⇒ المعالج الجديد؛ تثبيتٌ مكتمل ⇒ يتخطّاه بلا لمسه.
// ويحرس main.dart أن البوّابة تمرّ بـ`resolveSetupGateChild` ولا تنشئ المعالج
// القديم مباشرةً.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_entry.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_setup_screen.dart';

import 'first_run_test_kit.dart';

class _Gate extends ConsumerWidget {
  const _Gate();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return FutureBuilder<String?>(
      future: db.getSettingValue('setup_completed'),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        return resolveSetupGateChild(
          setupCompleted: snap.data,
          completed: () => const Text('MAIN', key: Key('main_screen')),
        );
      },
    );
  }
}

Future<void> _pumpGate(WidgetTester tester, AppDatabase db, FirstRunHarness h) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), ...h.overrides],
      child: const MaterialApp(home: _Gate()),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(loadEnglishCatalog);

  test('القرار الخالص: true فقط يتخطى المعالج', () {
    for (final v in [null, '', 'false', 'TRUE', '1']) {
      final w = resolveSetupGateChild(
        setupCompleted: v,
        completed: () => throw StateError('must not build main for "$v"'),
      );
      expect(w, isA<FirstRunSetupScreen>(), reason: '"$v"');
    }
    final done = resolveSetupGateChild(
      setupCompleted: 'true',
      completed: () => const SizedBox(key: Key('done')),
    );
    expect(done.key, const Key('done'));
  });

  testWidgets('تثبيت جديد (بلا setup_completed) ⇒ المعالج الجديد', (tester) async {
    useLocale(english: false);
    final db = AppDatabase.forTesting();
    await tester.runAsync(() => db.getBranches());
    final h = FirstRunHarness();
    await _pumpGate(tester, db, h);
    expect(find.byType(FirstRunSetupScreen), findsOneWidget);
    expect(find.byKey(const Key('main_screen')), findsNothing);
    await h.teardown(tester);
  });

  testWidgets('تثبيت مكتمل (setup_completed=true) ⇒ يتخطى المعالج تماماً',
      (tester) async {
    useLocale(english: false);
    final db = AppDatabase.forTesting();
    await tester.runAsync(() async {
      await db.getBranches();
      await db.setSetting('setup_completed', 'true');
    });
    final h = FirstRunHarness();
    await _pumpGate(tester, db, h);
    expect(find.byKey(const Key('main_screen')), findsOneWidget);
    expect(find.byType(FirstRunSetupScreen), findsNothing);
    // لا مسودة ولا تقدّم كُتبا في مخزن المعالج.
    expect(h.settings.values, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('main.dart يمرّ بـresolveSetupGateChild ولا يبني المعالج القديم', () {
    final src = File('lib/main.dart').readAsStringSync();
    expect(src, contains('resolveSetupGateChild('));
    expect(src, contains("setup_completed"));
    expect(src.contains('SetupWizardScreen'), isFalse);
  });

  test('المعالج الجديد لا يفتح المعالج القديم لأي مسار (مقر/فرع/مرآة)', () {
    for (final f in Directory('lib/presentation/screens/first_run')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      expect(s.contains('SetupWizardScreen'), isFalse, reason: f.path);
      expect(s.contains('setup_wizard_screen.dart'), isFalse, reason: f.path);
      expect(s.contains('_legacy'), isFalse, reason: f.path);
    }
  });

  test('ملفات المعالج الجديد بلا أي ذكر لعلامة أخرى', () {
    for (final root in ['lib/presentation/screens/first_run', 'lib/services/setup', 'lib/domain/models/first_run']) {
      for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final s = f.readAsStringSync().toLowerCase();
        expect(s.contains('uralcash'), isFalse, reason: f.path);
        expect(s.contains('ural-erp'), isFalse, reason: f.path);
        expect(f.lengthSync(), lessThan(30720), reason: f.path);
      }
    }
  });
}
