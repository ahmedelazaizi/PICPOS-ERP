import 'dart:convert';
import 'dart:io';

import '../db/database.dart';

class WhatsAppSendResult {
  WhatsAppSendResult.ok(this.providerMessageId) : error = null;
  WhatsAppSendResult.failed(this.error) : providerMessageId = null;
  final String? providerMessageId;
  final String? error;
  bool get ok => error == null;
}

/// Provider abstraction. Templates must be pre-approved by Meta (AR + EN).
abstract class WhatsAppProvider {
  String get name;
  Future<WhatsAppSendResult> sendTemplate({
    required String toPhone,
    required String template,
    required String language,
    required List<String> params,
  });
}

class SentMockMessage {
  SentMockMessage(this.toPhone, this.template, this.language, this.params, this.id);
  final String toPhone, template, language, id;
  final List<String> params;
}

/// TEST MODE provider: records messages in memory and logs them. Can be told
/// to fail the next N sends to exercise retries.
class MockWhatsAppProvider implements WhatsAppProvider {
  final List<SentMockMessage> sent = [];
  int failNext = 0;
  int _seq = 0;

  @override
  String get name => 'mock';

  @override
  Future<WhatsAppSendResult> sendTemplate({
    required String toPhone,
    required String template,
    required String language,
    required List<String> params,
  }) async {
    if (failNext > 0) {
      failNext--;
      return WhatsAppSendResult.failed('mock: simulated failure');
    }
    final id = 'mock-${++_seq}';
    sent.add(SentMockMessage(toPhone, template, language, params, id));
    stdout.writeln('[whatsapp:mock] $template/$language -> $toPhone $params ($id)');
    return WhatsAppSendResult.ok(id);
  }
}

/// Meta WhatsApp Cloud API provider — STUB. Builds the Graph API payload for
/// `POST https://graph.facebook.com/v20.0/{phoneNumberId}/messages` but does not
/// send until the owner's Meta account is approved (I-5).
class MetaCloudWhatsAppProvider implements WhatsAppProvider {
  MetaCloudWhatsAppProvider({required this.phoneNumberId, required this.accessToken});
  final String phoneNumberId;
  final String accessToken;

  @override
  String get name => 'meta';

  Map<String, Object?> buildPayload(
          String toPhone, String template, String language, List<String> params) =>
      {
        'messaging_product': 'whatsapp',
        'to': toPhone.replaceAll('+', ''),
        'type': 'template',
        'template': {
          'name': template,
          'language': {'code': language},
          'components': [
            {
              'type': 'body',
              'parameters': [
                for (final p in params) {'type': 'text', 'text': p},
              ],
            },
          ],
        },
      };

  @override
  Future<WhatsAppSendResult> sendTemplate({
    required String toPhone,
    required String template,
    required String language,
    required List<String> params,
  }) async {
    jsonEncode(buildPayload(toPhone, template, language, params));
    return WhatsAppSendResult.failed('meta provider not enabled (I-5)');
  }
}

WhatsAppProvider providerFromEnv(Map<String, String> env) {
  if (env['WHATSAPP_PROVIDER'] == 'meta') {
    return MetaCloudWhatsAppProvider(
      phoneNumberId: env['WHATSAPP_PHONE_NUMBER_ID'] ?? '',
      accessToken: env['WHATSAPP_TOKEN'] ?? '',
    );
  }
  return MockWhatsAppProvider();
}

/// Outbox processing (enqueue happens inside the push transaction).
class WhatsAppOutbox {
  WhatsAppOutbox(this.db, this.provider);
  final CloudDatabase db;
  final WhatsAppProvider provider;

  static const backoffMs = [60000, 300000, 1800000, 7200000, 43200000];
  static const maxAttempts = 5;

  /// Sends due messages once; returns number processed. A periodic timer in
  /// bin/server.dart calls this (I-1: single worker).
  Future<int> processDue({int limit = 20}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.tx((s) async {
      final rows = await db.q(s, '''
        SELECT id, to_phone, template, language, params, attempts
        FROM whatsapp_outbox
        WHERE status = 'queued' AND next_attempt_at <= @now
        ORDER BY id LIMIT @lim FOR UPDATE SKIP LOCKED''', {'now': now, 'lim': limit});
      for (final r in rows) {
        final m = r.toColumnMap();
        final res = await provider.sendTemplate(
          toPhone: m['to_phone'] as String,
          template: m['template'] as String,
          language: m['language'] as String,
          params: (jsonDecode(m['params'] as String) as List).cast<String>(),
        );
        final attempts = (m['attempts'] as int) + 1;
        if (res.ok) {
          await db.q(s, "UPDATE whatsapp_outbox SET status='sent', attempts=@a, "
              'provider_message_id=@p, last_error=NULL WHERE id=@id',
              {'a': attempts, 'p': res.providerMessageId, 'id': m['id']});
        } else {
          final dead = attempts >= maxAttempts;
          await db.q(s, 'UPDATE whatsapp_outbox SET status=@st, attempts=@a, '
              'last_error=@e, next_attempt_at=@n WHERE id=@id', {
            'st': dead ? 'dead' : 'queued',
            'a': attempts,
            'e': res.error,
            'n': now + backoffMs[(attempts - 1).clamp(0, backoffMs.length - 1)],
            'id': m['id'],
          });
        }
      }
      return rows.length;
    });
  }
}
