// لوحُ عرضِ الحساب في دليل الحسابات — النصفُ «التفاصيل» من الرئيسيّ/التفصيليّ.
//
// ═══ قرارُ المالك (البند ١٩، المرحلة G) ═══
//
// الشجرةُ والتفاصيلُ **ظاهرتان معاً**: الشجرةُ (~٤٠٪) يميناً، واللوحُ (~٦٠٪)
// بجانبها، لا محتوىً بعرضٍ كاملٍ يتبدّل. واللوحُ لا يختفي حين لا اختيار —
// يقول **ماذا يُفعل** ([CoaEmptyPanel]) بدل فراغٍ يُقرأ عطلاً.
//
// وعند الاختيار: ترويسةٌ (رمز · اسم · شاراتُ النوع والطبيعة والحالة)، ومسارُ
// الآباء، ورصيدُ السنة الماليّة (مدين · دائن · صافٍ)، وآخرُ الحركات بربطٍ إلى
// دفتر الأستاذ مرشَّحاً على الحساب، وعددُ الأبناء.
//
// ⚠️ **والتحريرُ ليس هنا** — في `AccountDetailPanel` نفسِه (نفسُ التحقّق
// والقواعد وحسابات النظام)، يُفتَح داخلَ اللوح نفسِه بزرّ «تعديل».
//
// ⚠️ **ولا `data/database`**: قيمٌ خالصةٌ تدخل، ونداءاتٌ تخرج — حارسُ
// `presentation_db_import_guard`.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/i18n/tr.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/account_facts.dart';
import '../picpos_shell/picpos_empty_state.dart';
import '../picpos_shell/picpos_stat_tile.dart';
import '../picpos_shell/picpos_surface.dart';
import '../screens/coa/coa_shared.dart';
import 'chart_of_accounts_detail_panel.dart';
import 'chart_of_accounts_insight.dart';

/// إطارُ اللوح المشترك — بطاقةٌ مسطّحةٌ بحدٍّ شعريّ (‏DESIGN.md: Cards).
class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: context.picposCard,
          border: Border.all(color: context.picposHairline),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

/// اللوحُ قبل أيّ اختيار.
class CoaEmptyPanel extends StatelessWidget {
  const CoaEmptyPanel({super.key});

  @override
  Widget build(BuildContext context) => _PanelCard(
        child: PicPosEmptyState(
          key: const Key('coa_empty_panel'),
          icon: PhosphorIconsBold.cursorClick,
          title: tr('اختر حساباً من الشجرة'),
          hint: tr('تظهر هنا بياناتُ الحساب ورصيدُه في السنة الماليّة وآخرُ حركاته، ومنها تعدّله أو تضيف تحته حساباً فرعيّاً.'),
        ),
      );
}

/// عرضُ الحساب المختار.
class AccountOverviewPanel extends StatelessWidget {
  const AccountOverviewPanel({
    super.key,
    required this.account,
    required this.path,
    required this.childCount,
    required this.insight,
    required this.onEdit,
    required this.onAddChild,
    required this.onOpenLedger,
    required this.onClose,
    this.onSelectAncestor,
  });

  final AccountPanelValue account;

  /// الآباءُ من الجذر إلى الأب المباشر.
  final List<AccountParentOption> path;

  /// عددُ الأبناء المباشرين.
  final int childCount;

  /// `null` ⇒ لم يبدأ التحميل بعد.
  final Future<AccountInsight>? insight;

  final VoidCallback onEdit;
  final VoidCallback onAddChild;

  /// يفتح دفترَ الأستاذ مرشَّحاً على الحساب ومدى [AccountInsight].
  final void Function(AccountInsight? insight) onOpenLedger;
  final VoidCallback onClose;
  final ValueChanged<int>? onSelectAncestor;

