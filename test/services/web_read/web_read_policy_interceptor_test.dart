import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
// ignore: experimental_member_use
import 'package:drift/remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:ural_erp/services/web_read/drift_json_channel.dart';
import 'package:ural_erp/services/web_read/web_read_policy_interceptor.dart';

class _User extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

/// قاعدة بلا جداول مُعرَّفة؛ نُرسل إليها SQL خاماً فقط.
class _RawDb extends GeneratedDatabase {
  _RawDb(super.connection) : super.connect();

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  int get schemaVersion => 1;
}

Future<QueryExecutor> _seeded() async {
  final raw = NativeDatabase.memory();
  await raw.ensureOpen(_User());
  for (final s in [
    'create table users (id integer primary key, username text, '
        'password_hash text, password_salt text, pin text, card_code text)',
    'create table products (id integer primary key, name text)',
    'create table sales_invoices (id integer primary key, total real)',
    'create table hr_secret (id integer primary key, v text)',
    'create table settings (key text primary key, value text)',
    'create table e_invoice_configs (id integer primary key, '
        'client_id text, client_secret text)',
    'create table api_keys (id integer primary key, name text, key_hash text)',
    "insert into users values (1,'ali','h','s','1234','c1')",
    "insert into products values (1,'tea'),(2,'cof')",
    'insert into sales_invoices values (1, 10.5)',
    "insert into hr_secret values (1,'x')",
    "insert into settings values ('currency','EGP'),"
        "('settings_access_password','topsecret')",
    "insert into e_invoice_configs values (1,'cid','shh')",
    "insert into api_keys values (1,'k','hashhash')",
  ]) {
    await raw.runCustom(s, const []);
  }
  return raw;
}

const _allowed = {
  'users',
  'products',
  'sales_invoices',
  'settings',
  'e_invoice_configs',
  'api_keys',
};

