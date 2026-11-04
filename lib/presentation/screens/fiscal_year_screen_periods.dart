part of 'fiscal_year_screen.dart';

extension _FiscalYearScreenPeriods on _FiscalYearScreenState {
  Widget _buildPeriodTile(BuildContext context, IAccountingRepository repo,
      AccountingPeriodData period, bool yearClosed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.picposHairline.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Icon(
            period.isClosed ? PhosphorIconsBold.lockSimple : PhosphorIconsBold.calendarBlank,
            size: 16,
            color: period.isClosed ? AppColors.error : AppColors.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(period.name, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Text(
            '${_dateFormat.format(period.startDate)} — ${_dateFormat.format(period.endDate)}',
            style: GoogleFonts.cairo(fontSize: 11, color: context.picposMuted),
          ),
          const SizedBox(width: 12),
          _buildStatusBadge(period.isClosed, false),
          if (!yearClosed) ...[
            const SizedBox(width: 8),
            if (!period.isClosed &&
                (ref.watch(currentUserPermissionsProvider).asData?.value ?? const <String>[])
                    .contains(FiscalPermissionCodes.fiscalPeriodClose))
              IconButton(
                icon: const Icon(PhosphorIconsBold.lockSimple, size: 14),
                tooltip: tr('إقفال الفترة'),
                onPressed: _savingPeriodIds.contains(period.id) ? null : () async {
                  setState(() => _savingPeriodIds.add(period.id));
                  try {
                    final userId = ref.read(authProvider).user?.id;
                    if (userId == null) throw Exception('المستخدم غير مسجل الدخول');
                    await repo.closeAccountingPeriod(period.id, userId);
                    if (context.mounted) {
                      AppToast.show(context, tr('تم إقفال فترة {p0}', {'p0': period.name}));
                    }
                  } finally {
                    if (mounted) setState(() => _savingPeriodIds.remove(period.id));
                  }
                },
              )
            else if (period.isClosed)
              IconButton(
                icon: const Icon(PhosphorIconsBold.lockSimpleOpen, size: 14),
                tooltip: tr('إعادة فتح الفترة'),
                onPressed: _savingPeriodIds.contains(period.id) ? null : () async {
                  // فحص صريح بلا أي استثناء للمدير — `modify_closed_period`
                  // كود فصل سلطات (segregation of duties)، فمينفعش يتفتح
                  // بكلمة مرور مدير زي بقية الأزرار. الصلاحية لازم تتمنح
                  // صراحة للمستخدم اللي هيعمل الفعل، مفيش باب خلفي.
                  final perms =
                      ref.read(currentUserPermissionsProvider).asData?.value ??
                          const <String>[];
                  if (!canReopenClosedPeriod(perms)) {
                    if (context.mounted) {
                      AppToast.show(
                        context,
                        tr('ليس لديك صلاحية إعادة فتح فترة مقفلة'),
                        type: ToastType.error,
                      );
                    }
                    return;
                  }
                  setState(() => _savingPeriodIds.add(period.id));
                  try {
                    final userId = ref.read(authProvider).user?.id;
                    if (userId == null) throw Exception('المستخدم غير مسجل الدخول');
                    await repo.reopenAccountingPeriod(period.id, userId);
                    if (context.mounted) {
                      AppToast.show(context, tr('تم إعادة فتح فترة {p0}', {'p0': period.name}));
                    }
                  } finally {
                    if (mounted) setState(() => _savingPeriodIds.remove(period.id));
                  }
                },
              ),
          ],
        ],
      ),
    );
  }
}
