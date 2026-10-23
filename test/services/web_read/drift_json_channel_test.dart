
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
// ignore: experimental_member_use
import 'package:drift/remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/web_read/drift_json_channel.dart';

/// قاعدة خفيفة تعيد استخدام جدول `settings` الحقيقي بلا إقلاع AppDatabase.
class _ProbeDb extends GeneratedDatabase {
  _ProbeDb(super.connection) : super.connect();

  late final $SettingsTable settingsTable = $SettingsTable(this);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => [settingsTable];

  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => [settingsTable];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (m) => m.createAll());
}

void main() {
  group('ترميز JSON', () {
    Object? roundTrip(Object? v) => decodeDriftMessage(encodeDriftMessage(v));

    test('رحلة ذهاب وعودة بلا فقد للأنواع الخاصة', () {
      final bytes = Uint8List.fromList(List.generate(256, (i) => i));
      final big = BigInt.parse('123456789012345678901234567890');
      final utc = DateTime.utc(2026, 5, 17, 13, 45, 12, 123, 456);
      final local = DateTime(2026, 1, 2, 3, 4, 5, 6, 7);
      final message = <Object?>[
        0,
        7,
        [
          3,
          'select ? from "t"',
          [bytes, big, utc, local, 1 << 60, -(1 << 62), 1.5, null, true, 'ع'],
          Uint8List(0),
        ],
        {
          'a': [1, 2],
          'nested': {'x': bytes},
        },
      ];

      final back = roundTrip(message)! as List;
      expect(back[0], 0);
      expect(back[1], 7);
      final inner = back[2] as List;
      final args = inner[2] as List;
      expect(args[0], isA<Uint8List>());
      expect(args[0], bytes);
      expect(args[1], big);
      expect(args[2], utc);
      expect((args[2] as DateTime).isUtc, isTrue);
      expect(args[3], local);
      expect((args[3] as DateTime).isUtc, isFalse);
      expect(args[4], 1 << 60);
      expect(args[5], -(1 << 62));
      expect(args[6], 1.5);
      expect(args[7], isNull);
      expect(args[8], true);
      expect(args[9], 'ع');
      expect(inner[3], isA<Uint8List>());
      expect(inner[3], isEmpty);
      final map = back[3] as Map;
      expect(map['a'], [1, 2]);
      expect((map['nested'] as Map)['x'], bytes);
    });

    test('NaN وInfinity تعبران', () {
      final back =
          roundTrip([double.nan, double.infinity, double.negativeInfinity])
              as List;
      expect((back[0] as double).isNaN, isTrue);
      expect(back[1], double.infinity);
      expect(back[2], double.negativeInfinity);
    });

    test('خريطة مفاتيحها تشبه الوسوم لا تُفكّ وسماً', () {
      final tricky = {r'$u8': 'AAAA', r'$big': '1'};
      expect(roundTrip(tricky), tricky);
      final single = {r'$u8': 'not-base64-but-data'};
      expect(roundTrip(single), single);
    });

    test('وسم مجهول أو نوع غير مدعوم يفشل صراحةً', () {
      expect(() => decodeDriftMessage('{"\$zz": 1}'), throwsFormatException);
      expect(() => encodeDriftMessage(Object()), throwsArgumentError);
      expect(() => encodeDriftMessage({1: 2}), throwsArgumentError);
    });
  });

  group('القناة', () {
    test('رسائل كائنات تعبر قناة نصوص بلا فقد', () async {
      final controller = StreamChannelController<String>();
      final a = driftJsonChannel(controller.local);
      final b = driftJsonChannel(controller.foreign);

      final bytes = Uint8List.fromList([0, 1, 2, 255]);
      final received = b.stream.first;
      a.sink.add([1, bytes, BigInt.two]);
      final got = await received as List;
      expect(got[1], bytes);
      expect(got[2], BigInt.two);

      final back = a.stream.first;
      b.sink.add({'ok': DateTime.utc(2020)});
      expect(await back, {'ok': DateTime.utc(2020)});
      await a.sink.close();
    });
  });

  group('drift remote عبر قناة JSON', () {
    test(
      'استعلام watch() يُحدَّث عبر القناة',
      () async {
        final serverDb = NativeDatabase.memory();
        final server = DriftServer(
          serverDb,
          closeConnectionAfterShutdown: false,
        );
        final controller = StreamChannelController<String>();
        server.serve(driftJsonChannel(controller.local));

        final connection = DatabaseConnection.delayed(
          connectToRemoteAndInitialize(driftJsonChannel(controller.foreign)),
        );
        final db = _ProbeDb(connection);

        final seen = <List<String>>[];
        final sub = db
            .select(db.settingsTable)
            .watch()
            .map((rows) => rows.map((r) => r.key).toList()..sort())
            .listen(seen.add);

        // الانتظار حتى يصل أول بثّ (يشمل بناء المخطّط عبر القناة).
        await _until(() => seen.isNotEmpty);
        final before = seen.last;

        await db
            .into(db.settingsTable)
            .insert(
              SettingsCompanion.insert(
                key: 'web_probe_key',
                value: const Value('v'),
              ),
            );
        await _until(() => seen.last.contains('web_probe_key'));
        expect(seen.last.length, before.length + 1);

        await sub.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await db.close();
        await server.shutdown();
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

Future<void> _until(bool Function() cond) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) fail('انتهت مهلة انتظار الشرط');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

