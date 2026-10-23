// اختبارُ نموذجِ عرضِ «العملاء والموردين» — حسابٌ خالصٌ بلا قاعدةٍ ولا ودجت.
//
// ما يُقاس هنا هو ما تنهار عليه الشاشةُ صامتةً لو انحرف: دلالةُ الترشيح
// (نفسُها قبل إعادة التصميم وبعدها)، وحدُّ الائتمان الصفريُّ الذي يعني «بلا
// حدّ» لا «حدَّ صفر»، وجمعُ الأرصدة بالوحدات الصغرى.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/domain/models/picpos_party_view.dart';

PicPosPartyCard _party({
  int id = 1,
  String name = 'أحمد سولا',
  double balance = 0,
  double creditLimit = 0,
  String? phone,
  String? address,
  bool isCustomer = false,
  bool isSupplier = false,
  bool isDeliveryCompany = false,
}) =>
    PicPosPartyCard(
      id: id,
      name: name,
      balance: balance,
      creditLimit: creditLimit,
      phone: phone,
      address: address,
      isCustomer: isCustomer,
      isSupplier: isSupplier,
      isDeliveryCompany: isDeliveryCompany,
    );

void main() {
  group('PicPosPartyCard — الحقولُ المشتقّة', () {
    test('الأحرفُ الأولى: كلمتان ⇒ حرفان، كلمةٌ ⇒ حرفٌ واحد', () {
      expect(_party(name: 'أحمد سولا').initials, 'أس');
      expect(_party(name: 'أحمد').initials, 'أ');
      expect(_party(name: 'أحمد محمد سولا').initials, 'أم');
    });

    test('الأحرفُ الأولى لا تنهار على فراغٍ أو مسافاتٍ متعدّدة', () {
      expect(_party(name: '   ').initials, '؟');
      expect(_party(name: 'أحمد    سولا').initials, 'أس');
    });

    // ⚠️ هذه النصوصُ **عقدُ تكافؤٍ مع الفورك الآخر** لا ذوقٌ: أيُّ تغييرٍ هنا
    // يجب أن يقع في `getPartyTypeLabel` كذلك، وإلّا اختلف وصفُ نفسِ الطرف
    // بين الشاشتين.
    test('تسميةُ النوع تطابق getPartyTypeLabel نصّاً وترتيبَ أولويّة', () {
      expect(
        _party(isCustomer: true, isSupplier: true, isDeliveryCompany: true)
            .typeLabel,
        'شركة توصيل',
      );
      expect(_party(isCustomer: true, isSupplier: true).typeLabel, 'عميل مورد');
      expect(_party(isSupplier: true).typeLabel, 'مورد');
      expect(_party(isCustomer: true).typeLabel, 'عميل');
      expect(_party().typeLabel, 'غير محدد');
    });

    // ⚠️ العطبُ الذي يحرسه هذا الاختبار: قراءةُ `creditLimit` حرفيّاً تجعل
    // كلَّ طرفٍ عليه قرشٌ «متجاوزاً حدَّ الائتمان» — لأن العمودَ افتراضُه صفر.
    test('حدُّ الائتمان الصفريُّ يعني «بلا حدّ» فلا تجاوزَ أبداً', () {
      expect(_party(balance: 999999, creditLimit: 0).isOverLimit, isFalse);
      expect(_party(balance: 0.001, creditLimit: 0).isOverLimit, isFalse);
    });

    test('التجاوزُ يقع فوق الحدِّ فقط — لا عنده', () {
      expect(_party(balance: 100, creditLimit: 100).isOverLimit, isFalse);
      expect(_party(balance: 100.001, creditLimit: 100).isOverLimit, isTrue);
      expect(_party(balance: -500, creditLimit: 100).isOverLimit, isFalse);
    });

    test('تسميةُ الحدّ تفرّق «بلا حدّ» عن حدٍّ مذكور', () {
      expect(_party(creditLimit: 0).creditLimitLabel, 'بلا حدّ ائتمان');
      expect(_party(creditLimit: 250).creditLimitLabel, 'حد 250');
    });

    // decimalPlaces = 3 في هذا المستودع — والاختبارُ يقرأ الثابتَ لا يكتب ٣،
    // فلو تغيّر الثابتُ سقط الاختبارُ عمداً بدل أن يكذب بصمت.
    test('نصُّ الرصيد يستعمل decimalPlaces لا رقماً مكتوباً باليد', () {
      final label = _party(balance: 12.5).balanceLabel;
      expect(
        label,
        '${(12.5).toStringAsFixed(AppConstants.decimalPlaces)} '
        '${AppConstants.currencySymbolEn}',
      );
      expect(label.split('.').last.split(' ').first.length,
          AppConstants.decimalPlaces);
    });

    test('سطرُ التفاصيل يُسقط الفاصلَ مع الحقل الغائب', () {
      expect(_party(phone: '0790', address: 'عمّان').subtitle, '0790 · عمّان');
      expect(_party(phone: '0790').subtitle, '0790');
      expect(_party(address: 'عمّان').subtitle, 'عمّان');
      expect(_party().subtitle, 'لا توجد بيانات اتصال');
      expect(_party(phone: '   ', address: '  ').subtitle, 'لا توجد بيانات اتصال');
    });
  });

  group('PicPosPartyCard.matches — دلالةُ الترشيح', () {
    final customer = _party(id: 1, name: 'عميل', isCustomer: true);
    final supplier = _party(id: 2, name: 'مورد', isSupplier: true);
    final dual = _party(id: 3, name: 'مزدوج', isCustomer: true, isSupplier: true);
    final courier = _party(id: 4, name: 'طلبات', isDeliveryCompany: true);

    test('«الكل» يمرّر كلَّ الأنواع', () {
      for (final p in [customer, supplier, dual, courier]) {
        expect(p.matches(PicPosPartyFilter.all, ''), isTrue, reason: p.name);
      }
    });

    test('«عملاء» يشمل المزدوجَ ويستبعد الموردَ الخالص', () {
      expect(customer.matches(PicPosPartyFilter.customer, ''), isTrue);
      expect(dual.matches(PicPosPartyFilter.customer, ''), isTrue);
      expect(supplier.matches(PicPosPartyFilter.customer, ''), isFalse);
    });

    test('«موردين» يشمل المزدوجَ ويستبعد العميلَ الخالص', () {
      expect(supplier.matches(PicPosPartyFilter.supplier, ''), isTrue);
      expect(dual.matches(PicPosPartyFilter.supplier, ''), isTrue);
      expect(customer.matches(PicPosPartyFilter.supplier, ''), isFalse);
    });

    test('«عميل مورد» يشترط الصفتَين معاً', () {
      expect(dual.matches(PicPosPartyFilter.both, ''), isTrue);
      expect(customer.matches(PicPosPartyFilter.both, ''), isFalse);
      expect(supplier.matches(PicPosPartyFilter.both, ''), isFalse);
    });

    test('«توصيل» يشترط علمَ شركة التوصيل', () {
      expect(courier.matches(PicPosPartyFilter.delivery, ''), isTrue);
      expect(customer.matches(PicPosPartyFilter.delivery, ''), isFalse);
    });

    test('البحثُ على الاسم أو الهاتف، بلا حساسيّةٍ لحالة الأحرف', () {
      final p = _party(name: 'Ahmed Sola', phone: '0790123456');
      expect(p.matches(PicPosPartyFilter.all, 'ahmed'), isTrue);
      expect(p.matches(PicPosPartyFilter.all, 'SOLA'), isTrue);
      expect(p.matches(PicPosPartyFilter.all, '79012'), isTrue);
      expect(p.matches(PicPosPartyFilter.all, 'زيد'), isFalse);
    });

    test('البحثُ لا يطابق العنوانَ — نفسُ دلالةِ الفلتر قبل إعادة التصميم', () {
      final p = _party(name: 'عميل', address: 'عمّان');
      expect(p.matches(PicPosPartyFilter.all, 'عمّان'), isFalse);
    });

    test('الترشيحُ والبحثُ يتراكبان لا يتبادلان', () {
      expect(supplier.matches(PicPosPartyFilter.customer, 'مورد'), isFalse);
      expect(dual.matches(PicPosPartyFilter.customer, 'مزدوج'), isTrue);
    });

    test('هاتفٌ غائبٌ لا ينهار مع بحثٍ غيرِ فارغ', () {
      expect(_party(name: 'بلا هاتف').matches(PicPosPartyFilter.all, '079'),
          isFalse);
    });
  });

  group('PicPosPartyFilter.fromId', () {
    test('يقرأ المعرّفاتِ القائمة', () {
      expect(PicPosPartyFilter.fromId('supplier'), PicPosPartyFilter.supplier);
      expect(PicPosPartyFilter.fromId('both'), PicPosPartyFilter.both);
    });

    test('معرّفٌ مجهولٌ يرتدّ إلى «الكل» لا يرمي', () {
      expect(PicPosPartyFilter.fromId('nonsense'), PicPosPartyFilter.all);
    });
  });

  group('PicPosPartyKpis', () {
    test('قائمةٌ فارغةٌ تعطي أصفاراً لا قسمةً على صفر', () {
      final k = PicPosPartyKpis.from(const []);
      expect(k.total, 0);
      expect(k.customers, 0);
      expect(k.suppliers, 0);
      expect(k.totalDebit, 0);
      expect(k.totalCredit, 0);
      expect(k.overLimitCount, 0);
    });

    test('المزدوجُ يُعدّ عميلاً ومورداً معاً — لا مرّةً واحدة', () {
      final k = PicPosPartyKpis.from([
        _party(id: 1, isCustomer: true),
        _party(id: 2, isSupplier: true),
        _party(id: 3, isCustomer: true, isSupplier: true),
      ]);
      expect(k.total, 3);
      expect(k.customers, 2);
      expect(k.suppliers, 2);
    });

    test('المدينُ والدائنُ يُفصلان بالإشارة، والدائنُ موجبُ العرض', () {
      final k = PicPosPartyKpis.from([
        _party(id: 1, balance: 100),
        _party(id: 2, balance: -40),
        _party(id: 3, balance: 0),
      ]);
      expect(k.totalDebit, closeTo(100, 1e-9));
      expect(k.totalCredit, closeTo(40, 1e-9));
    });

    // ⚠️ هذا الاختبارُ كُتب أوّلاً يدّعي أنه يحرس «تراكمَ خطأ التمثيل»، ثمّ
    // أُفسد الحسابُ عمداً إلى جمعٍ مباشرٍ بالبتر — **فمرّ أخضرَ**. والمسحُ
    // بعدها أثبت أن الجمعَين لا يختلفان عند ثلاثِ خاناتٍ حتى مئةِ ألفِ صفّ.
    // فأُعيدت صياغتُه ليحرس ما يقع فعلاً: التقريبَ بدل البتر.
    test('رصيدٌ أدقُّ من المعروض يدخل المجموعَ مقرَّباً لا مبتوراً', () {
      final k = PicPosPartyKpis.from([_party(balance: 0.0006)]);
      expect(k.totalDebit, closeTo(0.001, 1e-9));
    });

    test('جمعُ عدّةِ أرصدةٍ يطابق المجموعَ المتوقَّع نصّاً', () {
      final k = PicPosPartyKpis.from([
        for (var i = 0; i < 10; i++) _party(id: i, balance: 0.1),
      ]);
      expect(k.totalDebitLabel,
          (1.0).toStringAsFixed(AppConstants.decimalPlaces));
    });

    test('عدّادُ المتجاوزين يحترم «الحدُّ الصفريُّ = بلا حدّ»', () {
      final k = PicPosPartyKpis.from([
        _party(id: 1, balance: 999, creditLimit: 0),
        _party(id: 2, balance: 999, creditLimit: 100),
        _party(id: 3, balance: 50, creditLimit: 100),
      ]);
      expect(k.overLimitCount, 1);
    });
  });
}
