// مزوّدو الإعداد الأول — كلُّهم قابلٌ للاستبدال في الاختبار.
library;

import 'dart:async';
import 'dart:io' show InternetAddressType, NetworkInterface;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/providers.dart';
import '../../../services/setup/branch_account_verifier.dart';
import '../../../services/setup/client_link_service.dart';
import '../../../services/setup/first_run_storage_probe.dart';
import '../../../services/setup/first_user_verifier.dart';
import '../../../services/setup/main_auth_port.dart';
import '../../../services/setup/server_provisioning_service.dart';
import '../../../services/setup/server_setup_writer.dart';
import '../setup_wizard/setup_persistence_riverpod.dart';
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

final firstRunFinisherProvider = Provider<FirstRunFinisher>((ref) =>
    defaultFinisher(
      writer: ref.read(serverSetupWriterProvider),
      provisioning: ref.read(serverProvisioningServiceProvider),
    ));

/// تهيئةُ PostgreSQL (‏اختبار · مخطّط · زرع · تحقّق) — تُستبدل بمزيّفٍ في الاختبار.
final serverProvisioningServiceProvider =
    Provider<ServerProvisioningService>((ref) => ServerProvisioningService());

/// كاتبُ بيانات المقرّ في قاعدة الخادم (‏معاملة واحدة).
final serverSetupWriterProvider =
    Provider<ServerSetupWriter>((ref) => ServerSetupWriter());

/// ربطُ الفرع/المرآة بالخادم الرئيسيّ.
final clientLinkPortProvider = Provider<ClientLinkPort>((ref) {
  return ClientLinkService(
    db: ref.read(databaseProvider),
    loadBranches: () => ref.read(branchRepositoryProvider).getAllBranches(),
  );
});

/// نداءاتُ المصادقة على الرئيسيّ بتوكن هذا الجهاز نفسه (‏بلا مفتاح مشترك).
final mainAuthPortProvider =
    Provider.autoDispose<MainAuthPort>((ref) => HttpMainAuthPort.fromRuntime());

/// A1/P4: أوّلُ مستخدمٍ يُتحقَّق منه **على الرئيسي**، ثم تُسلَّم اعتماداتُ فرعه
/// ويُسحب `admin/admin` المزروع.
final branchAccountVerifierProvider =
    Provider.autoDispose<BranchAccountVerifierPort>((ref) {
  return FirstUserVerifier(
    db: ref.read(databaseProvider),
    port: ref.read(mainAuthPortProvider),
    permissionCodes: ref.read(authRepositoryProvider).getUserPermissionCodes,
    saveClientBranchId: ref.read(setupPersistenceProvider).saveClientBranchId,
  );
});

/// دورٌ يصلح لمستخدم فرع (‏بلا «مدير النظام»: المسؤول الأول وحده).
class FirstRunRoleOption {
  const FirstRunRoleOption(this.id, this.name);
  final int id;
  final String name;
}

/// الأدوارُ المزروعة محليّاً — تُحلّ في الخادم بالاسم عند الكتابة.
final firstRunRolesProvider = FutureProvider<List<FirstRunRoleOption>>((ref) async {
  final roles = await ref.read(authRepositoryProvider).getAllRoles();
  return [
    for (final r in roles)
      if (r.name != 'مدير النظام') FirstRunRoleOption(r.id, r.name),
  ];
});

/// عناوينُ IPv4 لهذا الجهاز (‏غير loopback) لعرضها في صفحة نجاح المقرّ.
final firstRunLocalAddressesProvider = FutureProvider<List<String>>((ref) async {
  try {
    final ifaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return [
      for (final i in ifaces)
        for (final a in i.addresses) a.address,
    ];
  } catch (_) {
    return const [];
  }
});
