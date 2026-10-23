// م3-0 — قياس زمن drift remote لقراءات الويب (لا يفشل على الزمن).
//
// يقارن استعلاماً تجميعيّاً (ميزان مراجعة / مجموع قيود) على قاعدة اصطناعية
// كبيرة نسبيّاً عبر ثلاثة مسارات:
//   1) مباشر على المنفِّذ،
//   2) drift remote عبر قناة محلّية (StreamChannelController) بلا JSON،
//   3) drift remote عبر WebSocket حقيقيّ على localhost بقناة JSON.
// الأرقام تُطبع؛ الاختبار يتحقّق فقط من تطابق النتائج.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
// ignore: experimental_member_use
import 'package:drift/remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:picpos_erp/services/web_read/drift_json_channel.dart';
import 'package:picpos_erp/services/web_read/web_read_policy_interceptor.dart';
import 'package:web_socket_channel/io.dart';

const int _lines = 60000; // سطور قيود
const int _accounts = 300;
const int _runs = 20;

class _User extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

class _RawDb extends GeneratedDatabase {
  _RawDb(super.connection) : super.connect();

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  int get schemaVersion => 1;
}

class _Stats {
  _Stats(this.name, List<Duration> d, this.cold)
    : sorted = ([...d]..sort()).map((e) => e.inMicroseconds / 1000).toList();

  final String name;
  final Duration cold;
  final List<double> sorted;

  double get median => sorted[sorted.length ~/ 2];
  double get p95 => sorted[((sorted.length - 1) * 0.95).round()];
  double get min => sorted.first;

  @override
  String toString() =>
      '${name.padRight(26)} cold=${_ms(cold)}  '
      'min=${min.toStringAsFixed(2)}  median=${median.toStringAsFixed(2)}  '
      'p95=${p95.toStringAsFixed(2)} ms';

  static String _ms(Duration d) =>
      '${(d.inMicroseconds / 1000).toStringAsFixed(2)}ms';
}

Future<_Stats> _measure(String name, Future<Object?> Function() action) async {
  final sw = Stopwatch()..start();
  await action();
  final cold = sw.elapsed;
  final times = <Duration>[];
  for (var i = 0; i < _runs; i++) {
    sw
      ..reset()
      ..start();
    await action();
    times.add(sw.elapsed);
  }
  return _Stats(name, times, cold);
}

void main() {
  test(
    'قياس زمن الاستعلام التجميعي: مباشر / قناة محلية / WebSocket',
    () async {
      // ثلاثة عملاء فوق منفِّذ واحد عن قصد (قراءة فقط) — نكتم التحذير.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final raw = NativeDatabase.memory();
      await raw.ensureOpen(_User());
      await raw.runCustom(
        'create table journal_entry_lines (id integer primary key, '
        'entry_id integer, account_id integer, debit real, credit real, '
        'memo text)',
        const [],
      );
      await raw.runCustom(
        'create index idx_jel_account on journal_entry_lines(account_id)',
        const [],
      );
      final stmts = BatchedStatements(
        [
          'insert into journal_entry_lines (entry_id, account_id, debit, credit, memo) '
              'values (?,?,?,?,?)',
        ],
        [
          for (var i = 0; i < _lines; i++)
            ArgumentsForBatchedStatement(0, [
              i ~/ 2,
              i % _accounts,
              i.isEven ? (i % 977) + 0.25 : 0.0,
              i.isOdd ? ((i - 1) % 977) + 0.25 : 0.0,
              'قيد رقم $i',
            ]),
        ],
      );
      final seedWatch = Stopwatch()..start();
      await raw.runBatched(stmts);
      final seedMs = seedWatch.elapsedMilliseconds;

      const trialBalance =
          'select account_id, sum(debit) as d, sum(credit) as c, count(*) as n '
          'from journal_entry_lines group by account_id order by account_id';
      const totals =
          'select sum(debit) as d, sum(credit) as c, count(*) as n '
          'from journal_entry_lines';
      const wide =
          'select id, entry_id, account_id, debit, credit, memo '
          'from journal_entry_lines where id <= 5000';

      // ① مباشر
      final direct = _RawDb(DatabaseConnection(raw));

      // ② قناة محلية (بلا JSON)
      final allowed = {'journal_entry_lines'};
      final localServer = createWebReadDriftServer(raw, allowedTables: allowed);
      final local = StreamChannelController<Object?>();
      localServer.serve(local.local);
      final viaLocal = _RawDb(
        DatabaseConnection.delayed(connectToRemoteAndInitialize(local.foreign)),
      );

      // ③ WebSocket حقيقيّ + JSON
      final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final wsServer = createWebReadDriftServer(raw, allowedTables: allowed);
      final serverSub = http.listen((req) async {
        final ws = await WebSocketTransformer.upgrade(req);
        wsServer.serve(driftJsonChannel(IOWebSocketChannel(ws)));
      });
      final viaWs = _RawDb(
        DatabaseConnection.delayed(
          connectToRemoteAndInitialize(
            driftJsonChannel(
              IOWebSocketChannel.connect('ws://127.0.0.1:${http.port}/'),
            ),
          ),
        ),
      );

      Future<List<QueryRow>> q(_RawDb db, String sql) =>
          db.customSelect(sql).get();

      // تطابق النتائج أوّلاً.
      final expected = (await q(
        direct,
        trialBalance,
      )).map((r) => r.data).toList();
      expect(expected.length, _accounts);
      expect(
        (await q(viaLocal, trialBalance)).map((r) => r.data).toList(),
        expected,
      );
      expect(
        (await q(viaWs, trialBalance)).map((r) => r.data).toList(),
        expected,
      );
      final expectedTotals = (await q(direct, totals)).single.data;
      expect((await q(viaWs, totals)).single.data, expectedTotals);

      final results = <_Stats>[];
      for (final (label, sql) in [
        ('ميزان مراجعة ($_accounts صفاً)', trialBalance),
        ('مجموع القيود (صف واحد)', totals),
        ('5000 سطر خام', wide),
      ]) {
        results
          ..add(await _measure('[مباشر] $label', () => q(direct, sql)))
          ..add(await _measure('[محلية] $label', () => q(viaLocal, sql)))
          ..add(await _measure('[WebSocket] $label', () => q(viaWs, sql)));
      }

      // ignore: avoid_print
      print(
        '═══ drift remote latency — $_lines سطر، $_accounts حساباً، '
        'seed=${seedMs}ms، $_runs تكراراً (ms) ═══',
      );
      for (final r in results) {
        // ignore: avoid_print
        print(r);
      }

      await viaWs.close();
      await viaLocal.close();
      await serverSub.cancel();
      await http.close(force: true);
      await localServer.shutdown();
      await wsServer.shutdown();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}


