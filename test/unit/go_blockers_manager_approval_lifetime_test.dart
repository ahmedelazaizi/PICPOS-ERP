// ═══════════════════════════════════════════════════════════════════════════
// مانعُ Go ١‑٥ — إذنُ المدير لا يعبر الخروجَ ولا تبديلَ المستخدم
// ═══════════════════════════════════════════════════════════════════════════
//
// `ManagerApprovalCache` تحمل أذوناً حيّةً ستّين ثانية. وتوثيقُها يقول
// صراحةً إنّ `clear()` «تُنادى عند الخروج لضمان ألّا يعبر إذنٌ بين جلستَين
// على نفس الجهاز».
//
// 🔴 والمقيس: `clear()` كانت **بلا مستدعٍ في المستودع كلِّه**. فمديرٌ يصادق
// على فعلٍ ثمّ يسلّم الجهازَ لكاشيرٍ خلال الدقيقة يترك له إذناً جاهزاً
// يُصرَف على أوّل فعلٍ بنفس الكود — بلا كلمة مرور وبلا أثر.
//
// وهو نفسُ ما تمنعه `ServerProxy.clearSessions()` للتوكنات في نفس الدالّة
// — أي أنّ النيّةَ كانت مكتوبةً والتنفيذُ ناقصاً.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/services/manager_approval_cache.dart';

const _perm = 'pos_discount';

void main() {
  late ProviderContainer container;

  setUp(() {
    ManagerApprovalCache.instance.clear();
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    ManagerApprovalCache.instance.clear();
  });

  test('التجهيزة: الإذنُ الممنوحُ حيٌّ قبل الخروج', () {
    ManagerApprovalCache.instance.grant(_perm);
    expect(ManagerApprovalCache.instance.isFresh(_perm), isTrue,
        reason: 'مرساةٌ — لولاها لمرّ الاختبارُ التالي لأنّ الإذنَ لم يُمنَح '
            'أصلاً لا لأنّه مُسح');
  });

  test('الخروجُ يمسح إذنَ المدير', () {
    ManagerApprovalCache.instance.grant(_perm);
    expect(ManagerApprovalCache.instance.isFresh(_perm), isTrue);

    container.read(authProvider.notifier).logout();

    // 🔴 المعطوب: يبقى حيّاً ٦٠ ثانيةً، فيستهلكه المستخدمُ التالي.
    expect(ManagerApprovalCache.instance.consume(_perm), isFalse,
        reason: 'إذنُ المدير لا يعبر الخروج');
  });

  test('الإذنُ يُستهلَك مرّةً واحدةً — لا يُصرَف مرّتين', () {
    ManagerApprovalCache.instance.grant(_perm);
    expect(ManagerApprovalCache.instance.consume(_perm), isTrue);
    expect(ManagerApprovalCache.instance.consume(_perm), isFalse,
        reason: 'انحدارٌ: العقدُ «إذنٌ لفعلٍ واحد»');
  });

  test('الوسمُ بالباب يمنع عبورَ الإذن بين بابَين', () {
    // انحدارٌ على إصلاحٍ سابق — يبقى محروساً مع هذا التغيير.
    ManagerApprovalCache.instance.grant(_perm, scope: 'line');
    expect(ManagerApprovalCache.instance.consume(_perm, scope: 'invoice'),
        isFalse,
        reason: 'إذنُ خصمِ سطرٍ لا يُصرَف خصماً على الفاتورة كلِّها');
    expect(ManagerApprovalCache.instance.consume(_perm, scope: 'line'), isTrue);
  });
}
