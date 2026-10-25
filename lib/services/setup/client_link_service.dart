// ربطُ العميل والمرآة بالخادم الرئيسيّ — منطقٌ منقولٌ حرفياً من
// `setup_wizard_screen.dart` (‏`_connectAndSync` و`_pairMirror` و`_progressLabel`،
// P0 من خطة إعادة تصميم الإعداد الأول).
//
// ⚠️ لا `setState` هنا. الخدمةُ تُرجع [ClientLinkResult] وتبثّ نصَّ التقدّم عبر
// `onProgress`، وتطلب تأكيدَ إعادة الربط من النداء (‏`confirmRePair`) بدل أن
// تفتح حواراً بنفسها.
library;

import '../../core/i18n/tr.dart';
import '../../data/database/database_barrel.dart';
import '../api/lan_pairing_client.dart';
import '../delta_pull_service.dart';
import '../deployment/mode_activator.dart';
import '../mirror_pairing_service.dart';
import '../network_service.dart';
import '../server_proxy.dart';
import '../sync/client_first_sync_service.dart';
import '../sync_service.dart';

enum ClientLinkOutcome {
  /// اتصالٌ ومزامنةٌ أولى ناجحان.
  connected,

  /// فشل اختبارُ الاتصال بالخادم.
  connectFailed,

  /// رفض المستخدمُ إعادةَ الربط (‏لا رسالة).
  cancelled,

  /// فشلت المزامنةُ الأولى.
  syncFailed,

  /// استثناءٌ غيرُ متوقَّع.
  error,

  /// المرآة: تحقّق المديرُ.
  paired,

  /// الإقرانُ برمز الجهاز ناجحٌ والخادمُ يردّ.
  devicePaired,

  /// رفض الخادمُ الرمزَ أو تعذّر الإقران.
  pairFailed,
}

class ClientLinkResult {
  const ClientLinkResult(
    this.outcome, {
    this.message,
    this.branches = const [],
  });

  final ClientLinkOutcome outcome;

  /// نصٌّ جاهزٌ للعرض (‏بإيموجي الحالة كما كان)، أو `null` عند الإلغاء.
  final String? message;

  /// الفروعُ المزامَنة (‏عند [ClientLinkOutcome.connected] فقط).
  final List<Branche> branches;

  bool get ok =>
      outcome == ClientLinkOutcome.connected ||
      outcome == ClientLinkOutcome.paired ||
      outcome == ClientLinkOutcome.devicePaired;
}

/// ما يحتاجه المعالجُ من خدمة الربط — واجهةٌ تُحقن بنسخةٍ مزيّفة في الاختبار.
abstract interface class ClientLinkPort {
  /// إقرانُ الجهاز برمز الخادم (‏8 أحرف) ثم فحصُ وصوله. لا تغيير نمطٍ ولا مزامنة.
  Future<ClientLinkResult> pairDevice({
    required String address,
    required int port,
    required String code,
    String? deviceName,
  });

  /// تعيين النمط client ثم المزامنة الأولى (تُمسح البيانات المزروعة قبلها).
  Future<ClientLinkResult> connectAndSync({
    required String address,
    required int port,
    required Future<bool> Function() confirmRePair,
    void Function(String message)? onProgress,
    bool mirror = false,
  });

  /// A1/M1: mirror pairing by the one-time CODE the administrator issued for
  /// kind mirror (per-device token; no shared key, no admin login). The legacy
  /// admin-credentials handshake is no longer part of the first-run flow.
  Future<ClientLinkResult> pairMirrorWithCode({
    required String host,
    required int port,
    required String code,
    String? deviceName,
  });
}

class ClientLinkService implements ClientLinkPort {
  ClientLinkService({
    required this.db,
    required this.loadBranches,
    NetworkService? network,
  }) : _network = network ?? NetworkService.instance;

  final AppDatabase db;
  final Future<List<Branche>> Function() loadBranches;
  final NetworkService _network;

  /// وسمُ مرحلة المزامنة الأولى للعرض.
  static String progressLabel(String stage) {
    switch (stage) {
      case 'wipe':
        return tr('تجهيز قاعدة البيانات');
      case 'sync':
        return tr('مزامنة الجداول');
      case 'finalize':
        return tr('الانتهاء');
      default:
        return stage;
    }
  }

  @override
  Future<ClientLinkResult> pairDevice({
    required String address,
    required int port,
    required String code,
    String? deviceName,
  }) async {
    try {
      // A1: a branch device states its kind, so a MIRROR code is refused (the
      // chosen path decides the mode, never the code). `client` first, then
      // `pos` (a kind mismatch does not burn the one-time code).
      var paired = await LanPairingClient.pair(
          address: address,
          port: port,
          code: code,
          deviceName: deviceName,
          deviceKind: 'client');
      var kind = 'client';
      if (paired['success'] != true &&
          '${paired['error']}'.contains('النوع')) {
        paired = await LanPairingClient.pair(
            address: address,
            port: port,
            code: code,
            deviceName: deviceName,
            deviceKind: 'pos');
        kind = 'pos';
      }
      if (paired['success'] == true) {
        ActivationHints.deviceKind = '${paired['deviceKind'] ?? kind}';
      }
      if (paired['success'] != true) {
        return ClientLinkResult(
          ClientLinkOutcome.pairFailed,
          message: tr('❌ تعذّر إقران الجهاز: {p0}', {'p0': paired['error']}),
        );
      }
      final probe = await _network.testServerConnection(address, port);
      if (probe['success'] != true) {
        return ClientLinkResult(
          ClientLinkOutcome.connectFailed,
          message: tr('❌ فشل الاتصال بالسيرفر: {p0}', {'p0': probe['error']}),
        );
      }
      return ClientLinkResult(
        ClientLinkOutcome.devicePaired,
        message: tr('✅ تم إقران الجهاز بالسيرفر الرئيسي'),
      );
    } catch (e) {
      return ClientLinkResult(
        ClientLinkOutcome.error,
        message: tr('❌ خطأ: {e}', {'e': e}),
      );
    }
  }

