// حساباتُ شاشة الحجوزات — خالصةٌ فتُقاس بلا قاعدةٍ ولا ودجت.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/picpos_booking_view.dart';

void main() {
  group('تصنيفُ العميل', () {
    test('الحدودُ الأربعةُ بعتباتها الافتراضيّة', () {
      expect(bookingTierFor(0), BookingCustomerTier.bronze);
      expect(bookingTierFor(1999.99), BookingCustomerTier.bronze);
      expect(bookingTierFor(2000), BookingCustomerTier.silver);
      expect(bookingTierFor(7999.99), BookingCustomerTier.silver);
      expect(bookingTierFor(8000), BookingCustomerTier.gold);
      expect(bookingTierFor(14999.99), BookingCustomerTier.gold);
      expect(bookingTierFor(15000), BookingCustomerTier.platinum);
    });

    // ⚠️ **الحدُّ نفسُه داخلُ الدرجة الأعلى** — `>=` لا `>`. عميلٌ أنفق
    // ٢٠٠٠ بالضبط يقرأ «برونزي» لو كانت `>` وهو بالغُ العتبة.
    test('العتبةُ نفسُها تُدخل الدرجةَ الأعلى', () {
      expect(bookingTierFor(2000), BookingCustomerTier.silver);
      expect(bookingTierFor(8000), BookingCustomerTier.gold);
      expect(bookingTierFor(15000), BookingCustomerTier.platinum);
    });

    // 🔴 **الخاصّيّةُ التي تُبرّر الحسابَ بالوحدات الصغرى — وهي مقيسةٌ لا
    // مفترَضة.**
    //
    // ⚠️ أوّلُ صياغةٍ لهذا الحارس استعملت `1000 + 599.99 + 400.01` وسقطت
    // حمراء: ذلك الجمعُ يعطي **2000.0 بالضبط**. فالخاصّيّةُ المدَّعاةُ لم
    // تكن موجودةً في المثال المختار — وهو بالضبط صنفُ «حارسٍ يمرّ لأن ما
    // يقيسه غيرُ موجود» لو كان الاتّجاهُ معكوساً.
    //
    // فبُحث عن مثالٍ **حقيقيّ** بمسحٍ صغير: خمسةُ مبالغَ بخانتين مجموعُها
    // ٢٠٠٠ بالضبط حسابيّاً، وناتجُها في `double` هو
    // `1999.9999999999997726`. ومقارنةٌ عشريّةٌ مباشرةٌ تُبقي هذا العميلَ
    // برونزيّاً بفارقٍ لا يظهر في أيّ شاشة — يرى «٢٠٠٠٫٠٠» ويرى «برونزي».
    test('جمعٌ عشريٌّ يبلغ العتبةَ يُصنَّف فضّيّاً', () {
      const parts = [307.52, 351.45, 395.38, 439.31, 506.34];
      final spend = parts.reduce((a, b) => a + b);

      // المرساةُ: المثالُ يُنتج فارقَ تمثيلٍ فعلاً — وإلّا فالحارسُ لا يقيس شيئاً.
      expect(spend, lessThan(2000.0),
          reason: 'المثالُ مختارٌ لأنه يقع تحت العتبة بفارق تمثيل');
      expect(bookingTierFor(spend), BookingCustomerTier.silver);
    });

    test('عتباتٌ مخصَّصةٌ تُحترَم', () {
      const t = BookingTierThresholds(silver: 100, gold: 200, platinum: 300);
      expect(bookingTierFor(99, thresholds: t), BookingCustomerTier.bronze);
      expect(bookingTierFor(100, thresholds: t), BookingCustomerTier.silver);
      expect(bookingTierFor(300, thresholds: t), BookingCustomerTier.platinum);
    });

    test('عتباتٌ مقلوبةٌ تُكشَف بـ`isMonotonic`', () {
      const bad = BookingTierThresholds(silver: 500, gold: 100, platinum: 900);
      expect(bad.isMonotonic, isFalse);
      expect(const BookingTierThresholds().isMonotonic, isTrue);
    });

    test('إنفاقٌ سالبٌ لا يرمي', () {
      expect(bookingTierFor(-50), BookingCustomerTier.bronze);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('الورديّة — مدًى دائريّ', () {
    test('مدًى عاديٌّ داخلَه وخارجَه', () {
      // ١٠:٠٠ → ٢٠:٠٠
      expect(isWithinShift(600, startMinutes: 600, endMinutes: 1200), isTrue);
      expect(isWithinShift(900, startMinutes: 600, endMinutes: 1200), isTrue);
      expect(isWithinShift(1199, startMinutes: 600, endMinutes: 1200), isTrue);
      expect(isWithinShift(1200, startMinutes: 600, endMinutes: 1200), isFalse);
      expect(isWithinShift(599, startMinutes: 600, endMinutes: 1200), isFalse);
    });

    // 🔴 **الحالةُ التي يُخطئها الحسابُ الخطّيّ.**
    //
    // ورديّةٌ ٢٠:٠٠ → ٠٢:٠٠. حسابٌ خطّيٌّ (`m >= start && m < end`) يرجع
    // كاذباً **لكلّ لحظة** لأن `start > end` — فيُمنع الحجزُ طوالَ الورديّة
    // كلِّها. وهي ورديّةٌ قائمةٌ فعلاً في المطاعم.
    test('ورديّةٌ تعبر منتصفَ الليل', () {
      const start = 1200; // ٢٠:٠٠
      const end = 120; // ٠٢:٠٠
      expect(isWithinShift(1230, startMinutes: start, endMinutes: end), isTrue,
          reason: '٢٠:٣٠ داخلَها');
      expect(isWithinShift(60, startMinutes: start, endMinutes: end), isTrue,
          reason: '٠١:٠٠ داخلَها — بعد منتصف الليل');
      expect(isWithinShift(600, startMinutes: start, endMinutes: end), isFalse,
          reason: '١٠:٠٠ صباحاً خارجَها');
      expect(isWithinShift(120, startMinutes: start, endMinutes: end), isFalse,
          reason: '٠٢:٠٠ هي النهايةُ فخارجَها');
    });

    // طرفٌ معدومٌ = بلا حدّ. مَن لم يُسجَّل دوامُه **يُحجز له** لا يُمنع.
    test('ورديّةٌ غيرُ مسجَّلةٍ لا تمنع', () {
      expect(isWithinShift(0), isTrue);
      expect(isWithinShift(700, startMinutes: 600), isTrue);
      expect(isWithinShift(700, endMinutes: 1200), isTrue);
    });

    test('طرفان متساويان = دوامٌ كاملُ اليوم', () {
      expect(isWithinShift(0, startMinutes: 540, endMinutes: 540), isTrue);
      expect(isWithinShift(1439, startMinutes: 540, endMinutes: 540), isTrue);
    });

    test('`minuteOfDayFor` يحوّل الوقتَ لا التاريخ', () {
      expect(minuteOfDayFor(DateTime(2026, 8, 22, 10, 30)), 630);
      expect(minuteOfDayFor(DateTime(2030, 1, 1, 10, 30)), 630);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('استحقاقُ التذكير', () {
    final now = DateTime(2026, 8, 22, 10);

    test('مجدولٌ ومضى وقتُه ⇒ مستحقّ', () {
      expect(
        isReminderDue(
            state: 'scheduled',
            scheduledAt: DateTime(2026, 8, 22, 9),
            now: now),
        isTrue,
      );
    });

    test('مجدولٌ ولم يحن ⇒ غيرُ مستحقّ', () {
      expect(
        isReminderDue(
            state: 'scheduled',
            scheduledAt: DateTime(2026, 8, 22, 11),
            now: now),
        isFalse,
      );
    });

    // ما فُتح لا يعود مستحقّاً — وإلّا تكرّر إرسالُه على العميل.
    test('ما فُتح أو صُرف عنه ليس مستحقّاً ولو مضى وقتُه', () {
      for (final s in ['opened', 'dismissed']) {
        expect(
          isReminderDue(
              state: s, scheduledAt: DateTime(2026, 8, 22, 8), now: now),
          isFalse,
          reason: s,
        );
      }
    });

    test('اللحظةُ نفسُها مستحقّة', () {
      expect(
        isReminderDue(state: 'scheduled', scheduledAt: now, now: now),
        isTrue,
      );
    });

    test('الجدولةُ تطرح الإزاحةَ من الموعد', () {
      expect(
        reminderScheduleFor(DateTime(2026, 8, 22, 17), 60),
        DateTime(2026, 8, 22, 16),
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('رابطُ واتساب', () {
    // ⚠️ **الصيغةُ الدوليّةُ شرطٌ، والصفرُ البادئُ يُبطلها.**
    //
    // كانت هذه المجموعةُ تؤكّد `wa.me/0791234567` — أي رقماً **يبدأ بصفر**،
    // وهو غيرُ صالحٍ عند واتساب: لا رقمَ دوليٌّ يبدأ بصفر. فكان التوكيدُ
    // **يوثّق العطبَ لا يحرسه**، والتعليقُ فوقَ الدالّة يحذّر من عينِ ما
    // تفعله. وُحِّد المسارُ 2026-09-12 على `normalizeWhatsAppPhone` —
    // محرّكِ إرسالِ الفواتير وكشوفِ الحساب نفسِه.
    String? link(String? phone, {String cc = '962'}) => whatsappReminderLink(
          phone: phone,
          message: 'x',
          defaultCountryCode: cc,
        );

    test('المحلّيُّ يصير دوليّاً — ولا يبقى الصفرُ البادئ', () {
      final url = link('079-123 4567');
      expect(url, contains('wa.me/962791234567'));
      expect(url, isNot(contains('wa.me/0')),
          reason: 'صفرٌ بادئٌ في رابطٍ دوليّ — واتساب يرفضه');
      expect(url, isNot(contains('-')));
      expect(url, isNot(contains(' ')));
    });

    test('يزيل `+` من الصيغة الدوليّة', () {
      expect(link('+962791234567'), contains('wa.me/962791234567'));
    });

    test('والأرقامُ العربيّةُ الهنديّةُ تُحوَّل ولا تُمسَح', () {
      // كانت تُمسَح بالكامل فيعود `null` — زرٌّ معطَّلٌ بلا سببٍ مفهوم.
      expect(link('٠٧٩١٢٣٤٥٦٧'), contains('wa.me/962791234567'));
    });

    // ⚠️ رابطٌ يفشل صامتاً أسوأُ من زرٍّ معطَّل: الموظَّفُ يظنّ أنه أرسل.
    test('رقمٌ معدومٌ أو بلا أرقامٍ ⇒ لا رابط', () {
      expect(link(null), isNull);
      expect(link('---'), isNull);
      expect(link(''), isNull);
    });

    test('ورمزُ دولةٍ غيرُ مضبوطٍ ⇒ لا رابط', () {
      // الإعدادُ فارغٌ في تنصيبةٍ جديدة؛ ورابطٌ بلا رمزِ دولةٍ يفتح صفحةَ
      // «الرقمُ غيرُ صالح» — فالزرُّ المعطَّلُ أصدق.
      expect(link('0791234567', cc: ''), isNull);
    });

    test('يُرمّز النصَّ العربيَّ فلا يكسر الرابط', () {
      final url = whatsappReminderLink(
        phone: '0791234567',
        message: 'مرحباً',
        defaultCountryCode: '962',
      );
      expect(url, isNot(contains('مرحباً')));
      expect(url, contains('%'));
    });

    test('نصُّ الرسالة يذكر العميلَ والخدمةَ والوقت', () {
      final msg = bookingReminderMessage(
        customerName: 'أحمد',
        serviceName: 'قص شعر',
        timeLabel: '05:00 م',
      );
      expect(msg, contains('أحمد'));
      expect(msg, contains('قص شعر'));
      expect(msg, contains('05:00 م'));
    });

    test('اسمُ المنشأة يُضاف حين يوجد ويُحذف حين لا', () {
      expect(
        bookingReminderMessage(
            customerName: 'أ',
            serviceName: 'س',
            timeLabel: 'و',
            businessName: 'صالون النور'),
        contains('صالون النور'),
      );
      final without = bookingReminderMessage(
          customerName: 'أ', serviceName: 'س', timeLabel: 'و',
          businessName: '  ');
      expect(without, isNot(contains('في  ')));
    });
  });
}
