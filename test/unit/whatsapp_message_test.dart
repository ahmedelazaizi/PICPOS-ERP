// إرسالُ الفاتورة وكشفِ الحساب والمطالبة على واتساب — البندُ الثاني.
//
// منفَذُ `wa.me` بقرار المالك 2026-09-12.
//
// ═══ لماذا تسويةُ الرقم هي نصفُ الميزة ═══
//
// `wa.me` يقبل **أرقاماً دوليّةً بلا رموز**: لا `+` ولا مسافات ولا شُرَط ولا
// صفرٌ بادئ. وأرقامُ العملاء في أيّ قاعدةٍ حقيقيّةٍ مكتوبةٌ كما أملاها
// صاحبُها: `010 1234 5678` و`+20 10…` و`٠١٠…` بالأرقام العربيّة الهنديّة.
//
// ورقمٌ لم يُسوَّ لا يُنتج خطأً: `wa.me` يفتح صفحةً تقول «الرقمُ غيرُ صالح»،
// فيظنّ الموظّفُ أن العميلَ ليس على واتساب. وهو إخفاقٌ **صامتٌ من جهتنا**.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/whatsapp_message.dart';

void main() {
  group('تسويةُ الرقم', () {
    String? n(String? raw, {String cc = '20'}) =>
        normalizeWhatsAppPhone(raw, defaultCountryCode: cc);

    test('المحلّيُّ بصفرٍ بادئٍ يأخذ رمزَ الدولة', () {
      expect(n('01012345678'), '201012345678');
    });

    test('والدوليُّ بـ+ يُنزَع منه الرمزُ فقط', () {
      expect(n('+201012345678'), '201012345678');
    });

    test('والدوليُّ بـ00 كذلك', () {
      expect(n('00201012345678'), '201012345678');
    });

    test('والفواصلُ كلُّها تسقط', () {
      expect(n('010 123 45678'), '201012345678');
      expect(n('010-1234-5678'), '201012345678');
      expect(n('(010) 1234 5678'), '201012345678');
      expect(n('  01012345678  '), '201012345678');
    });

    test('والأرقامُ العربيّةُ الهنديّةُ تُحوَّل', () {
      // ⚠️ هذه هي الحالةُ التي تُسقط الميزةَ في السوق العربيّ بلا أن يُبلَّغ
      // عنها: الموظّفُ يرى رقماً سليماً على الشاشة، والرابطُ يحمل محارفَ
      // لا يفهمها واتساب.
      expect(n('٠١٠١٢٣٤٥٦٧٨'), '201012345678');
      expect(n('۰۱۰۱۲۳٤٥٦٧۸'), '201012345678');
    });

    test('ورمزُ دولةٍ آخرُ يُحترَم', () {
      expect(n('0512345678', cc: '966'), '966512345678');
      expect(n('+966512345678', cc: '20'), '966512345678',
          reason: 'الدوليُّ الصريحُ لا يُعاد تركيبه برمز الإعداد');
    });

    test('ورقمٌ بلا صفرٍ ولا رمزٍ يأخذ رمزَ الدولة', () {
      expect(n('1012345678'), '201012345678');
    });

    test('ورقمٌ يبدأ برمز الدولة أصلاً لا يُضاعَف', () {
      expect(n('201012345678'), '201012345678',
          reason: 'التكرارُ يُنتج رقماً لا وجودَ له');
    });

    test('وأصفارٌ بادئةٌ متعدّدةٌ تُقَصّ', () {
      expect(n('0001012345678'), '201012345678');
    });

    group('ما يُرفَض — ولا يُفتَح به رابط', () {
      test('الفارغُ والمعدوم', () {
        expect(n(null), isNull);
        expect(n(''), isNull);
        expect(n('   '), isNull);
      });

      test('وما لا رقمَ فيه', () {
        expect(n('لا يوجد'), isNull);
        expect(n('n/a'), isNull);
        expect(n('---'), isNull);
      });

      test('والقصيرُ جدّاً', () {
        // امتدادٌ داخليٌّ أو رقمٌ ناقصٌ — فتحُ واتساب به يُربك الموظّف.
        expect(n('123'), isNull);
        expect(n('0100'), isNull);
      });

      test('والطويلُ فوق حدّ E.164', () {
        expect(n('0123456789012345678'), isNull);
      });

      test('ورمزُ دولةٍ غيرُ صالحٍ في الإعداد', () {
        expect(normalizeWhatsAppPhone('01012345678', defaultCountryCode: ''),
            isNull);
        expect(normalizeWhatsAppPhone('01012345678', defaultCountryCode: 'مصر'),
            isNull);
      });
    });
  });

  group('بناءُ الرابط', () {
    test('يحمل الرقمَ المسوّى والنصَّ مرمَّزاً', () {
      final url = buildWhatsAppUrl(phone: '201012345678', message: 'مرحباً');
      expect(url, startsWith('https://wa.me/201012345678?text='));
      expect(url, isNot(contains(' ')), reason: 'مسافةٌ خامٌ تكسر الرابط');
    });

    test('والسطورُ والرموزُ تُرمَّز ولا تُبتَر', () {
      final url = buildWhatsAppUrl(
        phone: '201012345678',
        message: 'فاتورة #10\nالمبلغ: 250.00 ج.م\n50% خصم & شكراً',
      );
      expect(url, isNot(contains('\n')));
      expect(url, isNot(contains('#')), reason: '# يقطع الرابط عند المرساة');
      expect(url, isNot(contains('&')),
          reason: '& يُقرأ فاصلَ معاملاتٍ فيُبتَر النصّ');
      // والفكُّ يعيد النصَّ كما هو — لا حرفَ ضاع.
      final text = Uri.parse(url).queryParameters['text'];
      expect(text, contains('فاتورة #10'));
      expect(text, contains('50% خصم & شكراً'));
    });
  });

  group('نصوصُ الرسائل الثلاثة', () {
    test('الفاتورةُ تحمل رقمَها ومبلغَها واسمَ المحلّ', () {
      final msg = composeInvoiceMessage(
        shopName: 'مطعم الأصيل',
        customerName: 'أحمد',
        invoiceNumber: 'INV-1024',
        total: 250,
        issuedAt: DateTime(2026, 9, 12),
      );
      expect(msg, contains('مطعم الأصيل'));
      expect(msg, contains('أحمد'));
      expect(msg, contains('INV-1024'));
      expect(msg, contains('250'));
      expect(msg, contains('2026'));
    });

    test('وكشفُ الحساب يقول الرصيدَ ومعناه لا الرقمَ عارياً', () {
      // ⚠️ «رصيدُك ‎-٥٠٠» لا يفهمه زبون. والإشارةُ في هذا المستودع
      // `+debit / -credit`، فالسالبُ **لصالح العميل** لا عليه.
      final owes = composeStatementMessage(
        shopName: 'م',
        customerName: 'أحمد',
        balance: 500,
        asOf: DateTime(2026, 9, 12),
      );
      expect(owes, contains('عليك'), reason: 'موجبٌ = مستحقٌّ على العميل');

      final credit = composeStatementMessage(
        shopName: 'م',
        customerName: 'أحمد',
        balance: -500,
        asOf: DateTime(2026, 9, 12),
      );
      expect(credit, contains('لك'), reason: 'سالبٌ = لصالح العميل');
      expect(credit, isNot(contains('-500')),
          reason: 'رقمٌ سالبٌ خامٌ يُربك القارئ');

      final settled = composeStatementMessage(
        shopName: 'م',
        customerName: 'أحمد',
        balance: 0,
        asOf: DateTime(2026, 9, 12),
      );
      expect(settled, contains('لا مستحقّات'));
    });

    test('والمطالبةُ لا تُبنى على رصيدٍ غيرِ مستحقّ', () {
      // ⚠️ مطالبةٌ بمبلغٍ لا يستحقّ إساءةٌ إلى عميلٍ منتظم — والدالّةُ
      // ترفض بدل أن تكتب «برجاء سداد ٠».
      expect(
        composeDueReminderMessage(
          shopName: 'م',
          customerName: 'أحمد',
          dueAmount: 0,
        ),
        isNull,
      );
      expect(
        composeDueReminderMessage(
          shopName: 'م',
          customerName: 'أحمد',
          dueAmount: -100,
        ),
        isNull,
      );
      final msg = composeDueReminderMessage(
        shopName: 'م',
        customerName: 'أحمد',
        dueAmount: 100,
      );
      expect(msg, isNotNull);
      expect(msg, contains('100'));
    });

    test('واسمُ محلٍّ فارغٌ لا يترك فجوةً في النصّ', () {
      final msg = composeInvoiceMessage(
        shopName: '   ',
        customerName: 'أحمد',
        invoiceNumber: 'INV-1',
        total: 10,
        issuedAt: DateTime(2026, 9, 12),
      );
      expect(msg.contains('  '), isFalse, reason: 'فراغٌ مزدوجٌ مكانَ الاسم');
      expect(msg.trim(), isNotEmpty);
    });
  });
}
