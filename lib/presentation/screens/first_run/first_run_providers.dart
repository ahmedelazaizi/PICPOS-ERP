// مزوّدو الإعداد الأول — كلُّهم قابلٌ للاستبدال في الاختبار.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/providers.dart';
import '../../../services/setup/first_run_storage_probe.dart';
import 'first_run_draft_store.dart';
import 'first_run_finish.dart';

/// مخزنُ المسودّة عبر مستودع الإعدادات (‏بلا استيراد قاعدة).
final firstRunDraftStoreProvider = Provider<FirstRunDraftStore>((ref) {
  final repo = ref.read(settingsRepositoryProvider);
  final store = FirstRunDraftStore(
    read: repo.getSetting,
    write: repo.saveSetting,
  );
  // ما بقي معلَّقاً في نافذة الـdebounce يُكتَب قبل الإغلاق.
  ref.onDispose(() => unawaited(store.flush()));
  return store;
});

final firstRunStorageProbeProvider = Provider<FirstRunStorageProbe>((ref) {
  final db = ref.read(databaseProvider);
  return FirstRunStorageProbe(
    countInvoices: () async {
      final row = await db
          .customSelect('SELECT COUNT(*) AS c FROM sales_invoices')
          .getSingle();
      return row.read<int>('c');
    },
  );
});

final firstRunFinisherProvider =
    Provider<FirstRunFinisher>((ref) => defaultFinisher());