  @override
  Widget build(BuildContext context) {
    // ⚠️ **قائمةٌ واحدةٌ تتمرّر بترويستها** لا ترويسةٌ ثابتةٌ فوق قائمة: على
    //    الضيّق يُكدَّس اللوحُ تحت الشجرة بنصف الارتفاع، وترويسةٌ ثابتةٌ
    //    (~١٩٠ بكسلاً) أطولُ من ذلك تفيض.
    return _PanelCard(
      child: FutureBuilder<AccountInsight>(
        future: insight,
        builder: (context, snap) => ListView(
          key: const Key('coa_overview_panel'),
          padding: EdgeInsets.zero,
          children: [
            _header(context),
            Divider(height: 1, color: context.picposHairline),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BalanceTiles(snapshot: snap, childCount: childCount),
                  const SizedBox(height: 16),
                  _MovementsBlock(
                    snapshot: snap,
                    onOpenLedger: () => onOpenLedger(snap.data),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final info = kAccountTypeConfig[account.accountType];
    final typeColor = info?.color ?? context.picposBrandInk;
    final credit = normalBalanceFor(account.accountType) == 'credit';
    final isView = account.accountNature == kAccountNatureView;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  account.code,
                  key: const Key('coa_overview_code'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: typeColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  trData(account.name),
                  key: const Key('coa_overview_name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: context.picposText,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                tooltip: tr('إلغاء التحديد'),
                icon: Icon(PhosphorIconsBold.x,
                    size: 15, color: context.picposMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (info != null) _Badge(label: info.label, tone: typeColor),
              _Badge(
                label: isView ? tr('رئيسي — لا يُرحَّل عليه') : tr('تفصيلي — يُرحَّل عليه'),
                tone: context.picposBrandInk,
              ),
              _Badge(
                label: credit ? tr('طبيعته دائنة') : tr('طبيعته مدينة'),
                tone: context.picposMuted,
              ),
              _Badge(
                label: account.isActive ? tr('نشط') : tr('موقوف'),
                tone: account.isActive
                    ? AppColors.statusSuccess(context)
                    : AppColors.statusError(context),
              ),
              if (account.isSystem)
                _Badge(
                  label: tr('حساب نظام'),
                  tone: AppColors.statusInfo(context),
                  icon: PhosphorIconsBold.lock,
                ),
              if (account.isHiddenFromEntries)
                _Badge(
                  label: tr('مخفي من القيود'),
                  tone: AppColors.statusWarning(context),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _Breadcrumb(
            path: path,
            current: account,
            onSelect: onSelectAncestor,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('coa_overview_edit'),
                onPressed: onEdit,
                icon: const Icon(PhosphorIconsBold.pencilSimple, size: 15),
                label: Text(tr('تعديل')),
              ),
              OutlinedButton.icon(
                key: const Key('coa_overview_add_child'),
                onPressed: onAddChild,
                icon: const Icon(PhosphorIconsBold.plus, size: 15),
                label: Text(tr('إضافة حساب فرعي')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// شارةٌ مستديرةٌ بلونٍ دلاليّ (‏DESIGN.md: Status pill).
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.tone, this.icon});
  final String label;
  final Color tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          border: Border.all(color: tone.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: tone),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: tone,
              ),
            ),
          ],
        ),
      );
}

/// مسارُ الآباء — كلُّ أبٍ قابلٌ للنقر فيُختار.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.path,
    required this.current,
    required this.onSelect,
  });

  final List<AccountParentOption> path;
  final AccountPanelValue current;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final muted = context.picposMuted;
    final style = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: muted);
    // ⚠️ `chevron_right` تنعكس وحدَها في RTL (`matchTextDirection`) فتشير
    //    دائماً نحو نهاية السطر — أي نحو الابن.
    final sep = Icon(Icons.chevron_right, size: 14, color: muted);

    return Wrap(
      key: const Key('coa_overview_breadcrumb'),
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 2,
      children: [
        Icon(PhosphorIconsBold.treeStructure, size: 13, color: muted),
        const SizedBox(width: 4),
        if (path.isEmpty)
          Text(tr('حسابٌ رئيسيّ في أعلى الشجرة'), style: style)
        else
          for (final p in path) ...[
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onSelect == null ? null : () => onSelect!(p.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('${p.code} ${trData(p.name)}', style: style),
              ),
            ),
            sep,
          ],
        if (path.isNotEmpty)
          Text(
            trData(current.name),
            style: style.copyWith(
              fontWeight: FontWeight.w800,
              color: context.picposText,
            ),
          ),
      ],
    );
  }
}

String _amount(double v) => formatAccountAmount(v);