void main() {
  late QueryExecutor raw;
  late QueryExecutor guarded;

  setUp(() async {
    raw = await _seeded();
    guarded = raw.interceptWith(
      WebReadPolicyInterceptor(allowedTables: _allowed),
    );
  });

  Future<void> expectRejected(String sql) => expectLater(
    guarded.runSelect(sql, const []),
    throwsA(isA<WebReadPolicyViolation>()),
    reason: sql,
  );

  group('الكتابة والمعاملات مرفوضة', () {
    test('insert/update/delete/custom/batched', () async {
      await expectLater(
        guarded.runInsert("insert into products values (9,'x')", const []),
        throwsA(isA<WebReadPolicyViolation>()),
      );
      await expectLater(
        guarded.runUpdate("update products set name='z'", const []),
        throwsA(isA<WebReadPolicyViolation>()),
      );
      await expectLater(
        guarded.runDelete('delete from products', const []),
        throwsA(isA<WebReadPolicyViolation>()),
      );
      await expectLater(
        guarded.runCustom('drop table products', const []),
        throwsA(isA<WebReadPolicyViolation>()),
      );
      await expectLater(
        guarded.runBatched(
          BatchedStatements(
            ['delete from products'],
            [ArgumentsForBatchedStatement(0, [])],
          ),
        ),
        throwsA(isA<WebReadPolicyViolation>()),
      );
      final n = await raw.runSelect('select count(*) c from products', []);
      expect(n.single['c'], 2, reason: 'لم يتغيّر شيء في القاعدة');
    });

    test('beginTransaction وbeginExclusive', () {
      expect(
        () => guarded.beginTransaction(),
        throwsA(isA<WebReadPolicyViolation>()),
      );
      expect(
        () => guarded.beginExclusive(),
        throwsA(isA<WebReadPolicyViolation>()),
      );
    });

    test('close لا يغلق القاعدة المشتركة', () async {
      await guarded.close();
      final r = await raw.runSelect('select 1 as one', []);
      expect(r.single['one'], 1);
    });
  });

  group('قبول SELECT', () {
    test('select بسيط وWITH وjoin وcomma-join على جداول مسموحة', () async {
      expect(
        (await guarded.runSelect('SELECT * FROM "products"', const [])).length,
        2,
      );
      expect(
        await guarded.runSelect(
          'select name from products where id = ? limit 1;',
          [1],
        ),
        [
          {'name': 'tea'},
        ],
      );
      expect(
        await guarded.runSelect(
          'with p as (select * from products) select name from p order by id',
          const [],
        ),
        hasLength(2),
      );
      expect(
        await guarded.runSelect(
          'select p.name from products p join sales_invoices s on s.id = p.id',
          const [],
        ),
        hasLength(1),
      );
      expect(
        await guarded.runSelect(
          'select a.id from products a, sales_invoices b where a.id=b.id',
          const [],
        ),
        hasLength(1),
      );
      expect(
        await guarded.runSelect(
          'select count(*) as c from (select id from products) t',
          const [],
        ),
        [
          {'c': 2},
        ],
      );
      expect(
        await guarded.runSelect('select 1 as one', const []),
        hasLength(1),
      );
    });

    test('الأحرف الكبيرة والاقتباس لا تُفلت من الفحص', () async {
      await expectRejected('SELECT * FROM `hr_secret`');
      await expectRejected('select * from [hr_secret]');
      await expectRejected('select * from "HR_Secret"');
    });
  });

  group('الرفض عند الشكّ', () {
    test('ليس SELECT/WITH', () async {
      for (final s in [
        '',
        '   ',
        'pragma table_info(users)',
        'insert into products values (3,"a")',
        'delete from products',
        'explain select 1',
        '(select 1)',
        'values (1)',
      ]) {
        await expectRejected(s);
      }
    });

    test('أكثر من أمر وتعليقات', () async {
      await expectRejected('select 1; select 2');
      await expectRejected('select 1; drop table products');
      await expectRejected('select 1 -- x');
      await expectRejected('select /* x */ 1');
    });

    test('PRAGMA/ATTACH/sqlite_master/pg_/information_schema/INTO', () async {
      await expectRejected('select * from sqlite_master');
      await expectRejected('select name from "sqlite_master"');
      await expectRejected('select * from sqlite_schema');
      await expectRejected('select * from pg_catalog.pg_tables');
      await expectRejected('select * from pg_user');
      await expectRejected('select * from information_schema.tables');
      await expectRejected("select * from products into outfile 'x'");
      await expectRejected('select * from pragma_table_info(\'users\')');
      await expectRejected("attach database 'x' as y");
      await expectRejected(
        "with a as (select 1) insert into products select * from a",
      );
      await expectRejected(
        'with a as (select 1) delete from products where id in (select 1)',
      );
    });

    test('جدول خارج المسموح في أي موضع', () async {
      await expectRejected('select * from hr_secret');
      await expectRejected('select * from products, hr_secret');
      await expectRejected('select * from products join hr_secret on 1=1');
      await expectRejected('select * from (select * from hr_secret) t');
      await expectRejected(
        'select * from products where id in (select id from hr_secret)',
      );
      await expectRejected(
        'select * from products union select id, v from hr_secret',
      );
      await expectRejected(
        'with a as (select * from hr_secret) select * from a',
      );
      await expectRejected('select * from main.products');
      await expectRejected('select * from json_each(\'[1]\')');
      await expectRejected('select * from');
    });

    test('نصّ مبتور أو غير مغلق', () async {
      await expectRejected("select 'abc from products");
      await expectRejected('select "abc from products');
    });
  });

  group('إخفاء الأعمدة الحسّاسة', () {
    test('users: كلمات المرور وpin وcard_code فارغة لا null', () async {
      final rows = await guarded.runSelect('select * from users', const []);
      final r = rows.single;
      expect(r['username'], 'ali');
      for (final c in ['password_hash', 'password_salt', 'pin', 'card_code']) {
        expect(r[c], '', reason: c);
        expect(r[c], isNotNull);
      }
    });

    test('تسمية drift المؤهّلة "users.pin" تُخفى أيضاً', () async {
      final rows = await guarded.runSelect(
        'select "users"."pin" as "users.pin", "users"."id" as "users.id" '
        'from users',
        const [],
      );
      expect(rows.single['users.pin'], '');
      expect(rows.single['users.id'], 1);
    });

    test('clientSecret وkey_hash', () async {
      final e = await guarded.runSelect('select * from e_invoice_configs', []);
      expect(e.single['client_secret'], '');
      expect(e.single['client_id'], 'cid');
      final k = await guarded.runSelect('select * from api_keys', []);
      expect(k.single['key_hash'], '');
      expect(k.single['name'], 'k');
    });

    test('settings_access_password تُفرَّغ قيمته وغيره سليم', () async {
      final rows = await guarded.runSelect(
        'select * from settings order by key',
        [],
      );
      final byKey = {for (final r in rows) r['key']: r['value']};
      expect(byKey['currency'], 'EGP');
      expect(byKey['settings_access_password'], '');
    });

    test('محاولات التحايل مرفوضة', () async {
      // تغيير اسم العمود
      await expectRejected('select pin as x from users');
      await expectRejected('select password_hash as ph from users');
      // تحويل/تجميع/ترشيح/ترتيب بالعمود الحسّاس
      await expectRejected('select substr(pin,1,1) from users');
      await expectRejected('select id from users where pin = \'1234\'');
      await expectRejected('select id from users order by pin');
      await expectRejected('select id, pin || \'x\' from users');
      await expectRejected('select * from (select pin as z from users) t');
      // settings بلا عمود key في النتيجة
      await expectRejected('select value from settings');
      await expectRejected(
        'select substr(value,1,3) v from settings where key like \'%pass%\'',
      );
    });
  });

  group('تجاوز الإخفاء بالاستعلام الفرعي/UNION/CTE (W-1)', () {
    test('استعلام فرعي/UNION/INTERSECT/EXCEPT على جدول حسّاس مرفوض', () async {
      await expectRejected(
        'select (select client_secret from e_invoice_configs limit 1) as x',
      );
      await expectRejected(
        'select 1 as a union select client_secret from e_invoice_configs',
      );
      await expectRejected(
        'select id from e_invoice_configs union all '
        'select 1 from e_invoice_configs',
      );
      await expectRejected(
        'select 1 intersect select client_secret from e_invoice_configs',
      );
      await expectRejected(
        'select 1 except select client_secret from e_invoice_configs',
      );
      await expectRejected(
        'select (select key_hash from api_keys limit 1) as k',
      );
      await expectRejected(
        'select * from (select * from users) t',
      );
      await expectRejected(
        'select id from users where id in (select id from users)',
      );
    });

    test('CTE بقائمة أعمدة على جدول حسّاس (إعادة تسمية) مرفوض', () async {
      await expectRejected(
        'with t(a,b,c,d,e,f) as (select * from users) select a, b from t',
      );
    });

    test('with recursive مرفوض حتى بلا جدول حسّاس', () async {
      await expectRejected(
        'with recursive r(n) as (select 1 union all select n+1 from r) '
        'select n from r',
      );
      await expectRejected(
        'with recursive r(n) as (select 1 union all select n+1 from r '
        'limit 3) select n from r',
      );
    });

    test('الاستعلام الفرعي/UNION/CTE على جداول غير حسّاسة ما زال مقبولاً',
        () async {
      expect(
        await guarded.runSelect(
          'select name from products where id in '
          '(select id from sales_invoices)',
          const [],
        ),
        hasLength(1),
      );
      expect(
        await guarded.runSelect(
          'select id from products union select id from sales_invoices',
          const [],
        ),
        hasLength(2),
      );
    });

    test('SELECT بسيط على الجدول الحسّاس يعمل ويُخفى كما كان', () async {
      final rows = await guarded.runSelect(
        'select id, username, pin from users where id = ?',
        [1],
      );
      expect(rows.single['username'], 'ali');
      expect(rows.single['pin'], '');
    });

    test('سقف الصفوف: النتيجة الأكبر من السقف تُرفض', () async {
      final small = raw.interceptWith(
        WebReadPolicyInterceptor(allowedTables: _allowed, maxRows: 1),
      );
      await expectLater(
        small.runSelect('select * from products', const []),
        throwsA(isA<WebReadPolicyViolation>()),
      );
      expect(
        await small.runSelect('select * from products limit 1', const []),
        hasLength(1),
      );
    });
  });

  group('DriftServer عبر القناة', () {
    test(
      'يقرأ المسموح، ويرفض الممنوع، ولا يكتب، ولا يُغلق القاعدة',
      () async {
        final server = createWebReadDriftServer(raw, allowedTables: _allowed);
        final c = StreamChannelController<String>();
        server.serve(driftJsonChannel(c.local));
        final db = _RawDb(
          DatabaseConnection.delayed(
            connectToRemoteAndInitialize(driftJsonChannel(c.foreign)),
          ),
        );

        final ok = await db.customSelect('select * from users').get();
        expect(ok.single.data['pin'], '');
        expect(ok.single.data['username'], 'ali');

        await expectLater(
          db.customSelect('select * from hr_secret').get(),
          throwsA(anything),
        );
        await expectLater(
          db.customUpdate('delete from products'),
          throwsA(anything),
        );
        await expectLater(
          db.transaction(() async {
            await db.customSelect('select 1').get();
          }),
          throwsA(anything),
        );

        await db.close();
        await server.shutdown();
        final n = await raw.runSelect('select count(*) c from products', []);
        expect(n.single['c'], 2);
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });
}

