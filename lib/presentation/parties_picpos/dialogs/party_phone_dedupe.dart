import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ural_erp/core/i18n/tr.dart';

import '../../../data/providers/customer_picker_providers.dart';
import '../../../data/providers/providers.dart';

/// نتيجةُ فحص تكرار الهاتف عند الإضافة السريعة.
class PhoneDedupeResult {
  const PhoneDedupeResult._(this.existingId, this.cancelled);

  /// لا تكرار، أو اختار المستخدم «إنشاء على أي حال».
  const PhoneDedupeResult.proceed() : this._(null, false);

  /// اختار المستخدم العميلَ الموجود.
  const PhoneDedupeResult.useExisting(int id) : this._(id, false);

  const PhoneDedupeResult.cancelled() : this._(null, true);

  final int? existingId;
  final bool cancelled;
}

/// إن كان [phone] مسجَّلاً لعميلٍ (داخل نطاق فرع المستخدم) يعرض «هذا الرقم
/// مسجَّل باسم X» ويترك القرار للمستخدم. أكثرُ من عميلٍ بالرقم ⇒ يختار
/// واحداً منهم.
Future<PhoneDedupeResult> checkPhoneDuplicate(
  BuildContext context,
  WidgetRef ref,
  String phone,
) async {
  final List<Party> matches;
  try {
    matches = await ref.read(customersByPhoneProvider(phone).future);
  } catch (_) {
    return const PhoneDedupeResult.proceed(); // الفحصُ لا يمنع الحفظ
  }
  if (matches.isEmpty || !context.mounted) {
    return const PhoneDedupeResult.proceed();
  }
  final picked = await showDialog<Object>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: Directionality.of(context),
      child: AlertDialog(
        title: Text(tr('هذا الرقم مسجَّل باسم {p0}', {'p0': matches.first.name})),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in matches)
                ListTile(
                  dense: true,
                  title: Text(p.name),
                  subtitle: Text(p.phone ?? ''),
                  trailing: TextButton(
                    key: ValueKey('use_existing_${p.id}'),
                    onPressed: () => Navigator.pop(ctx, p.id),
                    child: Text(tr('استخدام العميل الموجود')),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('create_anyway'),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('إنشاء على أي حال')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('إلغاء')),
          ),
        ],
      ),
    ),
  );
  if (picked is int) return PhoneDedupeResult.useExisting(picked);
  if (picked == false) return const PhoneDedupeResult.proceed();
  return const PhoneDedupeResult.cancelled();
}
