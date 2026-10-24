// P2 — مخزن المسودة: debounce، تالفٌ ⇒ null، لا أسرار، clear، وعلم committing.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_draft.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_draft_store.dart';

void main() {
  late Map<String, String> data;
  late int writes;
  FirstRunDraftStore make() => FirstRunDraftStore(
        read: (k) async => data[k],
        write: (k, v) async {
          writes++;
          data[k] = v;
        },
        debounce: const Duration(milliseconds: 30),
        newId: () => 'gen-id',
      );

  setUp(() {
    data = {};
    writes = 0;
  });

  test('debounce: عدّة تعديلات ⇒ كتابة واحدة بآخر قيمة', () async {
    final s = make();
    final d = s.fresh();
    s.scheduleSave(d.copyWith(companyName: 'أ'));
    s.scheduleSave(d.copyWith(companyName: 'أب'));
    s.scheduleSave(d.copyWith(companyName: 'أبج'));
    expect(writes, 0);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(writes, 1);
    expect((await s.load())!.companyName, 'أبج');
  });

  test('flush يكتب المعلّق فوراً', () async {
    final s = make();
    s.scheduleSave(s.fresh().copyWith(companyName: 'س'));
    await s.flush();
    expect(writes, 1);
    s.dispose();
  });

  test('JSON تالف أو إصدار مجهول أو فارغ ⇒ null', () async {
    final s = make();
    expect(await s.load(), isNull);
    data['setup_draft_v2'] = '{bad';
    expect(await s.load(), isNull);
    data['setup_draft_v2'] = jsonEncode({'version': 7});
    expect(await s.load(), isNull);
    data['setup_draft_v2'] = '   ';
    expect(await s.load(), isNull);
  });

  test('لا أسرار في المخزن: لا password/pairing/license/key', () async {
    final s = make();
    s.scheduleSave(s.fresh().copyWith(companyName: 'شركة', endpoint: '10.0.0.5'));
    await s.flush();
    final raw = data['setup_draft_v2']!.toLowerCase();
    for (final bad in ['password', 'pairing', 'license', 'secret', 'token']) {
      expect(raw, isNot(contains(bad)));
    }
  });

  test('markCommitting ثم clear', () async {
    final s = make();
    expect(await s.wasCommitting(), isFalse);
    await s.markCommitting();
    expect(await s.wasCommitting(), isTrue);
    s.scheduleSave(s.fresh());
    await s.clear();
    expect(data['setup_draft_v2'], isEmpty);
    expect(await s.wasCommitting(), isFalse);
    // clear يلغي أي حفظ معلّق.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(data['setup_draft_v2'], isEmpty);
  });

  test('المفاتيح محلية للجهاز: setup_draft_v2/setup_progress_v2', () {
    // حارس بنيوي على القائمة: لا تُدفع/تُسحب بالمزامنة.
    expect(FirstRunDraftStore.draftKey, 'setup_draft_v2');
    expect(FirstRunDraftStore.progressKey, 'setup_progress_v2');
  });

  test('مسودة جديدة تحمل السنة الحالية', () {
    expect(make().fresh().fiscalYear, DateTime.now().year);
  });

  test('FirstRunDraft.fromJson يرجع بمعرّف احتياطي', () {
    final d = FirstRunDraft.fromJson({'version': 1}, fallbackId: 'fb');
    expect(d!.draftId, 'fb');
    unawaited(Future<void>.value());
  });
}
