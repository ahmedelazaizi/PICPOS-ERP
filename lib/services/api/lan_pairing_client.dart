import 'dart:convert';
import 'dart:io';

import '../device_identity_service.dart';
import '../server_proxy.dart';
import '../secure_storage_service.dart';
import '../tls_trust.dart';
import '../../core/config/brand.dart';
import '../../core/utils/uuid_v7.dart';

/// Client-side pairing handshake and device-header source of truth.
class LanPairingClient {
  static const deviceNameKey = 'ural_lan_device_name';

  static Map<String, String> deviceHeaders() {
    final id = DeviceIdentityService.instance.tryGetDeviceId();
    return {
      if (id != null && id.isNotEmpty) 'X-Device-Id': id,
      'X-Device-Name': _deviceName(),
    };
  }

  static String _deviceName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'جهاز LAN';
    }
  }

  static Future<Map<String, dynamic>> pair({
    required String address,
    required int port,
    required String code,
    String? deviceName,
  }) async {
    final id = await _deviceId();
    final name = deviceName?.trim().isNotEmpty == true
        ? deviceName!.trim()
        : _deviceName();
    final base = _baseUrl(address, port);
    final uri = Uri.parse('$base/api/pair');
    final client = TlsTrust.ioClient(connectionTimeout: const Duration(seconds: 15));
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set('User-Agent', '${Brand.name}-Client');
      request.headers.set('X-Device-Id', id);
      request.headers.set('X-Device-Name', name);
      request.write(jsonEncode({
        'pairingCode': code.trim().toUpperCase(),
        'deviceId': id,
        'deviceName': name,
      }));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final data = body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          'success': false,
          'error': data['error'] ?? 'فشل إقران الجهاز (${response.statusCode})',
        };
      }
      final token = data['token'] as String?;
      if (token == null || token.isEmpty) {
        return {'success': false, 'error': 'لم يُرجع الخادم توكن الجهاز'};
      }
      DeviceIdentityService.instance.adoptForPairing(id);
      ServerProxy.instance.setApiToken(token);
      return {'success': true, 'deviceId': id};
    } catch (error) {
      return {'success': false, 'error': 'تعذّر الاتصال بالخادم: $error'};
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _deviceId() async {
    final existing = DeviceIdentityService.instance.tryGetDeviceId();
    if (existing != null && existing.isNotEmpty) return existing;
    final storage = SecureStorageService();
    const key = 'device_id';
    final stored = await storage.read(key);
    if (stored != null && stored.isNotEmpty) return stored;
    final generated = UuidV7.generate();
    try {
      await storage.write(key, generated);
    } catch (_) {}
    return generated;
  }

  static String _baseUrl(String address, int port) {
    final trimmed = address.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed.endsWith('/')
          ? trimmed.substring(0, trimmed.length - 1)
          : trimmed;
    }
    return 'http://$trimmed:$port';
  }
}
