// خطوةُ «الصناديق والبنوك» — بندُ المالك ٦، الخطوة ٥ (‏المستقلّ وحدَه).
//
// القاعدةُ تُزرَع عند أوّل فتحٍ بثلاثة صناديقَ افتراضيّة: صندوقُ الكاشير
// (`cash`) والحسابُ البنكيّ (`bank`) وصندوقُ تحويل كليك (`click`). والخطوةُ
// **تسمّيها لا تُنشئها**: الحقولُ تبدأ بأسمائها الحاليّة من القاعدة، وما لم
// يتغيّر لا يُكتَب — وإعادةُ التسمية تنتقل إلى الحساب المرتبط ذرّيّاً.
//
// ⚠️ والصندوقُ الرئيسيّ (‏المركزيّ) لا يُعرَض: ليس صندوقَ بيعٍ ولا يُسمّى
//    عند التنصيب.
part of '../setup_wizard_screen.dart';

extension _SetupWizardCashBanksExt on _SetupWizardScreenState {
  Widget _buildCashBanksStep() {
    _ensureSafesLoaded();
    return FutureBuilder<void>(
      future: _safesLoad,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _safeCard(
              icon: PhosphorIconsBold.cashRegister,
              title: tr('صندوق الكاشير'),
              hint: tr('يستقبل مبيعات نقطة البيع النقدية'),
              children: [
                _buildTextField(
                  key: const Key('setup_safe_cash'),
                  controller: _cashBoxNameController,
                  label: tr('اسم الصندوق'),
                  icon: PhosphorIconsBold.wallet,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _safeCard(
              icon: PhosphorIconsBold.bank,
              title: tr('الحساب البنكي'),
              hint: tr('مدفوعات البطاقات والإيداعات'),
              children: [
                _buildTextField(
                  key: const Key('setup_safe_bank'),
                  controller: _bankSafeNameController,
                  label: tr('اسم الحساب'),
                  icon: PhosphorIconsBold.bank,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        key: const Key('setup_bank_name'),
                        controller: _bankNameController,
                        label: tr('اسم البنك'),
                        icon: PhosphorIconsBold.buildings,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        key: const Key('setup_bank_account'),
                        controller: _bankAccountController,
                        label: tr('رقم الحساب / IBAN'),
                        icon: PhosphorIconsBold.hash,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _safeCard(
              icon: PhosphorIconsBold.arrowsLeftRight,
              title: tr('صندوق تحويل كليك'),
              hint: tr('تحويلات CliQ والمحافظ الإلكترونية'),
              children: [
                _buildTextField(
                  key: const Key('setup_safe_cliq'),
                  controller: _cliqSafeNameController,
                  label: tr('اسم الصندوق'),
                  icon: PhosphorIconsBold.arrowsLeftRight,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _inlineNote(
              context,
              icon: PhosphorIconsBold.info,
              tone: AppColors.info,
              title: tr('صناديق إضافية'),
              body: tr('أضف صناديق وحسابات بنكية أخرى من شاشة «الخزينة» بعد الإعداد — كلٌّ منها يُربط بحسابه في دليل الحسابات تلقائياً.'),
            ),
          ],
        );
      },
    );
  }

  Widget _safeCard({
    required IconData icon,
    required String title,
    required String hint,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _brandInk(context)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  hint,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: _mutedInk(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}
