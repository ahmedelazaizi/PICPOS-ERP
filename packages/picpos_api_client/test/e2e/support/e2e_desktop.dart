// دور «المكتب» في اختبارات E2E لتطبيق الإدارة: يملك مفتاح توقيع Ed25519
// حقيقيًا، يدفع المفتاح العام والمستخدمين واللقطات الموقّعة إلى السحابة، ويُصدر
// رموز الاقتران — تمامًا كما يفعل تطبيق المكتب. (نسخة مطابقة في mobile_admin.)
import 'package:picpos_api_client/picpos_api_client.dart';

import 'e2e_cloud.dart';

class E2eDesktop {
  E2eDesktop._(this.cloud, this.headers, this.signer, this.publicKey);

  final E2eCloud cloud;
  final Map<String, String> headers;
  final PayloadSigner signer;
  final String publicKey;

  static const defaultPassword = 'mobile-pass-1';

  /// يربط المكتب بشركة ويدفع مفتاح التوقيع.
  static Future<E2eDesktop> link(E2eCloud cloud,
      {String? company, List<int>? seed, int decimals = 3}) async {
    final headers = await cloud.desktopLink(company ?? cloud.companyA);
    final signer = await PayloadSigner.fromSeed(seed ?? PayloadSigner.newSeed());
    final pub = await signer.publicKeyBase64();
    final r = await cloud.call('POST', '/desktop/link/signing-key',
        headers: headers, body: {'publicKey': pub, 'decimals': decimals});
    if (r.status != 204) throw StateError('signing key: $r');
    return E2eDesktop._(cloud, headers, signer, pub);
  }

  /// مستخدم الجوال كما يدفعه المكتب (كلمة المرور تُشتق محليًا: PBKDF2).
  Future<Map<String, Object?>> userJson(String gid, String username,
      {String password = defaultPassword,
      bool enabled = true,
      List<String>? permissions,
      List<int> branchScope = const [],
      int version = 1}) async =>
      {
        'globalId': gid,
        'username': username,
        'displayName': 'User $username',
        'locale': 'ar',
        'mobileEnabled': enabled,
        'mobilePasswordHash': await hashMobilePassword(password, iterations: 1000),
        'permissions': permissions ??
            ['mobile_admin_access', 'dashboard_sales_today', 'dashboard_profit', 'treasury_view', 'sales_return_approve'],
        'branchScope': branchScope,
        'require2fa': false,
        'version': version,
      };

  Future<E2eResponse> pushUsers(List<Map<String, Object?>> users) =>
      cloud.call('POST', '/desktop/users', headers: headers, body: {'users': users});

  Future<Map<String, Object?>> signed(String kind, Map<String, Object?> data,
          {String scope = 'all', DateTime? asOf}) =>
      buildSignedSnapshot(signer, kind: kind, scope: scope, asOf: asOf ?? DateTime.now().toUtc(), data: data);

  Future<E2eResponse> pushSnapshots(List<Map<String, Object?>> items) =>
      cloud.call('POST', '/desktop/snapshots', headers: headers, body: {'items': items});

  Future<String> adminPairingCode(String userGid) async {
    final r = await cloud.call('POST', '/desktop/admin-pairing-codes', headers: headers, body: {'userGlobalId': userGid});
    if (r.status != 201) throw StateError('admin pairing code: $r');
    return r.json['code'] as String;
  }

  Future<List<Map<String, dynamic>>> adminDevices() async =>
      ((await cloud.call('GET', '/desktop/admin-devices', headers: headers)).json['devices'] as List).cast<Map<String, dynamic>>();

  Future<E2eResponse> revokeAdminDevice(String deviceId) =>
      cloud.call('POST', '/desktop/admin-devices/$deviceId/revoke', headers: headers);
}
