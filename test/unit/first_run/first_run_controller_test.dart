// P2 — المتحكّم والمخزن بلا واجهة: تغيير المسار يصفّر، لا قفز أمامياً، الاستئناف
// من الحقائق لا من المسودّة، لا أسرار مخزَّنة، وتالفُ JSON ⇒ مسودّةٌ فارغة،
// وتشغيل الإنهاء مرّتين لا يكرّر.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_draft.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_machine.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_packs.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_path.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_controller.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_draft_store.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_providers.dart';
import 'package:picpos_erp/presentation/screens/setup_wizard/setup_persistence_riverpod.dart';

import '../../widget/first_run/first_run_test_kit.dart';

ProviderContainer _container(
  MemorySettings settings,
  RecordingPersistence persistence, {
  FakeProbe? probe,
}) {
  final c = ProviderContainer(overrides: [
    firstRunDraftStoreProvider.overrideWith((ref) => FirstRunDraftStore(
          read: settings.read,
          write: settings.write,
          debounce: const Duration(milliseconds: 5),
          newId: () => 'ctl-id',
        )),
    firstRunStorageProbeProvider.overrideWithValue(probe ?? FakeProbe()),
    setupPersistenceProvider.overrideWithValue(persistence),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<FirstRunController> _ready(ProviderContainer c) async {
  c.listen(firstRunControllerProvider, (_, _) {});
  for (var i = 0; i < 20 && c.read(firstRunControllerProvider).loading; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return c.read(firstRunControllerProvider.notifier);
}

void _fillValid(FirstRunController ctl) {
  ctl.update((d) => d.copyWith(
        companyName: 'شركة',
        branchName: 'ف',
        warehouseName: 'م',
      ));
  ctl.setCurrency('JOD');
  ctl.updateSecrets((s) => s.copyWith(
        adminPassword: 'S3cretPass',
        adminPasswordConfirm: 'S3cretPass',
        developerPassword: 'dev1',
        developerPasswordConfirm: 'dev1',
      ));
}

void main() {
  setUpAll(loadEnglishCatalog);

  test('بداية نظيفة: مسودة جديدة بمعرّف وافتراضيات وتخزين مفحوص', () async {
    final c = _container(MemorySettings(), RecordingPersistence());
    await _ready(c);
    final s = c.read(firstRunControllerProvider);
    expect(s.loading, isFalse);
    expect(s.draft.draftId, 'ctl-id');
    expect(s.draft.currency, isEmpty);
    expect(s.draft.branchName, isNotEmpty);
    expect(s.draft.warehouseName, isNotEmpty);
    expect(s.draft.checks.storageChecked, isTrue);
    expect(s.resumedIncomplete, isFalse);
  });

  test('تغيير المسار يصفّر التقدم والأسرار، ولا قفز أمامياً', () async {
    final c = _container(MemorySettings(), RecordingPersistence());
    final ctl = await _ready(c);
    _fillValid(ctl);
    ctl.next(); // mode → company
    expect(c.read(firstRunControllerProvider).draft.step, 1);
    ctl.jumpToStep(4); // فوق maxStep
    expect(c.read(firstRunControllerProvider).draft.step, 1);
    ctl.selectPathTo(FirstRunPath.branch);
    final s = c.read(firstRunControllerProvider);
    expect((s.draft.step, s.draft.maxStep), (0, 0));
    expect(s.secrets.adminPassword, isEmpty);
    expect(s.draft.path, FirstRunPath.branch);
    // فحص التخزين يبقى من آخر نتيجة، لا من المسودة.
    expect(s.draft.checks.storageChecked, isTrue);
    expect(s.draft.checks.linked, isFalse);
  });

  test('التالي المحروس يضع الخطأ ولا يتقدّم', () async {
    final c = _container(MemorySettings(), RecordingPersistence());
    final ctl = await _ready(c);
    ctl.next(); // → company
    ctl.next(); // مرفوض: لا اسم ولا عملة
    final s = c.read(firstRunControllerProvider);
    expect(s.draft.step, 1);
    expect(s.error, isNotNull);
  });

  test('الحفظ المؤجّل لا يحوي أسراراً ولا أعلام تحقق', () async {
    final settings = MemorySettings();
    final c = _container(settings, RecordingPersistence());
    final ctl = await _ready(c);
    _fillValid(ctl);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final saved = settings.values['setup_draft_v2']!;
    expect(saved, contains('شركة'));
    expect(saved, isNot(contains('S3cretPass')));
    expect(saved, isNot(contains('dev1')));
    expect(saved.toLowerCase(), isNot(contains('password')));
    expect(saved, isNot(contains('storageChecked')));
    expect(FirstRunDraft.fromJson(jsonDecode(saved), fallbackId: 'x'), isNotNull);
  });

  test('استئناف: لا يُستعاد adminReady ولا الأسرار، والأعلام من الحقائق',
      () async {
    final settings = MemorySettings();
    final saved = const FirstRunDraft(draftId: 'old')
        .copyWith(companyName: 'قديمة', step: 3, maxStep: 3, checks: const FirstRunChecks(linked: true, firstSyncDone: true));
    settings.values['setup_draft_v2'] = jsonEncode(saved.toJson());
    final c = _container(settings, RecordingPersistence(), probe: FakeProbe(writable: false));
    await _ready(c);
    final s = c.read(firstRunControllerProvider);
    expect(s.draft.companyName, 'قديمة');
    expect(s.draft.step, 3);
    expect(s.secrets.adminPassword, isEmpty);
    expect(s.draft.checks.storageChecked, isFalse); // الواقع: غير قابل للكتابة
    expect(s.draft.checks.linked, isFalse);
    expect(s.draft.checks.firstSyncDone, isFalse);
  });

  test('finish: مرتان بنفس المسودة ⇒ طاولات بلا تكرار و setup_completed آخراً',
      () async {
    final p = RecordingPersistence();
    final c = _container(MemorySettings(), p);
    final ctl = await _ready(c);
    _fillValid(ctl);
    ctl.update((d) => d.copyWith(
          pack: FirstRunPack.restaurant,
          tablesCount: '5',
          step: 5,
          maxStep: 5,
        ));
    await ctl.finish();
    expect(c.read(firstRunControllerProvider).phase, FirstRunPhase.committed);
    final firstRun = List<String>.from(p.calls);
    // إعادة التشغيل بنفس المسودّة (‏محاكاة إعادة المحاولة بعد انهيار).
    c.read(firstRunControllerProvider.notifier).update((d) => d);
    // ‏`finish` يتجاهل نداءً بعد commit؛ نختبر المشغّل مباشرةً مرةً ثانية.
    final again = await c.read(firstRunFinisherProvider)(
      c.read(firstRunControllerProvider).draft,
      const FirstRunSecrets(
        adminPassword: 'S3cretPass',
        adminPasswordConfirm: 'S3cretPass',
        developerPassword: 'dev1',
        developerPasswordConfirm: 'dev1',
      ),
      p,
    );
    expect(again.ok, isTrue);
    expect(p.tableNames, hasLength(5));
    // آخر كتابة قيمةٍ هي setup_completed (ثم مسحُ breadcrumb التقدّم).
    final saves = firstRun.where((c) => c.startsWith('save:')).toList();
    expect(saves[saves.length - 2], 'save:setup_completed');
    expect(saves.last, 'save:setup_in_progress');
  });

  test('finish متزامن مزدوج لا يشغّل مرتين', () async {
    final p = RecordingPersistence();
    final c = _container(MemorySettings(), p);
    final ctl = await _ready(c);
    _fillValid(ctl);
    ctl.update((d) => d.copyWith(step: 5, maxStep: 5));
    final a = ctl.finish();
    final b = ctl.finish(); // يُتجاهل: busy
    await Future.wait([a, b]);
    expect(p.calls.where((c) => c == 'mode:standalone'), hasLength(1));
  });

  test('finish بخطوات ناقصة يقفز لأول خطوة فاشلة بلا كتابة', () async {
    final p = RecordingPersistence();
    final c = _container(MemorySettings(), p);
    final ctl = await _ready(c);
    ctl.update((d) => d.copyWith(step: 5, maxStep: 5));
    await ctl.finish();
    final s = c.read(firstRunControllerProvider);
    expect(s.error, isNotNull);
    expect(s.draft.step, 1); // company
    expect(p.calls, isEmpty);
  });
}
