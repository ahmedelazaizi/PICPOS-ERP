// «حذفُ الشعار» يحذفه فعلاً — لا يُخفيه.
//
// ═══ 🔴 العطبُ المقيس (2026-09-20) ═══
//
// `saveReceiptSettings` كانت تكتب:
//
//     logoImage: logoImage != null ? Value(logoImage) : const Value.absent()
//
// أي **«غيابُ القيمة يعني لا تمسّ العمود»** — وهو عقدُ تحديثٍ جزئيٍّ صحيحٌ
// لحقلٍ نصّيّ، وخاطئٌ لهذا الحقل: الحقولُ النصّيّةُ تأتي من
// `TextEditingController` فترسل `''` لا `null`، **فـ`logoImage` هو الحقلُ
// الوحيدُ في الدالّة الذي يكون فراغُه `null` حقيقيّاً** — والوحيدُ الذي
// تعذَّر مسحُه.
//
// ═══ ⚠️ وما كان يُخفيه ═══
//
// زرُّ «حذف الشعار» يضع `_logoImage = null` **و`_showLogo = false` معاً**،
// و`showLogo` تُكتَب فعلاً (‏`false != null`). فالشعارُ يختفي من الإيصال
// ويظنّ المستخدمُ أنّه حُذف — **ثمّ يُعيد فتحَ الشاشة فيعود الشعارُ ظاهراً
// في المنتقي والمفتاحُ يُفعَّل من جديد**، لأنّ البايتاتِ لم تغادر القاعدةَ
// قطّ. وكلُّ نسخةٍ احتياطيّةٍ تحملها.
//
// ═══ ⚠️ ولماذا `null` تعني «امسح» ولا يُضاف وسيطُ `clearLogo` ═══
//
// قِيس كلُّ منادٍ قبل القرار: المناداةُ الثلاثُ (`receipt_settings_widget` ·
// `company_info_widget_io` · `company_info_widget_web`) **تقرأ الحالةَ
// القائمةَ ثمّ تحفظ الاستمارةَ كاملةً**، ولا واحدةٌ منها تُسقط
// `logoImage:`. فلا منادِيَ يحتاج «لا تمسّ» أصلاً، ووسيطٌ ثانٍ كان يُنتج
// مصدرَي حقيقةٍ يختلفان (`logoImage: bytes, clearLogo: true`).
//
// وحارسُ `receipt_logo_callers_pass_it_test` يثبّت الشرطَ: **كلُّ منادٍ
// يمرّر `logoImage:` صراحةً** — فمنادٍ جديدٌ يُسقطه يمحو شعارَ المنشأة.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  Uint8List bytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (i) => i % 251));

  Future<Uint8List?> storedLogo() async =>
      (await db.getReceiptSettings()).logoImage;

  test('⚓ مرساة — الشعارُ يُحفَظ فعلاً', () async {
    await db.saveReceiptSettings(companyName: 'منشأة', logoImage: bytes(64));
    final got = await storedLogo();
    expect(got, isNotNull);
    expect(got!.length, 64);
  });

  test('⚓ مرساة — وحقلٌ نصّيٌّ يُمسَح بالفراغ لا بالغياب', () async {
    // الحقولُ النصّيّةُ تصل `''` من المنتقي، فلا يشملها العطبُ أعلاه —
    // وهذه المرساةُ تمنع «إصلاحاً» يقلب عقدَها هي أيضاً.
    await db.saveReceiptSettings(companyName: 'منشأة', termsText: 'شروط');
    expect((await db.getReceiptSettings()).termsText, 'شروط');
    await db.saveReceiptSettings(termsText: '');
    expect((await db.getReceiptSettings()).termsText, '');
  });

  test('🔴 «حذف الشعار» يمحو البايتاتِ من القاعدة', () async {
    await db.saveReceiptSettings(companyName: 'منشأة', logoImage: bytes(64));
    expect(await storedLogo(), isNotNull, reason: 'التجهيزةُ لم تحفظ شيئاً');

    // ما يُرسله الزرُّ بالضبط: لا شعارَ، ولا إظهار.
    await db.saveReceiptSettings(logoImage: null, showLogo: false);

    expect(await storedLogo(), isNull,
        reason: 'البايتاتُ بقيت — و«الحذفُ» أخفى الشعارَ ولم يحذفه');
  });

  test('🔴 ولا يعود عند إعادة فتح الشاشة', () async {
    // الشاشةُ تُعيد التحميلَ بـ`_logoImage = data[\'logoImage\']`، فبقاءُ
    // البايتاتِ يُعيد الشعارَ ظاهراً في المنتقي ويُفعّل مفتاحَه من جديد.
    await db.saveReceiptSettings(companyName: 'منشأة', logoImage: bytes(32));
    await db.saveReceiptSettings(logoImage: null, showLogo: false);

    final reopened = await db.getReceiptSettings();
    expect(reopened.logoImage, isNull);
    expect(reopened.showLogo, isFalse);
  });

  test('وحفظٌ لاحقٌ لحقلٍ آخرَ لا يُعيد شعاراً محذوفاً', () async {
    await db.saveReceiptSettings(companyName: 'منشأة', logoImage: bytes(16));
    await db.saveReceiptSettings(logoImage: null, showLogo: false);
    await db.saveReceiptSettings(logoImage: null, companyName: 'منشأة ٢');

    expect(await storedLogo(), isNull);
    expect((await db.getReceiptSettings()).companyName, 'منشأة ٢');
  });

  test('واستبدالُ الشعار يستبدله لا يُراكمه', () async {
    await db.saveReceiptSettings(companyName: 'منشأة', logoImage: bytes(64));
    await db.saveReceiptSettings(logoImage: bytes(8));
    final got = await storedLogo();
    expect(got!.length, 8);
  });

  test('والإدراجُ الأوّلُ يحمل الشعارَ معه — لا حفظاً ثانياً يلزمه', () async {
    // فرعُ `else` في الدالّة (لا صفَّ بعد): كان يُسقط `logoImage` إسقاطاً
    // تامّاً، فأوّلُ حفظٍ على قاعدةٍ نظيفةٍ يضيع شعارُه بلا رسالة.
    await db.saveReceiptSettings(companyName: 'منشأة', logoImage: bytes(24));
    final got = await storedLogo();
    expect(got, isNotNull,
        reason: 'أوّلُ حفظٍ على قاعدةٍ بلا صفٍّ أسقط الشعار');
    expect(got!.length, 24);
  });
}