String _date(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// مدين · دائن · صافٍ · أبناء.
class _BalanceTiles extends StatelessWidget {
  const _BalanceTiles({required this.snapshot, required this.childCount});

  final AsyncSnapshot<AccountInsight> snapshot;
  final int childCount;

  @override
  Widget build(BuildContext context) {
    final data = snapshot.data;
    final waiting = data == null && !snapshot.hasError;
    String v(double Function(AccountInsight i) f) =>
        data == null ? (waiting ? '…' : '—') : _amount(f(data));
    final net = data?.net ?? 0;

    final tiles = <Widget>[
      PicPosStatTile(
        key: const Key('coa_balance_debit'),
        label: tr('مدين'),
        value: v((i) => i.debit),
        icon: PhosphorIconsBold.arrowDown,
        accent: context.picposBrandInk,
      ),
      PicPosStatTile(
        key: const Key('coa_balance_credit'),
        label: tr('دائن'),
        value: v((i) => i.credit),
        icon: PhosphorIconsBold.arrowUp,
        accent: context.picposBrandInk,
      ),
      PicPosStatTile(
        key: const Key('coa_balance_net'),
        label: tr('الصافي'),
        value: v((i) => i.net),
        icon: PhosphorIconsBold.scales,
        accent: net < 0
            ? AppColors.statusError(context)
            : AppColors.statusSuccess(context),
      ),
      PicPosStatTile(
        key: const Key('coa_child_count'),
        label: tr('الحسابات الفرعية'),
        value: '$childCount',
        icon: PhosphorIconsBold.folder,
        accent: context.picposMuted,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BlockTitle(
          title: data == null
              ? tr('رصيد السنة المالية')
              : tr('رصيد السنة المالية {p0}', {'p0': trData(data.periodLabel)}),
          subtitle: data == null
              ? null
              : tr('من {p0} إلى {p1} — القيود المرحّلة فقط', {
                  'p0': _date(data.from),
                  'p1': _date(data.to),
                }),
        ),
        const SizedBox(height: 10),
        // أربعةٌ في صفٍّ على العريض، واثنان في صفٍّ على الضيّق.
        LayoutBuilder(builder: (context, c) {
          final perRow = c.maxWidth >= 520 ? 4 : 2;
          const gap = 10.0;
          final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final t in tiles) SizedBox(width: w, child: t)],
          );
        }),
        if (snapshot.hasError) ...[
          const SizedBox(height: 8),
          Text(
            tr('تعذّر تحميل الرصيد والحركات.'),
            key: const Key('coa_insight_error'),
            style: TextStyle(fontSize: 12, color: AppColors.statusError(context)),
          ),
        ],
      ],
    );
  }
}

/// عنوانُ كتلة: شريطُ العلامة ثمّ العنوان والسطرُ الخافت (‏DESIGN.md: Block header).
class _BlockTitle extends StatelessWidget {
  const _BlockTitle({required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 3.5,
            height: 15,
            decoration: BoxDecoration(
              color: context.picposBrandInk,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: context.picposText,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: context.picposMuted,
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      );
}

/// آخرُ الحركات — جدولٌ مصغّرٌ بربطٍ إلى دفتر الأستاذ.
class _MovementsBlock extends StatelessWidget {
  const _MovementsBlock({required this.snapshot, required this.onOpenLedger});
  final AsyncSnapshot<AccountInsight> snapshot;
  final VoidCallback onOpenLedger;

  @override
  Widget build(BuildContext context) {
    final data = snapshot.data;
    final muted = context.picposMuted;

    Widget body;
    if (data == null && !snapshot.hasError) {
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (data == null || data.recent.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: Text(
          snapshot.hasError
              ? tr('تعذّر تحميل الرصيد والحركات.')
              : tr('لا حركات مرحّلة على هذا الحساب في السنة الماليّة.'),
          key: const Key('coa_movements_empty'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: muted),
        ),
      );
    } else {
      body = Column(
        children: [
          _MovementRow.header(context),
          for (final m in data.recent) _MovementRow(movement: m),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BlockTitle(
          title: tr('آخر الحركات'),
          subtitle: data == null
              ? null
              : tr('{p0} من {p1} حركة في السنة', {
                  'p0': data.recent.length,
                  'p1': data.movementCount,
                }),
          trailing: TextButton.icon(
            key: const Key('coa_open_ledger'),
            onPressed: onOpenLedger,
            icon: const Icon(PhosphorIconsBold.book, size: 14),
            label: Text(tr('عرض في دفتر الأستاذ')),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: context.picposHairline),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: body,
        ),
      ],
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement}) : _header = false;
  const _MovementRow._header() : movement = null, _header = true;

  static Widget header(BuildContext context) => const _MovementRow._header();

  final AccountMovement? movement;
  final bool _header;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final style = _header
        ? TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: context.picposMuted,
          )
        : TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: context.picposText,
            fontFeatures: const [FontFeature.tabularFigures()],
          );

    Widget cell(String s, {int flex = 2, bool end = false}) => Expanded(
          flex: flex,
          child: Text(
            s,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: end ? TextAlign.end : TextAlign.start,
            style: style,
          ),
        );

    String amt(double v) => v.abs() < 0.005 ? '—' : _amount(v);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _header ? context.picposField : null,
        border: Border(top: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          cell(m == null ? tr('التاريخ') : _date(m.date), flex: 3),
          cell(m == null ? tr('رقم القيد') : m.entryNumber, flex: 3),
          cell(m == null ? tr('البيان') : m.description, flex: 5),
          cell(m == null ? tr('مدين') : amt(m.debit), end: true, flex: 3),
          cell(m == null ? tr('دائن') : amt(m.credit), end: true, flex: 3),
        ],
      ),
    );
  }
}
