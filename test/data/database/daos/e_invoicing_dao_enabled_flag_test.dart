// ═══════════════════════════════════════════════════════════════════════════
// رايةُ تفعيل الفاتورة الإلكترونيّة تُكتب مع الإعداد — ولا تنفكّ عنه.
// ═══════════════════════════════════════════════════════════════════════════
//
// `EInvoiceConfigs.isEnabled` هي الحقيقة، لكنّ الجدولَ **خارجَ المزامنة**
// بقرار المالك 2026-09-02 لأنّه يحمل `clientSecret` نصّاً. فالكاشير لا يراه
// أبداً — ولا يستطيع أن يعرف أنّ المنشأةَ مسجَّلةٌ ضريبيّاً.
//
// والفارقُ ليس تجميلاً: الجهازُ الذي لا يعرف يطبع رمزاً **غيرَ ضريبيٍّ** على
// إيصالِ منشأةٍ مسجَّلةٍ (‏`receipt_qr_decision_test`). فالرايةُ
// `einvoice_enabled` في `Settings` — وهي تُزامَن — تحمل الحقيقةَ بلا سرّ.
//
// وتُكتب **داخلَ** `saveEInvoiceConfig` لا في شاشةٍ: فمن كتب الإعدادَ من أيّ
// مسارٍ (لوحةُ UralCash اليوم، ونموذجُ PicPos غداً) لا يستطيع أن ينسى الراية.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/models/receipt_qr_decision.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  Future<int> save(String platform, {required bool enabled}) {
    return db.saveEInvoiceConfig(
      platform: platform,
      clientId: 'id-$platform',
      clientSecret: 'secret-$platform',
      registrationNumber: '100-200-300',
      isEnabled: enabled,
    );
  }

  // 🔴 مرساةٌ غيرُ دائريّة: قبل أيّ حفظٍ لا صفَّ للراية أصلاً. فقراءةُ `true`
  //    بعدُ هي أثرُ الحفظ لا قيمةً افتراضيّةً مبذورة.
  test('مرساة: لا رايةَ قبل أوّل حفظ', () async {
    expect(await db.getSettingValue(kEInvoiceEnabledSettingKey), isNull);
  });

  test('حفظُ إعدادٍ مُفعَّلٍ يرفع الراية', () async {
    await save('eta', enabled: true);

    expect(await db.getSettingValue(kEInvoiceEnabledSettingKey), 'true');
  });

  test('تعطيلُ الإعداد الوحيد يُنزل الراية', () async {
    await save('eta', enabled: true);
    await save('eta', enabled: false);

    expect(await db.getSettingValue(kEInvoiceEnabledSettingKey), 'false');
  });

  // الرايةُ تعني «أيُّ منصّةٍ مُفعَّلة» لا «آخرُ ما كُتب»: منصّتان، تُعطَّل
  // إحداهما والأخرى قائمة ⇒ الرايةُ باقية.
  test('الرايةُ تتبع وجودَ أيّ منصّةٍ مُفعَّلة لا آخرَ كتابة', () async {
    await save('eta', enabled: true);
    await save('jofotara', enabled: false);
    expect(await db.getSettingValue(kEInvoiceEnabledSettingKey), 'true',
        reason: 'كتابةُ منصّةٍ معطَّلةٍ لا تُنزل رايةَ منصّةٍ مُفعَّلة');

    await save('eta', enabled: false);
    expect(await db.getSettingValue(kEInvoiceEnabledSettingKey), 'false',
        reason: 'لم يبقَ إعدادٌ مُفعَّلٌ على أيّ منصّة');
  });
}