  @override
  Future<ClientLinkResult> connectAndSync({
    required String address,
    required int port,
    required Future<bool> Function() confirmRePair,
    void Function(String message)? onProgress,
    bool mirror = false,
  }) async {
    try {
      final ns = _network;

      // The server address first (saveSettings keeps it). A1: NO DB write of
      // `network_mode` here - the mode is committed only by ModeActivator at the
      // end; a branch device behaves as a client in memory for the first sync.
      ns.setServerAddress(address, port: port);
      if (!mirror) await ns.setMode(NetworkMode.client);
      await ns.saveSettings();

      // اختبارُ الاتصال أوّلاً (‏يستخرج رمزَ الـAPI من نقطة الصحّة).
      final testResult = await ns.testServerConnection(address, port);
      if (testResult['success'] != true) {
        return ClientLinkResult(
          ClientLinkOutcome.connectFailed,
          message: tr('❌ فشل الاتصال بالسيرفر: {p0}',
              {'p0': testResult['error']}),
        );
      }

      final serverUrl = ns.buildServerUrl(address: address, port: port);
      final syncService = SyncService(serverUrl: serverUrl, localDb: db);

      // Spec 001: بذرُ القاعدة المحلّية جرى قبل معرفة النمط — تُمسح صفوفُها
      // الرئيسيّة قبل السحب. وجهازٌ مقترنٌ سلفاً يطلب تأكيداً صريحاً.
      final firstSyncService =
          mirror ? ClientFirstSyncService.mirror(db: db) : ClientFirstSyncService(db: db);
      final pending = await firstSyncService.isFirstSyncPending();
      if (!pending) {
        if (!await confirmRePair()) {
          return const ClientLinkResult(ClientLinkOutcome.cancelled);
        }
        await firstSyncService.reset();
      }

      final FirstSyncResult firstSyncResult;
      try {
        firstSyncResult = await firstSyncService.performFirstSync(
          syncService: syncService,
          onProgress: (stage) =>
              onProgress?.call('⏳ ${progressLabel(stage)}…'),
        );
      } on FirstSyncException catch (e) {
        return ClientLinkResult(
          ClientLinkOutcome.syncFailed,
          message: tr('⚠️ فشلت المزامنة: {p0}', {'p0': e.message}),
        );
      }

      // بذرُ العلامات المائيّة بساعة الخادم (‏لا ساعة عميلٍ قد تسبقه فتُفلت
      // صفوفٌ في نافذة الانحراف).
      final serverSec = await ServerProxy.instance.fetchServerTime();
      final seedSec = serverSec ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 60;
      await DeltaPullService.instance.seedWatermarks(seedSec);

      final branches = await loadBranches();
      final warningSuffix = firstSyncResult.warningCount > 0
          ? tr(' ({p0} تحذير)', {'p0': firstSyncResult.warningCount})
          : '';
      return ClientLinkResult(
        ClientLinkOutcome.connected,
        branches: branches,
        message: tr('✅ تم الاتصال والمزامنة — {p0} جدول{warningSuffix}', {
          'p0': firstSyncResult.tablesSynced,
          'warningSuffix': warningSuffix,
        }),
      );
    } catch (e) {
      return ClientLinkResult(
        ClientLinkOutcome.error,
        message: tr('❌ خطأ: {e}', {'e': e}),
      );
    }
  }

  @override
  Future<ClientLinkResult> pairMirrorWithCode({
    required String host,
    required int port,
    required String code,
    String? deviceName,
  }) async {
    try {
      final result = await MirrorPairingService.instance.pairWithCode(
        host: host,
        port: port,
        code: code,
        deviceName: deviceName,
      );
      if (!result.isSuccess) {
        final icon = result.outcome == MirrorPairingOutcome.missingFields
            ? '⚠️'
            : '❌';
        return ClientLinkResult(
          ClientLinkOutcome.pairFailed,
          message: '$icon ${result.message}',
        );
      }
      ActivationHints.deviceKind = 'mirror';
      return ClientLinkResult(
        ClientLinkOutcome.paired,
        message: tr(
            '✅ تم إقران الجهاز بالسيرفر الرئيسي كمرآة — سيتم تفعيل وضع المرآة عند إنهاء المعالج'),
      );
    } catch (e) {
      return ClientLinkResult(
        ClientLinkOutcome.error,
        message: tr('❌ خطأ: {e}', {'e': e}),
      );
    }
  }

}
