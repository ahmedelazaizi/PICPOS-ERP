// ═══════════════════════════════════════════════════════════════════════════
// انحدارُ المهمة ٦ — إثباتُ إغلاقه (Task 6أ)
// ═══════════════════════════════════════════════════════════════════════════
//
// المهمةُ ٦ جعلت `addOvertimeRecord` يرمي `StateError` لأيّ موظفٍ بلا
// `hoursPerDay` حين لا يُمرَّر `manualAmount`. و`HRNotifier` ليس `AsyncNotifier`
// وبلا `try/catch`، فالاستثناءُ كان يهبط في `PlatformDispatcher.onError` —
// يُسجَّل ويُعاد `true` — فلا التطبيقُ يسقط ولا المستخدمُ يرى شيئاً. الزرُّ
// يبدو أنه لم يفعل شيئاً، ولا سجلَّ ولا رسالة: **تسجيلُ الإضافي معطَّلٌ
// لكلّ الموظفين**، لا للـ`hourly` وحدَهم.
//
// هذا الاختبارُ يثبت الإغلاق مباشرةً على الطبقة التي كانت تبتلع الفشل:
// `HRNotifier.addOvertime` — لا على `hr_extensions.dart` (مُغطًّى في
// `overtime_amount_test.dart`) ولا بافتراض أن التغليف يعمل، بل بقياس
// القيمة المُعادة فعلياً من نداءٍ حقيقيّ عبر `ProviderContainer`.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/hr/hr_notifier.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  ProviderContainer containerFor() => ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );

  test(
    'موظفٌ بلا hoursPerDay وبلا manualAmount: addOvertime يُعيد رسالةَ خطأٍ '
    'لا يبتلع الاستثناءَ صامتاً',
    () async {
      final employeeId = await db.into(db.employees).insert(
          EmployeesCompanion.insert(name: 'موظف بلا ساعات', salary: const Value(5200)));
      // salaryType الافتراضيُّ 'monthly' و hoursPerDay غيرُ مُمرَّر — بالضبط
      // الحالةُ التي وصفها العنوانُ ١ في البريف: «لا واجهةَ تعرض hoursPerDay
      // لأحد، ولا حتى hourly». فأيُّ موظفٍ — لا الـ`hourly` وحده — يسقط هنا
      // لو حاول أحدٌ تسجيلَ إضافيٍّ له بلا مبلغٍ يدويّ.

      final container = containerFor();
      addTearDown(container.dispose);
      final notifier = container.read(hrFormProvider.notifier);

      // ── الدليلُ المقيس ────────────────────────────────────────────────────
      // قبل ٦أ: هذا النداءُ **يرمي** `StateError` عبر `await` عاريةٍ بلا
      // `try/catch` — وفي زرِّ الواجهة الحقيقي (`onPressed` غيرَ مُنتظَر من
      // Flutter) هذا الرميُ يهبط في `PlatformDispatcher.onError` بلا أن يراه
      // أحد. هنا ننتظره مباشرةً، فلو رمى لسقط الاختبارُ بذلك الاستثناء نفسه —
      // وهذا إثباتٌ أدقّ من محاولة تقليد زون الأخطاء غير المتزامن.
      final result = await notifier.addOvertime(
        employeeId: employeeId,
        date: DateTime(2026, 4, 7),
        hours: 2,
      );

      expect(result, isNotNull,
          reason: 'رسالةُ خطأٍ تُعاد للعرض، لا `null` بصمتٍ وكأنّ التسجيل نجح');
      expect(result, contains('ساعاتِ العمل اليومية'),
          reason: 'الرسالةُ تقود المستخدمَ إلى الحل — أدخِل الساعاتِ أو '
              'المبلغَ يدوياً');

      // وسجلُّ الإضافي لم يُكتب — الفشلُ لم يُخفَ ولم يُكتب نصفَ صفٍّ.
      final records = await db.select(db.overtimeRecords).get();
      expect(records, isEmpty);
    },
  );

  test(
    'نفسُ الموظف بمبلغٍ يدويّ: addOvertime يُعيد null (نجاح) ويكتب السجلّ',
    () async {
      final employeeId = await db.into(db.employees).insert(
          EmployeesCompanion.insert(name: 'موظف بلا ساعات', salary: const Value(5200)));

      final container = containerFor();
      addTearDown(container.dispose);
      final notifier = container.read(hrFormProvider.notifier);

      final result = await notifier.addOvertime(
        employeeId: employeeId,
        date: DateTime(2026, 4, 7),
        hours: 2,
        manualAmount: 120,
      );

      expect(result, isNull, reason: 'منفذُ الهروب أصبح موصولاً — لا يفشل');
      final records = await db.select(db.overtimeRecords).get();
      expect(records, hasLength(1));
      expect(records.single.amount, closeTo(120, 0.01));
    },
  );
}
