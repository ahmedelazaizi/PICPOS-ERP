// SYNC-004 — host-side phone dedupe: the same customer created on two offline
// terminals (different globalIds, differently formatted phones) is adopted, not
// duplicated; a shared phone with another name is flagged for the owner.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';

void main() {
  late AppDatabase db;
  late ApiHandler handler;
  late int seeded; // the seeded database already holds default parties

  setUp(() async {
    db = AppDatabase.forTesting();
    handler = ApiHandler(db);
    seeded = (await db.select(db.parties).get()).length;
  });

  Future<Map<String, dynamic>> post(Map<String, Object?> body) async {
    final resp = await handler.buildRouter().call(shelf.Request(
      'POST',
      Uri.parse('http://localhost/api/parties'),
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
      context: {ApiUserCtx.userIdKey: 1},
    ));
    final text = await resp.readAsString();
    expect(resp.statusCode, 200, reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<int> count() async => (await db.select(db.parties).get()).length;

  test('same person, different phone formatting + different globalId -> ONE party', () async {
    final a = await post({'name': 'أحمد علي', 'phone': '+20 101 234 5678', 'globalId': 'gid-term-1'});
    final b = await post({'name': 'أحمد  علي', 'phone': '01012345678', 'globalId': 'gid-term-2'});
    expect(b['serverId'], a['serverId']);
    expect(await count(), seeded + 1);
  });

  test('Arabic-Indic digits are normalised too', () async {
    final a = await post({'name': 'سارة', 'phone': '01012345678', 'globalId': 'g1'});
    final b = await post({'name': 'سارة', 'phone': '٠١٠١٢٣٤٥٦٧٨', 'globalId': 'g2'});
    expect(b['serverId'], a['serverId']);
    expect(await count(), seeded + 1);
  });

  test('same phone but another name is NOT merged; it is recorded as a suspect', () async {
    final a = await post({'name': 'محمود', 'phone': '01012345678', 'globalId': 'g1'});
    final b = await post({'name': 'محمد', 'phone': '+201012345678', 'globalId': 'g2'});
    expect(b['serverId'], isNot(a['serverId']));
    expect(await count(), seeded + 2);
    final rows = await db.customSelect(
        'SELECT reason, existing_party_id, new_party_id FROM party_dedup_suspects').get();
    expect(rows, hasLength(1));
    expect(rows.single.data['reason'], 'same_phone_different_name');
    expect(rows.single.data['existing_party_id'], a['serverId']);
    expect(rows.single.data['new_party_id'], b['serverId']);
  });

  test('the normalised match is role-aware: a supplier is never folded into a customer', () async {
    final c = await post({'name': 'شركة النور', 'phone': '01012345678', 'globalId': 'g1'});
    final s = await post({'name': 'شركة النور', 'phone': '+20 101 234 5678', 'globalId': 'g2', 'isSupplier': true, 'isCustomer': false});
    expect(s['serverId'], isNot(c['serverId']));
  });

  test('different phones never merge', () async {
    await post({'name': 'علاء', 'phone': '01012345678', 'globalId': 'g1'});
    await post({'name': 'علاء', 'phone': '01112345678', 'globalId': 'g2'});
    expect(await count(), seeded + 2);
  });
}
