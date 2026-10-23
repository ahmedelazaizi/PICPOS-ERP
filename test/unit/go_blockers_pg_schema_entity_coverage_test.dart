// ═══════════════════════════════════════════════════════════════════════════
// §٦‑٥ — كلُّ كيانِ مخطَّطٍ في drift له مسارُ إنشاءٍ يعمل على PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════
//
// خيارُ `dialects` في إعداد drift ما زال **sqlite وحدَها**، فكلُّ كيانٍ يُنشأ
// عبر `Migrator.create` بجملةٍ مولَّدةٍ خاصّةً باللهجة **يرمي على PG**:
//
//   «Tried running SQL optimized for … SqlDialect.sqlite. However, the
//    database is running SqlDialect.postgres.»
//
// وهذا ما أخفى ١٤٣ فهرساً عن كلِّ قاعدةِ خادمٍ حتى 2026-09-01. والفهارسُ
// عولجت بجملةٍ محمولةٍ (`pgPortableIndexSql`) بلا codegen — لكنّ **الجداولَ
// وحدَها والفهارسَ وحدَها** هما ما لهما مسارٌ اليوم:
//
//   · `TableInfo` → إعادةُ بناءٍ بـSQL متوافقةٍ مع PG
//   · `Index`     → الجملةُ المحمولة
//   · ما عداهما   → إعادةُ نداءٍ لـ`Migrator.create` تفشل بعينِ السبب
//
// فلو أُعلن `@DriftView` أو `Trigger` غداً، لسقط صامتاً على كلِّ خادم — ولا
// شيءَ في المستودع يمنع ذلك. وهذا الاختبارُ يمنعه: يُسقط البناءَ عند إضافة
// أيِّ نوعِ كيانٍ ثالثٍ حتى يُبنى له مسارُه (أو يُفعَّل `dialects`).
//
// ⚠️ ومقيسٌ 2026-09-02: صفرُ عروضٍ وصفرُ مُطلِقات — فالاختبارُ أخضرُ اليومَ
// بلا عمل، وهو دَينٌ مسدَّدٌ مقدَّماً لا فحصٌ فارغ.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  test('كلُّ كيانِ مخطَّطٍ إمّا جدولٌ أو فهرس — ولا نوعَ ثالثَ بلا مسارِ PG',
      () {
    final entities = db.allSchemaEntities.toList();

    // مرساة: الاستخراجُ يعمل — قائمةٌ فارغةٌ كانت ستُمرّر الاختبارَ زوراً.
    expect(entities.length, greaterThan(100),
        reason: 'مرساة: المخطَّطُ يحمل أكثرَ من مئةِ كيان، '
            'وُجد ${entities.length}');

    final unsupported = entities
        .where((e) => e is! TableInfo && e is! Index)
        .map((e) => '${e.runtimeType}:${e.entityName}')
        .toList()
      ..sort();

    expect(unsupported, isEmpty,
        reason: 'أنواعُ كياناتٍ بلا مسارِ إنشاءٍ يعمل على PostgreSQL. '
            'إمّا أن يُبنى لها مسارٌ في `_createAllForPostgres` و'
            '`_ensurePostgresSchemaParity` كما بُني للفهارس، أو يُضاف '
            '`postgres` إلى خيار `dialects` ويُعاد التوليد: $unsupported');
  });

  test('الفهارسُ كلُّها تُعطي جملةً محمولةً غيرَ فارغة', () {
    final indexes = db.allSchemaEntities.whereType<Index>().toList();
    expect(indexes.length, greaterThan(100), reason: 'مرساة');

    for (final index in indexes) {
      final sql = db.pgPortableIndexSql(index);
      expect(sql.toUpperCase(), contains('CREATE'),
          reason: '${index.entityName}: جملةٌ لا تُنشئ شيئاً');
      expect(sql.toUpperCase(), contains('IF NOT EXISTS'),
          reason: '${index.entityName}: بلا `IF NOT EXISTS` يفشل الشفاءُ '
              'المتكرّر كلَّ إقلاع');
      expect(sql, contains(index.entityName),
          reason: '${index.entityName}: الجملةُ لا تحمل اسمَ الفهرس');
    }
  });
}
