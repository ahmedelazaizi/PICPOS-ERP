// خطوةُ «دليل الحسابات» — بندُ المالك ٦، الخطوة ٦. **معاينةٌ لا كتابة.**
//
// الدليلُ القياسيُّ (‏IFRS — سبعُ مجموعاتٍ رئيسيّة) يُزرَع في القاعدة عند أوّل
// فتح، قبل المعالج — كما كان دائماً. فالخطوةُ تعرضه ليعرف المستخدمُ ما سيعمل
// عليه، ولا تُعيد زرعَه.
//
// ⚠️ **ولا «أرصدة افتتاحيّة» هنا**: المعالجُ القديمُ لا يدعمها، والقيدُ
//    الافتتاحيُّ يحتاج دليلاً مربوطاً وسنةً ماليّةً مفتوحة — وكلاهما يُنشأ
//    عند تشغيل الإعداد نفسِه. فهي من «القيود اليومية» بعده.
part of '../setup_wizard_screen.dart';

extension _SetupWizardChartPreviewExt on _SetupWizardScreenState {
  Widget _buildChartPreviewStep() {
    return FutureBuilder<List<Account>>(
      future: _accountsPreview(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final accounts = snap.data ?? const <Account>[];
        final roots = accounts.where((a) => a.parentId == null).toList()
          ..sort((a, b) => a.code.compareTo(b.code));
        // المجموعاتُ الرئيسيّةُ رموزٌ برقمٍ واحد (‏١ الأصول … ٧ الختاميّة)؛
        // وجذورٌ أخرى بلا أبٍ (‏6311 … 75) تُعَدّ ولا تُعرَض مجموعاتٍ.
        final groups = roots.where((a) => a.code.length == 1).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _inlineNote(
              context,
              icon: PhosphorIconsBold.treeStructure,
              tone: AppColors.success,
              title: accounts.isEmpty
                  ? tr('الدليل القياسي يُزرَع عند تشغيل الإعداد')
                  : tr('الدليل القياسي جاهز — {p0} حساب', {'p0': accounts.length}),
              body: tr('شجرة حسابات كاملة وفق IFRS مربوطة بالمبيعات والمشتريات والمخزون والخزينة. عدّلها أو أضف إليها لاحقاً من «دليل الحسابات».'),
            ),
            const SizedBox(height: 14),
            if (groups.isNotEmpty)
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth < 700 ? 2 : 3;
                  const gap = 10.0;
                  final w = (c.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final g in groups)
                        SizedBox(
                          width: w,
                          child: _accountGroupCard(g, accounts),
                        ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 14),
            _inlineNote(
              context,
              icon: PhosphorIconsBold.info,
              tone: AppColors.info,
              title: tr('الأرصدة الافتتاحية'),
              body: tr('تُدخَل بعد الإعداد بقيدٍ افتتاحيٍّ من «القيود اليومية» — بعد أن تُنشأ السنة المالية الحالية.'),
            ),
          ],
        );
      },
    );
  }

  /// قراءةٌ واحدةٌ مذكَّرة — لا تيّارَ drift (‏يعلّق اختبارَ الودجت).
  Future<List<Account>> _accountsPreview() {
    return _accountsLoad ??= () async {
      try {
        return await ref.read(accountingRepositoryProvider).getAllAccounts();
      } catch (e) {
        debugPrint('[SetupWizard] accounts preview failed: $e');
        return const <Account>[];
      }
    }();
  }

  Widget _accountGroupCard(Account group, List<Account> all) {
    final theme = Theme.of(context);
    final children = all.where((a) => a.parentId == group.id).toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                group.code,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _brandInk(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  trData(group.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final c in children.take(4))
            Text(
              '${c.code}  ${trData(c.name)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: _mutedInk(context)),
            ),
          if (children.length > 4)
            Text(
              tr('+ {p0} أخرى', {'p0': children.length - 4}),
              style: TextStyle(fontSize: 11.5, color: _mutedInk(context)),
            ),
        ],
      ),
    );
  }
}
